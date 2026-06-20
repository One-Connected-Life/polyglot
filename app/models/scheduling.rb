# FSRS scheduling cache — one row per (user, term, direction). (#axis-4)
#
# Columns mirror Fsrs::Card#to_h (FsrsScheduler::CARD_KEYS) + our additions:
#   ease       — 1–5 AI-prefilled, user-adjustable (1=cognate-trivial, 5=hard)
#   backfilled — true once the attempt-replay has run for this row
#   archived   — user's "done forever" flag (stops even long-interval resurfacing)
#
# The row is a DERIVED CACHE.  Source of truth is the `attempts` table.
# Never mutate these columns by hand; go through AttemptsController (live path)
# or FsrsScheduler.replay (backfill path).
class Scheduling < ApplicationRecord
  belongs_to :user
  belongs_to :term

  validates :from_language, :to_language, presence: true
  validates :ease, inclusion: { in: 1..5 }
  validates :term_id, uniqueness: { scope: [:user_id, :from_language, :to_language],
                                     message: "already has a scheduling row for this direction" }

  # ── scopes ────────────────────────────────────────────────────────────────

  # Cards that are due now in a given direction (FSRS gate).
  # NEW cards (state=0, never reviewed) are always returned.
  scope :due_now, ->(from:, to:, now: Time.current) {
    where(from_language: from, to_language: to, archived: false)
      .where("state = 0 OR due <= ?", now)
  }

  # Words that have reached retirement criteria (stability + reps threshold).
  scope :retired, -> {
    where(archived: false)
      .where("stability >= ? AND reps >= ?",
             Mastery::RETIRE_STABILITY_DAYS,
             Mastery::MIN_REPS_TO_RETIRE)
  }

  # Approaching retirement (progress > 0.5 but not yet retired) — the "almost
  # there" shelf shown on /stats.
  scope :approaching_retirement, -> {
    where(archived: false)
      .where("stability >= ? AND stability < ? AND reps >= 1",
             Mastery::RETIRE_STABILITY_DAYS * 0.5,
             Mastery::RETIRE_STABILITY_DAYS)
  }

  # English cognates (ease=1) — auto-skipped from drilling rotation.
  scope :cognate_trivial, -> { where(ease: 1) }

  # ── helpers ───────────────────────────────────────────────────────────────

  # Is this word retired per the Mastery policy?
  def retired?
    Mastery.new(card_hash).retired?
  end

  # Progress (0.0–1.0) toward retirement.
  def retirement_progress
    Mastery.new(card_hash).progress
  end

  # Estimated recall interval in months (rounded), for display.
  def recall_months
    (stability / 30.0).round
  end

  # Expose card state as the hash that FsrsScheduler / Mastery expect.
  def card_hash
    {
      state:          state,
      due:            due,
      stability:      stability,
      difficulty:     difficulty,
      elapsed_days:   elapsed_days,
      scheduled_days: scheduled_days,
      reps:           reps,
      lapses:         lapses,
      last_review:    last_review,
    }
  end

  # Persist an updated card hash back to this row (called after apply()).
  def update_from_card_hash!(hash)
    update!(
      state:          hash[:state],
      due:            hash[:due],
      stability:      hash[:stability],
      difficulty:     hash[:difficulty],
      elapsed_days:   hash[:elapsed_days],
      scheduled_days: hash[:scheduled_days],
      reps:           hash[:reps],
      lapses:         hash[:lapses],
      last_review:    hash[:last_review],
    )
  end
end
