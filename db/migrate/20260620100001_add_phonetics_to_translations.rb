# Adds a phonetics JSON column to translations for storing IPA and transliteration.
# Structure: { "ipa" => "xlʲep", "translit" => "khleb" }
# translit is only set for non-Latin script languages (currently Russian).
class AddPhoneticsToTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :translations, :phonetics, :text
  end
end
