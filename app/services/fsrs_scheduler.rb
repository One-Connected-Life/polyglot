# FSRS scheduling — adapter between our Attempt stream and the `fsrs` gem (#axis-4).
#
# The gem owns the math; this class owns the translation + our policy on top.
# Our binary signal (correct?) maps to FSRS's 4-point rating: GOOD / AGAIN.
#
# See also: Mastery (the retire-and-celebrate policy layer above FSRS).
#
#   our world                         fsrs gem
#   ---------                         --------
#   correct? boolean        ->        Rating::GOOD / Rating::AGAIN
#   Attempt.created_at      ->        review timestamp (UTC, tz-aware DateTime)
#   ease (1–5 int)          ->        seeded into initial difficulty on first review
#   a hash of card columns  <->       Fsrs::Card (state/stability/difficulty/due/…)
#
# Usage:
#   sched = FsrsScheduler.new
#   card  = sched.blank_card
#   card  = sched.apply(card, correct: true, at: attempt.created_at)
#   card  => { state:, due:, stability:, difficulty:, reps:, lapses:, ... }
#
# Backfill from attempt history:
#   card = sched.replay(attempts)    # attempts chronological, each has .correct + .created_at
#
class FsrsScheduler
  require "fsrs"
  require "date"

  # Columns persisted per (user, term, from_language, to_language).
  # Mirrors Fsrs::Card#to_h — round-tripping is lossless.
  CARD_KEYS = %i[state due stability difficulty elapsed_days scheduled_days reps lapses last_review].freeze

  # Ease (1–5) → FSRS rating to use on the FIRST correct review of a NEW card.
  # FSRS computes initial difficulty from the rating via init_difficulty(), so
  # rating selection is the only lever we have.  Ratings 1–4 yield difficulties
  # ~6.81 / ~5.87 / ~4.93 / ~3.99 (default parameters).
  # We keep HARD/GOOD/EASY; AGAIN is reserved for wrong answers only.
  #   1 (cognate-trivial)  → EASY   → difficulty ~3.99, long first interval
  #   2 (clearly related)  → EASY
  #   3 (moderate/default) → GOOD   → difficulty ~4.93
  #   4 (hard)             → HARD   → difficulty ~5.87
  #   5 (very hard)        → HARD
  EASE_TO_FIRST_RATING = {
    1 => :easy,
    2 => :easy,
    3 => :good,
    4 => :hard,
    5 => :hard,
  }.freeze

  def initialize(scheduler: Fsrs::Scheduler.new)
    @scheduler = scheduler
  end

  # A fresh card: never studied (state NEW). Returned as a plain hash so callers
  # never hold a gem object — the gem stays an implementation detail.
  def blank_card
    to_hash(Fsrs::Card.new)
  end

  # Grade one answer. `correct:` is our binary signal.
  # `ease:` (1–5) adjusts the FSRS rating on the FIRST correct review of a NEW
  # card — the only moment we can influence the initial difficulty seed.
  # Returns the next card state as a hash.
  def apply(card_hash, correct:, at:, ease: nil)
    card = from_hash(card_hash)

    if correct
      # On the first correct review of a NEW card, use ease to select a rating
      # that seeds FSRS's initial difficulty appropriately.
      is_first_review = card.state == Fsrs::State::NEW
      ease_rating = is_first_review && ease ? EASE_TO_FIRST_RATING[ease.to_i] : nil
      rating = case ease_rating
               when :easy then Fsrs::Rating::EASY
               when :hard then Fsrs::Rating::HARD
               else            Fsrs::Rating::GOOD
               end
    else
      rating = Fsrs::Rating::AGAIN
    end

    result = @scheduler.repeat(card, utc(at))[rating]
    to_hash(result.card)
  end

  # Rebuild a card from scratch by replaying its attempt history chronologically.
  # Backfill primitive: existing users have years of Attempts and no card rows.
  # `attempts` must respond to #each yielding objects with `correct` and `created_at`.
  def replay(attempts, ease: nil)
    attempts.reduce(blank_card) do |card, attempt|
      apply(card, correct: attempt.correct, at: attempt.created_at, ease: ease)
    end
  end

  # Is this card due for review at `now`? NEW cards are always due.
  def due?(card_hash, now: Time.current)
    card = from_hash(card_hash)
    return true if card.state == Fsrs::State::NEW
    card.due <= utc(now)
  end

  private

  def from_hash(hash)
    card = Fsrs::Card.new
    hash = hash.symbolize_keys
    CARD_KEYS.each do |key|
      next unless hash.key?(key)
      value = hash[key]
      value = coerce_date(value) if %i[due last_review].include?(key) && value
      card.public_send("#{key}=", value)
    end
    card
  end

  def to_hash(card)
    card.to_h.slice(*CARD_KEYS)
  end

  # FSRS needs a UTC, timezone-aware DateTime.
  def utc(time)
    time = coerce_date(time)
    time.respond_to?(:new_offset) ? time.new_offset(0) : time.to_datetime.new_offset(0)
  end

  def coerce_date(value)
    case value
    when DateTime then value
    when Time     then value.to_datetime
    when String   then DateTime.parse(value)
    else value
    end
  end
end
