# Upload your own audio → vocabulary deck (issue #3).
# The file is staged in tmp/audio_uploads/ (gitignored), transcribed + extracted in
# a background job, then DELETED — we never persist the original recording.
class AudioDecksController < ApplicationController
  MAX_BYTES = 25.megabytes
  ALLOWED = %w[.m4a .mp3 .wav .ogg .flac .aac .mp4].freeze

  def new
  end

  def create
    unless current_user.can_generate?
      return redirect_to new_audio_deck_path,
        alert: "You've reached your deck limit (#{User::GENERATION_CAP})."
    end

    file = params[:audio]
    if file.blank?
      return redirect_to new_audio_deck_path, alert: "Choose an audio file to upload."
    end

    ext = File.extname(file.original_filename.to_s).downcase
    if ALLOWED.exclude?(ext)
      return redirect_to new_audio_deck_path,
        alert: "That file type isn't supported — try an audio recording (m4a, mp3, wav…)."
    end
    if file.size > MAX_BYTES
      return redirect_to new_audio_deck_path,
        alert: "That file is too large (max #{MAX_BYTES / 1.megabyte} MB)."
    end

    path = stage(file, ext)
    deck = current_user.decks.create!(
      name: unique_name(File.basename(file.original_filename.to_s, ".*").presence || "Audio deck"),
      status: "transcribing",
      position: (current_user.decks.maximum(:position) || -1) + 1
    )
    current_user.increment!(:generations_count)
    ExtractDeckFromAudioJob.perform_later(deck, path.to_s)

    redirect_to root_path, notice: "Transcribing your audio — your deck will be ready to review shortly."
  end

  private

  # Write the upload to the gitignored staging dir. The job deletes it after use.
  def stage(file, ext)
    dir = Rails.root.join("tmp/audio_uploads")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{SecureRandom.uuid}#{ext}")
    File.binwrite(path, file.read)
    path
  end

  # Deck slug is unique per user; filenames repeat, so suffix on collision.
  def unique_name(base)
    base = base.titleize
    return base unless current_user.decks.exists?(slug: base.parameterize)

    n = 2
    n += 1 while current_user.decks.exists?(slug: "#{base} #{n}".parameterize)
    "#{base} #{n}"
  end
end
