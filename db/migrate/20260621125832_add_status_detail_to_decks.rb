class AddStatusDetailToDecks < ActiveRecord::Migration[8.1]
  def change
    add_column :decks, :status_detail, :string
  end
end
