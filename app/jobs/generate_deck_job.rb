class GenerateDeckJob < ApplicationJob
  queue_as :default

  def perform(deck)
    # Land topic decks in "review" too, so every imported collection is reviewable
    # (word count + import time + label) before it becomes drillable.
    DeckGenerator.new(deck, final_status: "review").call
  end
end
