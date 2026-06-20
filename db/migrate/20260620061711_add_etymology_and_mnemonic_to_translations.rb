class AddEtymologyAndMnemonicToTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :translations, :etymology, :text
    add_column :translations, :mnemonic, :text
  end
end
