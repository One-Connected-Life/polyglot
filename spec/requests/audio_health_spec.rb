require "rails_helper"

# Contract for the transcription health endpoint (issue 3). CI has no ffmpeg/whisper,
# so this asserts the JSON shape + that it's reachable without auth — not that the stack
# is healthy (that's what hitting it on prod proves). Doesn't pass ?deep (would run whisper).
RSpec.describe "Audio health", type: :request do
  it "reports the transcription stack as JSON, no auth required" do
    get "/up/audio"

    expect(response.media_type).to eq("application/json")
    expect(response.status).to be_in([ 200, 503 ])
    body = JSON.parse(response.body)
    expect(body).to include("ok", "ffmpeg", "whisper_cli", "model")
    expect(body["model"]).to include("present")
  end
end
