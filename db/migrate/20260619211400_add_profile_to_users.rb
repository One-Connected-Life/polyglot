class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :target_language, :string   # the language being learned (nil until onboarded)
    add_column :users, :source_language, :string, default: "en", null: false
    add_column :users, :generations_count, :integer, default: 0, null: false # AI deck-gen counter (cap)
  end
end
