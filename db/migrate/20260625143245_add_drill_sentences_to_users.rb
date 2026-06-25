class AddDrillSentencesToUsers < ActiveRecord::Migration[8.1]
  def change
    # Whether to sprinkle interleaved sentence cards into word drills.
    # Default true preserves existing behavior; users who find the sentences
    # irrelevant can turn them off in Settings.
    add_column :users, :drill_sentences, :boolean, default: true, null: false
  end
end
