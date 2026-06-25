class AddShowOtherLanguagesToUsers < ActiveRecord::Migration[8.1]
  def change
    # Opt-in multi-language "weave". Default OFF → single-language is the default
    # drill (one prompt, one target). When ON, /play runs the multi-language weave.
    add_column :users, :show_other_languages, :boolean, default: false, null: false
  end
end
