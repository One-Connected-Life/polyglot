class AddUserToDecksAndAttempts < ActiveRecord::Migration[8.1]
  def change
    add_reference :decks, :user, foreign_key: true        # nullable: existing global decks backfill to the owner
    add_reference :attempts, :user, foreign_key: true
    add_column :decks, :topic, :string                    # the AI topic this deck was generated from (nil for seeded)

    # Slugs are unique per user now, not globally (two users can both have "Groceries").
    remove_index :decks, :slug
    add_index :decks, [:user_id, :slug], unique: true
  end
end
