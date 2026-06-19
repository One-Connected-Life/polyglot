class AddAlternatesToTranslations < ActiveRecord::Migration[8.1]
  def change
    # Pipe-separated extra acceptable answers, e.g. "morning" for tomorrow/morgen.
    add_column :translations, :alternates, :string
  end
end
