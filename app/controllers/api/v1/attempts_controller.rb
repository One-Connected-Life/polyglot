module Api
  module V1
    # POST /api/v1/attempts { term_id, correct, from, to, given }
    #
    # Records one graded answer and returns the EXACT same JSON as the web
    # AttemptsController#create — FSRS path: { newly_owned, newly_retired, reps,
    # stability, due }; legacy path: { correct_count, newly_owned }. Grading logic
    # is copied verbatim so the contract can't drift.
    class AttemptsController < BaseController
      def create
        term    = current_user.terms.find(params[:term_id])
        correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
        attempt = current_user.attempts.create!(
          term:          term,
          from_language: params[:from],
          to_language:   params[:to],
          correct:       correct,
          given:         params[:given].to_s.first(255)
        )

        if fsrs_enabled?
          render json: grade_fsrs(term, attempt, correct)
        else
          render json: grade_legacy(term, correct, params[:from], params[:to])
        end
      end

      private

      def grade_legacy(term, correct, from, to)
        correct_count = current_user.attempts
                                    .where(term_id: term.id, from_language: from, to_language: to, correct: true)
                                    .count
        { correct_count: correct_count, newly_owned: correct && correct_count == 2 }
      end

      def grade_fsrs(term, attempt, correct)
        from = attempt.from_language
        to   = attempt.to_language

        scheduling = Scheduling.find_or_initialize_by(
          user_id:       current_user.id,
          term_id:       term.id,
          from_language: from,
          to_language:   to
        )

        unless scheduling.backfilled?
          backfill_scheduling!(scheduling, term, from, to, exclude_attempt_id: attempt.id)
        end

        previous_card = scheduling.card_hash
        scheduler     = FsrsScheduler.new
        new_card      = scheduler.apply(
          previous_card,
          correct: correct,
          at:      attempt.created_at,
          ease:    scheduling.ease
        )
        scheduling.update_from_card_hash!(new_card)

        newly_retired = Mastery.new(new_card).newly_retired_from?(previous_card)

        {
          newly_owned:   false,
          newly_retired: newly_retired,
          reps:          new_card[:reps],
          stability:     new_card[:stability].round(1),
          due:           new_card[:due]&.iso8601,
        }
      end

      def backfill_scheduling!(scheduling, term, from, to, exclude_attempt_id: nil)
        history = current_user.attempts
                              .where(term_id: term.id, from_language: from, to_language: to)
                              .where.not(id: exclude_attempt_id)
                              .order(:id)
                              .to_a
        scheduler = FsrsScheduler.new
        card = scheduler.replay(history, ease: scheduling.ease)
        scheduling.assign_attributes(card.slice(*FsrsScheduler::CARD_KEYS))
        scheduling.backfilled = true
        scheduling.save!
      end
    end
  end
end
