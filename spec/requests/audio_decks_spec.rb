require "rails_helper"

# Contract for "upload your own audio → vocab deck" (issue #3): the HTTP behavior of
# the upload endpoint. The transcription/extraction itself is exercised in the job spec.
RSpec.describe "Audio decks", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def upload(filename: "sample.m4a", type: "audio/mp4")
    fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.m4a"), type).tap do |f|
      f.instance_variable_set(:@original_filename, filename)
    end
  end

  before { sign_in(user) }

  it "stages the upload, creates a transcribing deck, and enqueues extraction" do
    expect {
      post audio_decks_path, params: { audio: upload(filename: "Doctor Voicemail.m4a") }
    }.to change(user.decks, :count).by(1)
      .and have_enqueued_job(ExtractDeckFromAudioJob)

    deck = user.decks.last
    expect(deck.status).to eq("transcribing")
    expect(deck.name).to eq("Doctor Voicemail")
    expect(response).to redirect_to(root_path)
    expect(user.reload.generations_count).to eq(1)
  end

  it "rejects a request with no file" do
    expect {
      post audio_decks_path, params: {}
    }.not_to change(user.decks, :count)
    expect(response).to redirect_to(new_audio_deck_path)
  end

  it "rejects an unsupported file type" do
    expect {
      post audio_decks_path, params: { audio: upload(filename: "notes.txt", type: "text/plain") }
    }.not_to change(user.decks, :count)
    expect(response).to redirect_to(new_audio_deck_path)
  end

  it "suffixes the deck name when the slug already exists" do
    create(:deck, user: user, name: "Voicemail", slug: "voicemail", status: "ready")
    post audio_decks_path, params: { audio: upload(filename: "Voicemail.m4a") }
    expect(user.decks.last.name).to eq("Voicemail 2")
  end

  it "blocks upload once the generation cap is reached" do
    user.update!(generations_count: User::GENERATION_CAP)
    expect {
      post audio_decks_path, params: { audio: upload }
    }.not_to change(user.decks, :count)
    expect(response).to redirect_to(new_audio_deck_path)
  end
end
