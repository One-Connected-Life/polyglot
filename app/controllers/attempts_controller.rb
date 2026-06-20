class AttemptsController < ApplicationController
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

  # ── legacy path (feature flag off) ────────────────────────────────────────

  def grade_legacy(term, correct, from, to)
    correct_count = current_user.attempts
                                .where(term_id: term.id, from_language: from, to_language: to, correct: true)
                                .count
    { correct_count: correct_count, newly_owned: correct && correct_count == 2 }
  end

  # ── FSRS path (feature flag on) ───────────────────────────────────────────
  #
  # Updates (or creates) the scheduling row and returns JSON that the drill
  # controller uses to fire the retire celebration at exactly the right moment.
  #
  # DRILL-CORE RECONCILIATION NOTE: the only field the JS drill currently reads
  # from this endpoint is `newly_owned`. Under FSRS we return `newly_retired`
  # instead (the orchestrator will reconcile the JS when all four features merge).
  # Both are booleans — the JS `saved.then` path already ignores unknown keys.

  def grade_fsrs(term, attempt, correct)
    from = attempt.from_language
    to   = attempt.to_language

    scheduling = Scheduling.find_or_initialize_by(
      user_id:       current_user.id,
      term_id:       term.id,
      from_language: from,
      to_language:   to
    )

    # Backfill on first FSRS grade if this row was created pre-flag-on.
    # Exclude the current attempt so it isn't replayed AND applied (double-count).
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
      # Legacy field — kept so existing drill JS doesn't break.
      newly_owned:   false,
      # FSRS fields — the drill JS reads these when FSRS is on.
      newly_retired: newly_retired,
      reps:          new_card[:reps],
      stability:     new_card[:stability].round(1),
      due:           new_card[:due]&.iso8601,
    }
  end

  def backfill_scheduling!(scheduling, term, from, to, exclude_attempt_id: nil)
    # Exclude the current attempt from backfill — it will be applied incrementally
    # after backfill completes so it isn't counted twice.
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

  # ── feature flag ──────────────────────────────────────────────────────────

  # FSRS_ENABLED env var gates the new scheduling path drill-by-drill.
  # Set FSRS_ENABLED=1 in .env (development) or as a server env var (production).
  # The drill still works when the flag is off — falls through to legacy path.
  def fsrs_enabled?
    ENV["FSRS_ENABLED"].to_s == "1"
  end
end
