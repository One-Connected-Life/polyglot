class DrillsController < ApplicationController
  def home
    @decks = Deck.includes(:terms).order(:position)
    @miss_counts = Attempt.miss_counts
  end

  def play
    @from = surfaced_lang(params[:from], "nl")
    @to   = surfaced_lang(params[:to], "en")

    case params[:deck]
    when "misses"
      ids = Attempt.missed_term_ids(from: @from, to: @to)
      terms = Term.where(id: ids)
      @title = "Your misses"
      @deck_slug = "misses"
    when "all", nil, ""
      terms = Term.order(:deck_id, :position)
      @title = "All words"
      @deck_slug = "all"
    else
      @deck = Deck.find_by!(slug: params[:deck])
      terms = @deck.terms
      @title = @deck.name
      @deck_slug = @deck.slug
    end

    @cards = terms.includes(:translations).filter_map do |term|
      prompt = term.translation(@from)
      answer = term.translation(@to)
      next unless prompt && answer

      {
        id: term.id,
        prompt: prompt.with_article,
        answer: answer.text,
        answer_article: answer.article,
      }
    end
  end

  private

  # Only let the surfaced (verified) languages drive the drill; fall back otherwise.
  def surfaced_lang(value, fallback)
    Translation::SURFACED.include?(value) ? value : fallback
  end
end
