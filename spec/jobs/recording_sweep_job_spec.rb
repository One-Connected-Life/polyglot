require "rails_helper"

# Daily sweep that auto-deletes Translate-audio clips past the 2-day retention (#16).
RSpec.describe RecordingSweepJob, type: :job do
  let(:user) { create(:user) }

  it "destroys clips older than the retention window and keeps fresh ones" do
    fresh = user.recordings.create!(language: "nl", transcript: "vers")
    old   = user.recordings.create!(language: "nl", transcript: "oud")
    old.update_column(:created_at, (Recording::RETENTION + 1.hour).ago)

    expect { RecordingSweepJob.perform_now }.to change(Recording, :count).by(-1)
    expect(Recording.exists?(fresh.id)).to be(true)
    expect(Recording.exists?(old.id)).to be(false)
  end
end
