class AddAnswerModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :answer_mode, :string, default: "type", null: false
  end
end
