class CreateAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :attempts do |t|
      t.references :term, null: false, foreign_key: true
      t.string :from_language, null: false
      t.string :to_language, null: false
      t.boolean :correct, null: false, default: false
      t.string :given

      t.timestamps
    end
    add_index :attempts, [:from_language, :to_language, :term_id]
  end
end
