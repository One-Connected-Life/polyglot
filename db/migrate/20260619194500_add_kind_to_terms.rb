class AddKindToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :kind, :string, null: false, default: "word"
    add_index :terms, :kind
  end
end
