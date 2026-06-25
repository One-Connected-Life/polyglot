class AddCorrectFeedbackToUsers < ActiveRecord::Migration[8.1]
  def change
    # What the user hears on a correct answer: "word" (an enthusiastic "Yes!",
    # the default), "sound" (a quick celebration chime), "answer" (speak the
    # English word), or "none" (silent — the old behavior).
    add_column :users, :correct_feedback, :string, default: "word", null: false
  end
end
