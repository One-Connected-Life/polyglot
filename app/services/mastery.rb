# The retire-and-celebrate POLICY on top of FSRS (#axis-4).
#
# FSRS itself never "finishes" a card — it just keeps stretching the interval.
# This is the gap our differentiator fills: when stability crosses a threshold,
# the word is genuinely owned and drops out of rotation. We celebrate the moment.
#
# Stability = "days until recall drops to 90%". RETIRE_STABILITY_DAYS = 180
# means: once FSRS predicts ~6-month recall, stop drilling it and mark the moment.
# That threshold is a starting point and is tunable here in one place.
#
# MIN_REPS guards against a single lucky jump retiring a barely-seen word.
#
# Pure policy object over a card hash — no DB, no gem dependency.
class Mastery
  RETIRE_STABILITY_DAYS = 180.0
  MIN_REPS_TO_RETIRE    = 3

  def initialize(card_hash)
    @card = (card_hash || {}).symbolize_keys
  end

  # The big moment: this word is owned for good and leaves the active rotation.
  def retired?
    stability >= RETIRE_STABILITY_DAYS && reps >= MIN_REPS_TO_RETIRE
  end

  # 0.0 → 1.0 progress toward retirement (for the thin emerald sliver affordance
  # shown on "approaching" words — never a loud bar, just a hint).
  def progress
    [stability / RETIRE_STABILITY_DAYS, 1.0].min
  end

  # Did THIS grade cross the line? Pass the card state from BEFORE the answer.
  # Used by AttemptsController to fire the celebrate exactly once, at the transition.
  def newly_retired_from?(previous_card_hash)
    retired? && !self.class.new(previous_card_hash).retired?
  end

  private

  def stability = (@card[:stability] || 0.0).to_f
  def reps      = (@card[:reps] || 0).to_i
end
