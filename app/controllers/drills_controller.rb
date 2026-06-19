class DrillsController < ApplicationController
  LANG_ORDER = Translation::SURFACED + (Translation::LANGUAGES.keys - Translation::SURFACED)

  def home
    @decks = Deck.includes(:terms).order(:position)
    @miss_counts = Attempt.miss_counts
    @word_count = Term.where(kind: "word").count
  end

  def play
    @from = surfaced_lang(params[:from], "nl")
    @to   = surfaced_lang(params[:to], "en")

    # Skip-easy is a sticky preference; flip it when the toggle passes a value.
    session[:skip_easy] = params[:skip_easy] == "1" if params.key?(:skip_easy)
    @skip_easy = session[:skip_easy] || false

    # Rest mastered words (2x correct -> 7 days, 3x+ -> 14 days). Sticky, on by default.
    session[:hide_mastered] = params[:hide_mastered] == "1" if params.key?(:hide_mastered)
    @hide_mastered = session.key?(:hide_mastered) ? session[:hide_mastered] : true
    resting = @hide_mastered ? Attempt.resting_term_ids(from: @from, to: @to) : []
    @correct_counts = Attempt.where(from_language: @from, to_language: @to, correct: true).group(:term_id).count

    terms = select_terms(params[:deck]).includes(:translations).to_a
    terms.select! { |t| t.difficulty != :easy } if @skip_easy
    terms.reject! { |t| resting.include?(t.id) } unless @deck_slug == "misses"

    @cards = terms.filter_map { |term| build_card(term) }

    # Sentences sprinkle into word drills — but not when the deck IS sentences.
    @sentences =
      if @is_sentence_deck
        []
      else
        pool = Term.where(kind: "sentence").includes(:translations).to_a
        pool.reject! { |t| resting.include?(t.id) }
        pool.filter_map { |t| build_card(t) }
      end
  end

  private

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
      difficulty: (term.kind == "word" ? term.difficulty.to_s : ""),
      correct_so_far: (@correct_counts[term.id] || 0),
      translations: LANG_ORDER.filter_map { |code|
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
      Term.where(id: Attempt.missed_term_ids(from: @from, to: @to))
    when "all", nil, ""
      @title = "All words"
      @deck_slug = "all"
      Term.where(kind: "word").order(:deck_id, :position)
    else
      @deck = Deck.find_by!(slug: deck_param)
      @title = @deck.name
      @deck_slug = @deck.slug
      @is_sentence_deck = @deck.terms.exists?(kind: "sentence")
      @deck.terms
    end
  end

  # Only let the surfaced (verified) languages drive the drill; fall back otherwise.
  def surfaced_lang(value, fallback)
    Translation::SURFACED.include?(value) ? value : fallback
  end
end
