require "rails_helper"

# A short audio clip kept for 2-day replay after a Translate-audio capture (#16).
# Separate from the /audio_decks voicemail flow, which never persists audio.
RSpec.describe Recording, type: :model do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  it "belongs to a user and stores a transcript + language" do
    rec = user.recordings.create!(language: "nl", transcript: "goedemorgen")
    expect(rec.user).to eq(user)
    expect(rec.transcript).to eq("goedemorgen")
    expect(rec.language).to eq("nl")
  end

  it "retains clips for 48 hours" do
    expect(Recording::RETENTION).to eq(48.hours)
  end

  describe ".expired" do
    it "selects only clips older than the retention window" do
      fresh = user.recordings.create!(language: "nl", transcript: "vers")
      old   = user.recordings.create!(language: "nl", transcript: "oud")
      old.update_column(:created_at, (Recording::RETENTION + 1.hour).ago)

      expect(Recording.expired).to include(old)
      expect(Recording.expired).not_to include(fresh)
    end
  end

  it "purges its attached audio when destroyed" do
    rec = user.recordings.create!(language: "nl", transcript: "hoi")
    rec.audio.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/sample.m4a")),
      filename: "sample.m4a", content_type: "audio/mp4"
    )
    expect(rec.audio).to be_attached
    blob_id = rec.audio.blob.id

    perform_enqueued_jobs { rec.destroy }
    expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
  end
end
