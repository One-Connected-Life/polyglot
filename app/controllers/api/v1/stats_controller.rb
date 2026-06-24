module Api
  module V1
    # GET /api/v1/stats — mirrors StatsController#index: active words (with status
    # + tallies), the retired shelf, approaching-retirement words, and totals.
    # Direction is target→source (the /stats convention).
    class StatsController < BaseController
      def index
        @target = current_user.target_language
        @source = current_user.source_language
        @words  = current_user.terms.drillable.where(kind: "word").includes(:translations).to_a

        @summary = Hash.new { |h, k| h[k] = { correct: 0, wrong: 0, latest_correct: nil } }
        current_user.attempts.order(:id).find_each do |a|
          s = @summary[[a.term_id, a.from_language, a.to_language]]
          a.correct ? s[:correct] += 1 : s[:wrong] += 1
          s[:latest_correct] = a.correct
        end

        @resting = current_user.attempts.resting_term_ids(from: @target, to: @source).to_set

        if fsrs_enabled?
          retired_ids = current_user.schedulings.retired
                                    .where(from_language: @target, to_language: @source)
                                    .pluck(:term_id).to_set
          approaching_ids = current_user.schedulings.approaching_retirement
                                        .where(from_language: @target, to_language: @source)
                                        .pluck(:term_id).to_set
          @retired_schedulings = current_user.schedulings.retired
                                             .where(from_language: @target, to_language: @source)
                                             .index_by(&:term_id)
          @approaching_schedulings = current_user.schedulings.approaching_retirement
                                                 .where(from_language: @target, to_language: @source)
                                                 .index_by(&:term_id)
          @retired_words     = @words.select { |t| retired_ids.include?(t.id) }
          @approaching_words = @words.select { |t| approaching_ids.include?(t.id) }
          @fsrs_enabled      = true
        else
          @retired_words           = []
          @approaching_words       = []
          @retired_schedulings     = {}
          @approaching_schedulings = {}
          @fsrs_enabled            = false
        end

        retired_id_set = @retired_words.map(&:id).to_set
        @active_words  = @words.reject { |t| retired_id_set.include?(t.id) }
        @active_words.sort_by! do |t|
          s = @summary[[t.id, @target, @source]]
          [-(s[:correct] + s[:wrong]), t.translation(@source)&.text.to_s]
        end

        totals = {
          attempts: current_user.attempts.count,
          correct:  current_user.attempts.where(correct: true).count,
          owned:    @active_words.count { |t| @summary[[t.id, @target, @source]][:correct] >= 2 },
          retired:  @retired_words.size,
        }

        render json: {
          target:           @target,
          source:           @source,
          fsrs_enabled:     @fsrs_enabled,
          totals:           totals,
          active_words:     @active_words.map { |t| active_word_json(t) },
          retired_words:    @retired_words.map { |t| retired_word_json(t) },
          approaching_words: @approaching_words.map { |t| approaching_word_json(t) },
        }
      end

      private

      def active_word_json(term)
        s = @summary[[term.id, @target, @source]]
        {
          id:      term.id,
          target:  term.translation(@target)&.with_article,
          source:  term.translation(@source)&.with_article,
          status:  word_status(term),
          correct: s[:correct],
          wrong:   s[:wrong],
        }
      end

      def retired_word_json(term)
        sched = @retired_schedulings[term.id]
        {
          id:            term.id,
          target:        term.translation(@target)&.with_article,
          source:        term.translation(@source)&.with_article,
          stability:     sched&.stability&.round(1),
          recall_months: sched&.recall_months,
        }
      end

      def approaching_word_json(term)
        sched = @approaching_schedulings[term.id]
        {
          id:       term.id,
          target:   term.translation(@target)&.with_article,
          source:   term.translation(@source)&.with_article,
          progress: sched&.retirement_progress&.round(2),
        }
      end

      # Verbatim from StatsController#word_status.
      def word_status(term)
        s = @summary[[term.id, @target, @source]]
        return "new"             if s[:correct] + s[:wrong] == 0
        return "owned · resting" if @resting.include?(term.id)
        return "owned · due"     if s[:correct] >= 2
        return "missed"          if s[:latest_correct] == false
        "learning #{s[:correct]}/2"
      end
    end
  end
end
