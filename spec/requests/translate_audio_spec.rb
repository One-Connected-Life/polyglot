require "rails_helper"

# Contract for audio input on the Translate tab (#16): an uploaded or recorded clip
# is transcribed (self-hosted whisper.cpp, default Dutch), the transcript feeds the
# SAME Translator → results → Translated-deck pipeline as typed text, and the clip is
# persisted on a Recording for 2-day replay (separate from the delete-immediately
# /audio_decks voicemail flow). Transcriber + Translator are stubbed.
RSpec.describe "Translate audio", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def audio_upload(name: "spoken.m4a", type: "audio/mp4")
    fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.m4a"), type).tap do |f|
      allow(f).to receive(:original_filename).and_return(name)
    end
  end

  def stub_transcriber(text)
    allow_any_instance_of(Transcriber).to receive(:call).and_return(text)
  end

  def stub_translator(words)
    allow_any_instance_of(Translator).to receive(:call).and_return(words)
  end

  before { sign_in(user) }

  it "transcribes an uploaded clip, translates it, and saves into the Translated deck" do
    stub_transcriber("de hond rent in het park")
    stub_translator([
      { "target" => "hond", "article" => "de", "source" => "dog" },
      { "target" => "park", "article" => "het", "source" => "park" }
    ])

    expect {
      post translate_path, params: { audio: audio_upload, capture: "1" }
    }.to have_enqueued_job(EnrichTranslationsJob)

    expect(response).to have_http_status(:ok)
    deck = user.decks.find_by(slug: User::TRANSLATED_SLUG)
    expect(deck.terms.count).to eq(2)
    expect(deck.terms.first.translation("nl").text).to eq("hond")
  end

  it "persists the clip on a Recording (with the transcript and the audio attached)" do
    stub_transcriber("hallo wereld")
    stub_translator([{ "target" => "wereld", "source" => "world" }])

    expect {
      post translate_path, params: { audio: audio_upload, capture: "1" }
    }.to change(user.recordings, :count).by(1)

    rec = user.recordings.last
    expect(rec.transcript).to eq("hallo wereld")
    expect(rec.language).to eq("nl")
    expect(rec.audio).to be_attached
  end

  it "transcribes in the requested input language when given" do
    expect_any_instance_of(Transcriber).to receive(:call).and_return("the dog runs")
    allow(Transcriber).to receive(:new).with(language: "en").and_call_original
    stub_translator([{ "target" => "hond", "source" => "dog" }])

    post translate_path, params: { audio: audio_upload, capture: "1", input_language: "en" }

    expect(response).to have_http_status(:ok)
    expect(user.recordings.last.language).to eq("en")
  end

  it "defaults the transcription language to the user's target language (Dutch)" do
    expect(Transcriber).to receive(:new).with(language: "nl").and_call_original
    allow_any_instance_of(Transcriber).to receive(:call).and_return("brood")
    stub_translator([{ "target" => "brood", "source" => "bread" }])

    post translate_path, params: { audio: audio_upload, capture: "1" }
    expect(response).to have_http_status(:ok)
  end

  it "redirects with an alert when no speech is detected" do
    allow_any_instance_of(Transcriber).to receive(:call).and_raise(Transcriber::Error, "no speech detected in the audio")

    post translate_path, params: { audio: audio_upload, capture: "1" }
    expect(response).to redirect_to(new_translate_path)
    expect(user.recordings.count).to eq(0)
  end

  it "rejects a clip that is too large" do
    stub_const("TranslateController::MAX_AUDIO_BYTES", 1) # real fixture is bigger

    post translate_path, params: { audio: audio_upload, capture: "1" }
    expect(response).to redirect_to(new_translate_path)
    expect(user.recordings.count).to eq(0)
  end

  it "renders Record mode when ?mode=record and Upload mode when ?mode=upload" do
    get new_translate_path(mode: "record")
    expect(response).to have_http_status(:ok)
    get new_translate_path(mode: "upload")
    expect(response).to have_http_status(:ok)
  end
end
