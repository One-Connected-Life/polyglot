# Translate-first home (issue #10). Takes target-language text, translates it to the
# user's source language, and — when "capture to my words" is checked — melts the words
# into the rolling "My Words" deck. Small captures (≤ BATCH_THRESHOLD) drill immediately;
# larger ones route through the existing review screen so the user can prune first.
class TranslateController < ApplicationController
  # 1–9 items: no batch, straight in. 10+: send to the review screen.
  BATCH_THRESHOLD = 9

  def create
    text = params[:text].to_s.strip
    capture = params[:capture] == "1"

    if text.blank?
      return redirect_to root_path, alert: "Type a word or phrase to translate."
    end

    @words = Translator.new(current_user, text).call
    if @words.blank?
      return redirect_to root_path, alert: "Couldn't find anything to translate there — try different text."
    end

    @captured = false
    @deck = nil
    if capture
      @deck = current_user.my_words_deck

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
  rescue Translator::Error => e
    Rails.logger.error("[Translate] #{e.message}")
    redirect_to root_path, alert: "Translation failed — give it another try."
  end
end
