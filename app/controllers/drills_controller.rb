class DrillsController < ApplicationController
  def home
    @decks = Deck.includes(:terms).order(:position)
    @miss_counts = Attempt.miss_counts
  end

  def play
    @from = surfaced_lang(params[:from], "nl")
    @to   = surfaced_lang(params[:to], "en")

    # Skip-easy is a sticky preference; flip it when the toggle passes a value.
    session[:skip_easy] = params[:skip_easy] == "1" if params.key?(:skip_easy)
    @skip_easy = session[:skip_easy] || false

    terms = select_terms(params[:deck]).includes(:translations).to_a
    terms.select! { |t| t.difficulty != :easy } if @skip_easy

    @cards = terms.filter_map do |term|
      prompt = term.translation(@from)
      answer = term.translation(@to)
      next unless prompt && answer

      {
        id: term.id,
        prompt: prompt.with_article,
        answer: answer.text,
        answer_article: answer.article,
        accept: answer.accepted_answers,
        difficulty: term.difficulty.to_s,
      }
    end
  end

  private

  def select_terms(deck_param)
    case deck_param
    when "misses"
      ids = Attempt.missed_term_ids(from: @from, to: @to)
      @title = "Your misses"
      @deck_slug = "misses"
      Term.where(id: ids)
    when "all", nil, ""
      @title = "All words"
      @deck_slug = "all"
      Term.order(:deck_id, :position)
    else
      @deck = Deck.find_by!(slug: deck_param)
      @title = @deck.name
      @deck_slug = @deck.slug
      @deck.terms
    end
  end

  # Only let the surfaced (verified) languages drive the drill; fall back otherwise.
  def surfaced_lang(value, fallback)
    Translation::SURFACED.include?(value) ? value : fallback
  end
end
