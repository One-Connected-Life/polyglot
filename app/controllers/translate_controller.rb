# Translate tab (nav rework). The GET renders a standalone Translate page with a
# Type/Photo segmented toggle. The POST takes target-language text (typed or read from a
# photo), translates it to the user's source language (+ IPA/mnemonic/etymology), and —
# when "Save" is chosen — appends every word to the per-user "Translated" deck.
#
# Save behavior (nav-rework spec): every saved translation is appended to a single
# per-user default deck named "Translated" (auto-created on first save). That's the only
# Translate destination for now. Large batches (10+) route through the existing review
# screen so the user can prune before they land drillable.
class TranslateController < ApplicationController
  # 1–9 items: no batch, straight in. 10+: send to the review screen.
  BATCH_THRESHOLD = 9
  # Audio clips are short (a colleague speaks a sentence). Cap matches /audio_decks.
  MAX_AUDIO_BYTES = 25.megabytes

  MODES = %w[type photo upload record].freeze

  # Standalone Translate page (the tab landing). Mode = type | photo | upload | record.
  def new
    @mode = MODES.include?(params[:mode]) ? params[:mode] : "type"
    @input_language = input_language
  end

  def create
    text = params[:text].to_s.strip
    capture = params[:capture] == "1"

    # An uploaded photo (sign/menu/letter) → read its target-language text first, then
    # translate that. Image bytes stay in memory only — never persisted (#10 privacy).
    if params[:image].present?
      text = ImageReader.new(current_user, params[:image]).call
      if text.blank?
        return redirect_to new_translate_path, alert: "Couldn't read any #{current_user.target_language_name} text in that image."
      end
    elsif params[:audio].present?
      # A spoken clip (uploaded or recorded live) → transcribe it (#16), then translate
      # the transcript through the SAME pipeline as typed text. Unlike the voicemail
      # flow, the clip is kept 2 days for replay (Recording + RecordingSweepJob).
      return if (text = transcribe_audio(params[:audio])).nil?  # already redirected
    end

    if text.blank?
      return redirect_to new_translate_path, alert: "Type a word or phrase to translate."
    end

    @words = Translator.new(current_user, text, input_language: input_language).call
    if @words.blank?
      return redirect_to new_translate_path, alert: "Couldn't find anything to translate there — try different text."
    end

    @captured = false
    @deck = nil
    if capture
      @deck = current_user.translated_deck

      if @words.size > BATCH_THRESHOLD
        # Big batch → land unreviewed and let the user prune on the review screen.
        @deck.absorb(@words, reviewed: false)
        return redirect_to review_deck_path(@deck) if @deck.needs_review?
      end

      created = @deck.absorb(@words, reviewed: true)
      @captured = created.any?
      EnrichTranslationsJob.perform_later(created.map(&:id)) if created.any?
    end

    render :show
  rescue Translator::Error, ImageReader::Error => e
    Rails.logger.error("[Translate] #{e.class}: #{e.message}")
    redirect_to new_translate_path, alert: "That didn't work — give it another try."
  end

  private

  # Transcribe a spoken clip and persist it for 2-day replay. Returns the transcript
  # String, or nil after redirecting (too large / no speech) so #create can bail.
  def transcribe_audio(file)
    if file.size > MAX_AUDIO_BYTES
      redirect_to new_translate_path, alert: "That recording is too large (max #{MAX_AUDIO_BYTES / 1.megabyte} MB)."
      return nil
    end

    language = input_language
    transcript = Transcriber.new(language: language).call(file.tempfile.path)
    current_user.recordings.create!(language: language, transcript: transcript, audio: file)
    transcript
  rescue Transcriber::Error => e
    Rails.logger.error("[Translate audio] #{e.class}: #{e.message}")
    redirect_to new_translate_path, alert: "Couldn't make out any speech in that recording — try again."
    nil
  end

  # The language the input is in. Defaults to the language the user is learning (#16);
  # the input-language toggle (#17) lets them pick another (e.g. English).
  def input_language
    code = params[:input_language].to_s
    Translation::LANGUAGES.key?(code) ? code : current_user.target_language
  end
end
