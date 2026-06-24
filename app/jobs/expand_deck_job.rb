# Add a fresh cohort of words to an existing topic deck (the "add more" flow).
# The deck stays "ready" and drillable throughout; the new words land reviewed: false
# so they surface in the review screen before joining practice.
class ExpandDeckJob < ApplicationJob
  queue_as :default

  def perform(deck)
    DeckGenerator.new(deck, append: true).call
  rescue StandardError => e
    Rails.logger.error("[ExpandDeckJob] deck=#{deck.id} #{e.class}: #{e.message}")
  ensure
    deck.update_columns(expanding: false)
  end
end
