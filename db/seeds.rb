# Rebuilds the vocabulary from db/seeds/vocabulary.yml.
# The YAML is the source of truth: each run wipes terms/translations and reloads,
# so editing the YAML and re-running `bin/rails db:seed` always converges.
require "yaml"

path = Rails.root.join("db/seeds/vocabulary.yml")

unless File.exist?(path)
  warn "No db/seeds/vocabulary.yml yet — skipping vocabulary seed."
  return
end

entries = YAML.load_file(path)
langs = Translation::LANGUAGES.keys

ActiveRecord::Base.transaction do
  Attempt.delete_all # term ids are rebuilt below; reseeding therefore resets miss history
  Translation.delete_all
  Term.delete_all
  Deck.delete_all

  deck_cache = {}
  positions = Hash.new(0)

  entries.each do |row|
    deck_name = row.fetch("deck")
    deck = deck_cache[deck_name] ||= Deck.create!(name: deck_name, position: deck_cache.size)

    term = deck.terms.create!(position: (positions[deck.id] += 1))

    langs.each do |lang|
      value = row[lang]
      next if value.nil?

      if value.is_a?(Hash)
        term.translations.create!(
          language: lang,
          text: value["text"],
          article: value["article"],
          alternates: Array(value["alt"]).join("|").presence
        )
      else
        term.translations.create!(language: lang, text: value.to_s)
      end
    end
  end
end

puts "Seeded #{Deck.count} decks, #{Term.count} terms, #{Translation.count} translations."
