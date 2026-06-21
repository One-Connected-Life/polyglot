# Audio→vocab background pipeline (issue #3): transcribe an uploaded file with
# self-hosted Whisper, extract a candidate deck, and land it in "review" so the
# user can prune before drilling.
#
# The audio is ALWAYS deleted afterward (success or failure) — we keep no original
# recording (privacy decision D2, docs/PRD-audio-to-vocab.md). audio_path points at
# a file in the gitignored tmp/audio_uploads/ staging dir.
class ExtractDeckFromAudioJob < ApplicationJob
  queue_as :default

  def perform(deck, audio_path)
    transcript = Transcriber.new(language: deck.user.target_language).call(audio_path)
    DeckGenerator.new(deck, transcript: transcript, final_status: "review").call
  rescue Transcriber::Error => e
    deck.update(status: "failed", status_detail: e.message)
  rescue DeckGenerator::Error => e
    deck.update(status: "failed", status_detail: "Couldn't extract words from the audio.")
    Rails.logger.error("[ExtractDeckFromAudioJob] deck=#{deck.id} #{e.class}: #{e.message}")
  ensure
    File.delete(audio_path) if audio_path.present? && File.exist?(audio_path)
  end
end
