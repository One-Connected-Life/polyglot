class AddLearningLanguagesToUsers < ActiveRecord::Migration[8.1]
  def change
    # Stores the user's chosen set of target languages as a JSON array.
    # e.g. ["nl", "es", "fr"] — replaces the single `target_language` as the
    # source-of-truth for multi-language drill. Primary target is derived as
    # learning_languages.first (kept in sync with target_language column).
    add_column :users, :learning_languages, :string, default: nil
    add_column :users, :drill_direction, :string, default: "forward"
  end
end
