class AddKeyToTerms < ActiveRecord::Migration[8.1]
  def change
    # Stable business key for seeded/imported terms (e.g. "pronouns/her-2"). Lets
    # `basics:import` upsert idempotently without churning term_id — so FSRS progress
    # and attempts survive re-runs and translation fixes. Nullable: user/AI decks have none.
    add_column :terms, :key, :string
    add_index :terms, [:deck_id, :key], unique: true, where: "key IS NOT NULL"
  end
end
