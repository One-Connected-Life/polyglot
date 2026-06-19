class DrillsController < ApplicationController
  def home
    @decks = current_user.decks.includes(:terms).order(:position)
    @miss_counts = current_user.attempts.miss_counts(langs: current_user.drillable_languages)
    @word_count = current_user.terms.where(kind: "word").count
  end

  def play
    @from = surfaced_lang(params[:from], current_user.target_language)
    @to   = surfaced_lang(params[:to], current_user.source_language)

    session[:skip_easy] = params[:skip_easy] == "1" if params.key?(:skip_easy)
    @skip_easy = session[:skip_easy] || false

    # Rest mastered words (2x correct -> 7 days, 3x+ -> 14 days). Sticky, on by default.
    session[:hide_mastered] = params[:hide_mastered] == "1" if params.key?(:hide_mastered)
    @hide_mastered = session.key?(:hide_mastered) ? session[:hide_mastered] : true
    resting = @hide_mastered ? current_user.attempts.resting_term_ids(from: @from, to: @to) : []

    terms = select_terms(params[:deck]).includes(:translations).to_a
    terms.select! { |t| t.difficulty(@from, @to) != :easy } if @skip_easy
    terms.reject! { |t| resting.include?(t.id) } unless @deck_slug == "misses"

    @cards = terms.filter_map { |term| build_card(term) }

    # Sentences sprinkle into word drills — but not when the deck IS sentences.
    @sentences =
      if @is_sentence_deck
        []
      else
        pool = current_user.terms.where(kind: "sentence").includes(:translations).to_a
        pool.reject! { |t| resting.include?(t.id) }
        pool.filter_map { |t| build_card(t) }
      end
  end

  private

  # Target/source first, then any other languages present (for the reveal panel).
  def lang_order
    current_user.drillable_languages + (Translation::LANGUAGES.keys - current_user.drillable_languages)
  end

  def build_card(term)
    prompt = term.translation(@from)
    answer = term.translation(@to)
    return nil unless prompt && answer

    {
      id: term.id,
      kind: term.kind,
      prompt: prompt.with_article,
      answer: answer.text,
      answer_article: answer.article,
      accept: answer.accepted_answers,
      difficulty: (term.kind == "word" ? term.difficulty(@from, @to).to_s : ""),
      translations: lang_order.filter_map { |code|
        t = term.translation(code)
        { lang: code, text: t.with_article } if t
      },
    }
  end

  def select_terms(deck_param)
    case deck_param
    when "misses"
      @title = "Your misses"
      @deck_slug = "misses"
      current_user.terms.where(id: current_user.attempts.missed_term_ids(from: @from, to: @to))
    when "all", nil, ""
      @title = "All words"
      @deck_slug = "all"
      current_user.terms.where(kind: "word").order(:deck_id, :position)
    else
      @deck = current_user.decks.find_by!(slug: deck_param)
      @title = @deck.name
      @deck_slug = @deck.slug
      @is_sentence_deck = @deck.terms.exists?(kind: "sentence")
      @deck.terms
    end
  end

  # Only let the user's two languages drive the drill; fall back otherwise.
  def surfaced_lang(value, fallback)
    current_user.drillable_languages.include?(value) ? value : fallback
  end
end
