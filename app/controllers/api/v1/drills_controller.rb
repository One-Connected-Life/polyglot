module Api
  module V1
    # GET /api/v1/drills/play — the drill runner for native clients.
    #
    # Returns { cards: [...], sentences: [...] } where each card is BYTE-FOR-BYTE
    # the same shape build_card / build_multi_card emit on the web side. Term
    # selection + ordering reuses the identical FSRS / legacy logic from
    # DrillsController (copied verbatim so the contract can't drift) — practice is
    # always available; FSRS orders, never gates.
    #
    # Query params: deck, from, to, order, skip_easy, multi, targets.
    # Unlike the web (which persists order/skip_easy/targets in the session), the
    # API is stateless — these come purely from query params each call.
    class DrillsController < BaseController
      def play
        # Explicit from/to wins; else the user's saved default direction. (coordinator add)
        default_from, default_to = current_user.default_drill_direction
        @from = surfaced_lang(params[:from], default_from)
        @to   = surfaced_lang(params[:to], default_to)

        # Default to the user's saved pref (Finding A); explicit param still overrides.
        @skip_easy = params.key?(:skip_easy) ? params[:skip_easy] == "1" : current_user.skip_easy?

        if %w[smart shuffle].include?(params[:order]) && current_user.drill_order != params[:order]
          current_user.update!(drill_order: params[:order])
        end

        # Default to the user's saved weave pref (show_other_languages, default OFF);
        # an explicit multi param still overrides for this request. (#fix-1)
        weave = params.key?(:multi) ? params[:multi] == "1" : current_user.show_other_languages?
        @multi = weave && current_user.multi_language_drill?
        if @multi
          chosen = params[:targets].present? ? params[:targets].split(",") : nil
          @target_langs = (chosen.presence || current_user.active_learning_languages)
                            .select { |l| Translation::LANGUAGES.key?(l) && l != @from }
          @target_langs = @target_langs.shuffle if current_user.drill_direction == "random"
        end

        if fsrs_enabled?
          play_fsrs
        else
          play_legacy
        end

        if !@is_sentence_deck && SentenceGenerator.stale?(current_user)
          GenerateSentencesJob.perform_later(current_user)
        end

        if @multi
          cards     = terms.filter_map { |term| build_multi_card(term) }
          sentences = []
        else
          cards = terms.filter_map { |term| build_card(term) }
          sentences =
            if @is_sentence_deck
              []
            else
              pool = current_user.terms.drillable.where(kind: "sentence").includes(:translations).to_a
              pool.reject! { |t| excluded_ids.include?(t.id) }
              pool.filter_map { |t| build_card(t) }
            end
        end

        render json: { cards: cards, sentences: sentences }
      end

      private

      # ── FSRS path (mirrors DrillsController#play_fsrs verbatim) ───────────────
      def play_fsrs
        base_terms = select_terms(params[:deck]).includes(:translations, :schedulings).to_a

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

        due_by_term = current_user.schedulings
                                  .where(from_language: @from, to_language: @to)
                                  .pluck(:term_id, :due).to_h
        pool = base_terms.reject { |t| @excluded_ids.include?(t.id) }
        @terms =
          if current_user.drill_order == "shuffle"
            pool.shuffle
          else
            pool.sort_by { |t| [(due_by_term[t.id] || Time.at(0)).to_f, rand] }
          end
      end

      # ── legacy path (mirrors DrillsController#play_legacy) ────────────────────
      # Defaults to the user's saved pref (Finding A); explicit param overrides.
      def play_legacy
        @hide_mastered = params.key?(:hide_mastered) ? params[:hide_mastered] == "1" : current_user.hide_mastered?
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

      # ── shared helpers (verbatim from DrillsController) ───────────────────────
      def lang_order
        current_user.drillable_languages + (Translation::LANGUAGES.keys - current_user.drillable_languages)
      end

      def build_card(term)
        prompt = term.translation(@from)
        answer = term.translation(@to)
        return nil unless prompt && answer

        target_translation = term.translation(@from)

        {
          id: term.id,
          kind: term.kind,
          ease: (ease_for(term) if fsrs_enabled?),
          prompt: prompt.with_article,
          prompt_ipa: prompt.ipa,
          prompt_translit: prompt.translit,
          prompt_non_latin: prompt.non_latin?,
          answer: answer.text,
          answer_article: answer.article,
          accept: answer.accepted_answers,
          difficulty: (term.kind == "word" ? term.difficulty(@from, @to).to_s : ""),
          etymology: target_translation&.etymology.presence,
          mnemonic: target_translation&.mnemonic.presence,
          answer_ipa: answer.ipa,
          answer_translit: answer.translit,
          answer_non_latin: answer.non_latin?,
          translations: lang_order.filter_map { |code|
            t = term.translation(code)
            { lang: code, text: t.with_article } if t
          },
        }
      end

      def ease_for(term)
        s = term.schedulings.detect do |x|
          x.user_id == current_user.id && x.from_language == @from && x.to_language == @to
        end
        s&.ease || 3
      end

      def build_multi_card(term)
        prompt = term.translation(@from)
        return nil unless prompt

        targets = @target_langs.filter_map do |lang|
          t = term.translation(lang)
          next unless t

          {
            lang: lang,
            lang_name: Translation::LANGUAGES[lang],
            answer: t.text,
            answer_article: t.article,
            accept: t.accepted_answers,
          }
        end

        return nil if targets.empty?

        {
          id: term.id,
          kind: "multi",
          prompt: prompt.with_article,
          from_lang_name: Translation::LANGUAGES[@from],
          targets: targets,
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
          @deck.terms.where(reviewed: true)
        end
      end

      def surfaced_lang(value, fallback)
        Translation::LANGUAGES.key?(value) ? value : (fallback || "en")
      end
    end
  end
end
