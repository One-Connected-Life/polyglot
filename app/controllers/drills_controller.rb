class DrillsController < ApplicationController
  def home
    @decks       = current_user.decks.includes(:terms).order(:position)
    @miss_counts = current_user.attempts.miss_counts(langs: current_user.drillable_languages)
    @word_count  = current_user.terms.where(kind: "word").count
  end

  def play
    @from = surfaced_lang(params[:from], current_user.source_language)
    @to   = surfaced_lang(params[:to], current_user.target_language)

    session[:skip_easy] = params[:skip_easy] == "1" if params.key?(:skip_easy)
    @skip_easy = session[:skip_easy] || false

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
          pool = current_user.terms.where(kind: "sentence").includes(:translations).to_a
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
  def play_fsrs
    base_terms = select_terms(params[:deck]).includes(:translations, :schedulings)

    # Pre-fill ease for any terms without a scheduling row yet.
    new_terms = base_terms.select { |t| t.schedulings.none? { |s| s.user_id == current_user.id } }
    EasePrefillService.new(current_user).upsert_ease!(new_terms) if new_terms.any?

    due_term_ids = current_user.schedulings
                               .due_now(from: @from, to: @to)
                               .pluck(:term_id)
                               .to_set

    # ease=1 cognates are auto-excluded (English cognate skip — #axis-4).
    cognate_ids = current_user.schedulings
                              .where(from_language: @from, to_language: @to, ease: 1)
                              .pluck(:term_id)
                              .to_set

    # Archived words are permanently out (user said "done forever").
    archived_ids = current_user.schedulings
                               .where(from_language: @from, to_language: @to, archived: true)
                               .pluck(:term_id)
                               .to_set

    @excluded_ids = cognate_ids | archived_ids
    @terms = base_terms.select { |t| due_term_ids.include?(t.id) && !@excluded_ids.include?(t.id) }
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
      current_user.terms.where(kind: "word").order(:deck_id, :position)
    else
      @deck            = current_user.decks.find_by!(slug: deck_param)
      @title           = @deck.name
      @deck_slug       = @deck.slug
      @is_sentence_deck = @deck.terms.exists?(kind: "sentence")
      @deck.terms
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
