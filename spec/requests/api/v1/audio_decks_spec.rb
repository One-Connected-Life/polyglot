require "rails_helper"

# POST /api/v1/audio_decks (multipart) → enqueues ExtractDeckFromAudioJob.
RSpec.describe "Api::V1 audio_decks", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def upload(filename: "memo.m4a", content_type: "audio/m4a", bytes: "fakeaudio")
    file = Tempfile.new(["memo", File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: filename)
  end

  it "401s without a token" do
    post "/api/v1/audio_decks", params: { audio: upload }
    expect(response).to have_http_status(:unauthorized)
  end

  it "stages the file, creates a transcribing deck, and enqueues the job" do
    expect {
      post "/api/v1/audio_decks", params: { audio: upload, label: "Voicemail" }, headers: auth_headers(user)
    }.to have_enqueued_job(ExtractDeckFromAudioJob)
    expect(response).to have_http_status(:accepted)
    expect(json["deck"]).to include("name" => "Voicemail", "status" => "transcribing")
    expect(user.reload.generations_count).to eq(1)
  end

  it "422s without a file" do
    post "/api/v1/audio_decks", params: { label: "x" }, headers: auth_headers(user)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("audio_required")
  end

  it "422s on an unsupported file type" do
    post "/api/v1/audio_decks", params: { audio: upload(filename: "note.txt", content_type: "text/plain") },
         headers: auth_headers(user)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("unsupported_file_type")
  end
end
