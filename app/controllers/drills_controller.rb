class DrillsController < ApplicationController
  def home
    @decks       = current_user.decks.includes(:terms).order(:position)
    @miss_counts = current_user.attempts.miss_counts(langs: current_user.drillable_languages)
    @word_count  = current_user.terms.drillable.where(kind: "word").count
    basics_ids   = @decks.select { |d| d.name.start_with?("Basics:") }.map(&:id)
    @basics_count = basics_ids.any? ? current_user.terms.drillable.where(deck_id: basics_ids).count : 0
  end

  def play
    @from = surfaced_lang(params[:from], current_user.source_language)
    @to   = surfaced_lang(params[:to], current_user.target_language)

    session[:skip_easy] = params[:skip_easy] == "1" if params.key?(:skip_easy)
    @skip_easy = session[:skip_easy] || false

    # Persistent drill-order setting (smart = FSRS order w/ randomized ties; shuffle = random).
    if %w[smart shuffle].include?(params[:order]) && current_user.drill_order != params[:order]
      current_user.update!(drill_order: params[:order])
    end
    @drill_order = current_user.drill_order

    # Multi-language drill: source → N targets in a sequential-reveal card.
    # Activated when multi=1 is in the params (set from the home deck picker).
    @multi = params[:multi] == "1" && current_user.multi_language_drill?
    if @multi
      session[:drill_targets] = params[:targets]&.split(",") if params.key?(:targets)
      @target_langs = (session[:drill_targets].presence || current_user.active_learning_languages)
                        .select { |l| Translation::LANGUAGES.key?(l) && l != @from }
      @target_langs = @target_langs.shuffle if current_user.drill_direction == "random"
    end

    # Term selection: FSRS scheduling when the flag is on, else the legacy resting
    # logic. Both set @terms + @excluded_ids (see the terms/excluded_ids helpers).
    if fsrs_enabled?
      play_fsrs
    else
      play_legacy
    end

    # Keep the "Recent sentences" pool fresh from recently-practiced words, in the
    # background — never blocks this drill. Fresh sentences flow into the sprinkle pool
    # on the next drill (see SentenceGenerator). Skip when drilling the sentence deck itself.
    if !@is_sentence_deck && SentenceGenerator.stale?(current_user)
      GenerateSentencesJob.perform_later(current_user)
    end

    if @multi
      # One card per concept; targets array inside each card drives the JS loop.
      @cards = terms.filter_map { |term| build_multi_card(term) }
      @sentences = []
    else
      @cards = terms.filter_map { |term| build_card(term) }

      # Sentences sprinkle into word drills — but not when the deck IS sentences.
      @sentences =
        if @is_sentence_deck
          []
        else
          pool = current_user.terms.drillable.where(kind: "sentence").includes(:translations).to_a
          pool.reject! { |t| excluded_ids.include?(t.id) }
          pool.filter_map { |t| build_card(t) }
        end
    end
  end

  private

  # ── FSRS path (feature flag on) ───────────────────────────────────────────
  #
  # Selects terms via scheduling.due_now instead of the bespoke resting logic.
  # Auto-skips ease=1 (English cognates) — supersedes the old skip_easy toggle.
  #
  # DRILL-CORE RECONCILIATION NOTE: sets @terms and @excluded_ids.
  # The legacy path also sets these so the shared build path below works.
  # PRACTICE IS ALWAYS AVAILABLE — there is no such thing as "no words due" when
  # the user wants to drill (product invariant; see memory
  # language_app_practice_always_available). FSRS *coaches order* (most-overdue /
  # new first) and drives retire-and-celebrate + ease, but it NEVER gates whether
  # a word can be practiced. We hold back only intentional removals: retired
  # (mastered, celebrated out), ease-1 cognates (auto-skip), archived (done forever).
  def play_fsrs
    base_terms = select_terms(params[:deck]).includes(:translations, :schedulings).to_a

    # Every term needs a scheduling row for THIS direction (ease pips + retire read
    # it). Idempotent; create blank rows where missing, then reload so the in-memory
    # associations see them. This also fixes a never-drilled direction being empty.
    new_terms = base_terms.reject do |t|
      t.schedulings.any? { |s| s.user_id == current_user.id && s.from_language == @from && s.to_language == @to }
    end
    if new_terms.any?
      EasePrefillService.new(current_user).upsert_ease!(new_terms, from: @from, to: @to)
      ActiveRecord::Associations::Preloader.new(records: base_terms, associations: :schedulings).call
    end

    retired_ids  = current_user.schedulings.retired
                               .where(from_language: @from, to_language: @to).pluck(:term_id).to_set
    cognate_ids  = current_user.schedulings.where(ease: 1).pluck(:term_id).to_set
    archived_ids = current_user.schedulings.where(archived: true).pluck(:term_id).to_set
    @excluded_ids = retired_ids | cognate_ids | archived_ids

    # Order, don't gate: surface the most-overdue (and never-drilled) cards first.
    due_by_term = current_user.schedulings
                              .where(from_language: @from, to_language: @to)
                              .pluck(:term_id, :due).to_h
    pool = base_terms.reject { |t| @excluded_ids.include?(t.id) }
    @terms =
      if current_user.drill_order == "shuffle"
        pool.shuffle # fully random across all cards
      else
        # FSRS due-order, but ties (esp. never-drilled, which all share the epoch
        # fallback) get a random tiebreaker — otherwise verb conjugations come out in
        # insertion order (I/you/he/…). The rand key is computed once per card. (#drill-order)
        pool.sort_by { |t| [(due_by_term[t.id] || Time.at(0)).to_f, rand] }
      end
  end

  # ── legacy path (feature flag off) ────────────────────────────────────────
  def play_legacy
    session[:hide_mastered] = params[:hide_mastered] == "1" if params.key?(:hide_mastered)
    @hide_mastered = session.key?(:hide_mastered) ? session[:hide_mastered] : true
    resting = @hide_mastered ? current_user.attempts.resting_term_ids(from: @from, to: @to) : []

    base_terms = select_terms(params[:deck]).includes(:translations).to_a
    base_terms.select! { |t| t.difficulty(@from, @to) != :easy } if @skip_easy

    @excluded_ids = resting.to_set
    @terms = base_terms.reject { |t| @excluded_ids.include?(t.id) && @deck_slug != "misses" }
  end

  def terms
    @terms || []
  end

  def excluded_ids
    @excluded_ids || Set.new
  end

  # ── shared helpers ─────────────────────────────────────────────────────────

  # Target/source first, then any other languages present (for the reveal panel).
  def lang_order
    current_user.drillable_languages + (Translation::LANGUAGES.keys - current_user.drillable_languages)
  end

  # Single-target card (existing format — unchanged for integrator compatibility).
  def build_card(term)
    prompt = term.translation(@from)
    answer = term.translation(@to)
    return nil unless prompt && answer

    # [ETYMOLOGY] The target-language row carries etymology + mnemonic.
    # We pass @from here because drills typically run target→source (nl→en),
    # so @from is the language the learner is studying.
    target_translation = term.translation(@from)

    {
      id: term.id,
      kind: term.kind,
      # [EASE] current AI-prefilled ease (1–5) for this direction; drives the
      # mid-drill nudge pips. nil in legacy mode (no scheduling rows exist).
      ease: (ease_for(term) if fsrs_enabled?),
      prompt: prompt.with_article,
      # PHONETICS: IPA + translit for the prompt (FROM) word
      prompt_ipa: prompt.ipa,
      prompt_translit: prompt.translit,
      prompt_non_latin: prompt.non_latin?,
      answer: answer.text,
      answer_article: answer.article,
      accept: answer.accepted_answers,
      difficulty: (term.kind == "word" ? term.difficulty(@from, @to).to_s : ""),
      # [ETYMOLOGY] etymology + mnemonic shown on reveal (nil when absent → omit block)
      etymology: target_translation&.etymology.presence,
      mnemonic: target_translation&.mnemonic.presence,
      # PHONETICS: IPA + translit for the answer (TO) word
      answer_ipa: answer.ipa,
      answer_translit: answer.translit,
      answer_non_latin: answer.non_latin?,
      translations: lang_order.filter_map { |code|
        t = term.translation(code)
        { lang: code, text: t.with_article } if t
      },
    }
  end

  # Current ease (1–5) for this term in the @from→@to direction. Reads the
  # preloaded schedulings (FSRS path includes them); defaults to 3 if no row yet.
  def ease_for(term)
    s = term.schedulings.detect do |x|
      x.user_id == current_user.id && x.from_language == @from && x.to_language == @to
    end
    s&.ease || 3
  end

  # Multi-language card: source prompt + N ordered targets.
  # A target language is SKIPPED (omitted from targets) when the concept lacks
  # a translation for it — the drill gracefully moves on.
  # The JS drill loop iterates over `targets`, grading one at a time, recording
  # one Attempt per target (from_language/@from → to_language/target_lang).
  def build_multi_card(term)
    prompt = term.translation(@from)
    return nil unless prompt

    targets = @target_langs.filter_map do |lang|
      t = term.translation(lang)
      next unless t  # gracefully skip missing translations

      {
        lang: lang,
        lang_name: Translation::LANGUAGES[lang],
        answer: t.text,
        answer_article: t.article,
        accept: t.accepted_answers,
      }
    end

    return nil if targets.empty?  # no usable target for any chosen language → skip

    {
      id: term.id,
      kind: "multi",
      prompt: prompt.with_article,
      from_lang_name: Translation::LANGUAGES[@from],
      targets: targets,
      # All translations for the detail panel shown after completing all targets.
      translations: lang_order.filter_map { |code|
        t = term.translation(code)
        { lang: code, text: t.with_article } if t
      },
    }
  end

  def select_terms(deck_param)
    case deck_param
    when "misses"
      @title     = "Your misses"
      @deck_slug = "misses"
      current_user.terms.where(id: current_user.attempts.missed_term_ids(from: @from, to: @to))
    when "all", nil, ""
      @title     = "All words"
      @deck_slug = "all"
      current_user.terms.drillable.where(kind: "word").order(:deck_id, :position)
    when "basics"
      # Virtual aggregate over every "Basics: *" deck — one drill across the whole
      # foundation (pronouns, verbs, numbers, …) without duplicating terms, so FSRS
      # progress is shared with the individual themed decks. Verbs are kind "phrase",
      # so include phrases here (unlike "all", which is words-only).
      @title     = "Basics: All"
      @deck_slug = "basics"
      basics_ids = current_user.decks.where("name LIKE 'Basics:%'").pluck(:id)
      current_user.terms.drillable.where(deck_id: basics_ids)
                  .where.not(kind: "sentence").order(:deck_id, :position)
    else
      @deck            = current_user.decks.find_by!(slug: deck_param)
      @title           = @deck.name
      @deck_slug       = @deck.slug
      @is_sentence_deck = @deck.terms.exists?(kind: "sentence")
      # Exclude a not-yet-accepted appended cohort (reviewed: false) from the deck drill.
      @deck.terms.where(reviewed: true)
    end
  end

  # Only let valid app languages drive the drill; fall back otherwise.
  def surfaced_lang(value, fallback)
    Translation::LANGUAGES.key?(value) ? value : (fallback || "en")
  end

  # FSRS_ENABLED env var gates the new scheduling path, drill-by-drill.
  # Set FSRS_ENABLED=1 in .env (development) or as a server env var (production).
  def fsrs_enabled?
    ENV["FSRS_ENABLED"].to_s == "1"
  end
end
