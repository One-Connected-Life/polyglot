# Additive, idempotent application of alternates + sentences to the CURRENT db,
# without wiping terms/attempts. (db:seed rebuilds from scratch; this preserves.)
require "yaml"

# 1) English answer alternates
alt = YAML.load_file(Rails.root.join("db/seeds/alternates.yml"))
applied = 0
alt.each do |label, alts|
  next if alts.blank?
  Translation.where(language: "en", text: label).find_each do |t|
    t.update!(alternates: Array(alts).join("|"))
    applied += 1
  end
end

# 2) Sentences -> a "Sentences" deck, kind: "sentence"
deck = Deck.find_or_create_by!(name: "Sentences") { |d| d.position = 99 }
sentences = YAML.load_file(Rails.root.join("db/seeds/sentences.yml"))
added = 0
sentences.each do |row|
  exists = deck.terms.joins(:translations)
                .where(translations: { language: "nl", text: row["nl"] }).exists?
  next if exists
  term = deck.terms.create!(kind: "sentence", position: deck.terms.count + 1)
  term.translations.create!(language: "nl", text: row["nl"])
  term.translations.create!(language: "en", text: row["en"])
  added += 1
end

puts "alternates applied to #{applied} translations; #{added} sentences added (deck now #{deck.terms.count})."
