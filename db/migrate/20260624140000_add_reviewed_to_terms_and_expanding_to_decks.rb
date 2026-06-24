class AddReviewedToTermsAndExpandingToDecks < ActiveRecord::Migration[8.1]
  def change
    # Per-term review gate. Existing words are already drilling → default true.
    # Newly-appended words (a fresh cohort added to a ready deck) come in as false
    # so they await review without pulling the rest of the deck out of practice.
    add_column :terms, :reviewed, :boolean, default: true, null: false

    # Transient flag while a deck is generating an additional cohort in the
    # background. Keeps the deck "ready" (still drillable) while it expands.
    add_column :decks, :expanding, :boolean, default: false, null: false
  end
end
