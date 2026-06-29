# A short audio clip captured on the Translate tab (#16) — uploaded or recorded live
# in the browser, transcribed (self-hosted whisper.cpp), then fed to the normal
# Translate pipeline. Unlike the /audio_decks voicemail flow (which deletes audio
# immediately, docs/PRD-audio-to-vocab.md D2), this clip is KEPT for 2 days so the
# user can replay what a colleague actually said — then RecordingSweepJob purges it.
class Recording < ApplicationRecord
  RETENTION = 48.hours

  belongs_to :user
  has_one_attached :audio

  # Clips past the retention window — what the daily sweep deletes.
  scope :expired, -> { where(created_at: ..RETENTION.ago) }
end
