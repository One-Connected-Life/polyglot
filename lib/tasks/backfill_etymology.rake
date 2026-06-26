require "net/http"
require "uri"
require "json"

# Re-prompts all existing target-language translations for etymology + mnemonic.
# Idempotent: skips rows where both fields are already populated.
#
# Usage:
#   bin/rails etymology:backfill
#   bin/rails etymology:backfill LANGUAGE=nl          # limit to one target language
#   bin/rails etymology:backfill DRY_RUN=1            # print what would be updated
namespace :etymology do
  desc "Backfill etymology + mnemonic for existing translations (idempotent)"
  task backfill: :environment do
    dry_run  = ENV["DRY_RUN"] == "1"
    language = ENV["LANGUAGE"].presence

    # Only target-language rows carry etymology (source rows are plain translations).
    # A row needs backfill when at least one field is still NULL.
    # Join through terms→decks→users to restrict to the user's own target language.
    # A row needs backfill when etymology OR mnemonic is NULL, or the phonetics
    # JSON has no "ipa" key yet. (phonetics stores {"ipa":..,"translit":..} as text.)
    scope = Translation
      .joins(term: { deck: :user })
      .where("translations.language = users.target_language")
      .where("translations.etymology IS NULL OR translations.mnemonic IS NULL " \
             "OR translations.phonetics IS NULL OR translations.phonetics NOT LIKE '%\"ipa\"%'")
    scope = scope.where(language: language) if language

    total = scope.count
    puts "[etymology:backfill] #{dry_run ? "DRY RUN — " : ""}#{total} translation(s) to backfill"
    puts "[etymology:backfill] Filtering to language=#{language}" if language

    updated = 0
    failed  = 0

    scope.includes(term: { deck: :user }).find_each do |t|
      user        = t.term.deck.user
      target_name = user.target_language_name
      source_name = user.source_language_name

      system_msg = "You are a factual etymology assistant. Output ONLY a valid JSON object, no prose."
      prompt = <<~PROMPT
        Word: "#{t.text}"#{t.article.present? ? " (article: #{t.article})" : ""}
        Language: #{target_name}
        Learner's base language: #{source_name}

        Return a JSON object:
          {"etymology": "<factual origin in ≤12 words, compound → parts + meanings, null if unknown>",
           "mnemonic": "<one #{source_name} memory hook ≤12 words, null if none>",
           "ipa": "<IPA transcription of the word, no surrounding slashes/brackets>"}
      PROMPT

      if dry_run
        puts "  [dry] would backfill translation #{t.id} (#{t.language}:#{t.text})"
        next
      end

      begin
        response = EtymologyBackfillHelper.post_message(system_msg, prompt)
        text     = response.dig("content", 0, "text").to_s.strip
        text     = text.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
        data     = JSON.parse(text)

        etymology = data["etymology"].presence
        mnemonic  = data["mnemonic"].presence
        ipa       = data["ipa"].presence

        # Only write fields that are missing — never overwrite existing curated data.
        attrs = {}
        attrs[:etymology] = etymology if t.etymology.nil?
        attrs[:mnemonic]  = mnemonic  if t.mnemonic.nil?
        # ipa lives inside the phonetics JSON blob — merge, don't clobber translit.
        if ipa && t.phonetics_data["ipa"].blank?
          attrs[:phonetics] = t.phonetics_data.merge("ipa" => ipa).to_json
        end

        t.update_columns(**attrs) if attrs.any?
        updated += 1
        print "."
      rescue => e
        failed += 1
        $stderr.puts "\n[etymology:backfill] FAILED translation #{t.id} (#{t.text}): #{e.message}"
      end

      # Gentle rate-limiting — Haiku handles fast bursts but be a good citizen.
      sleep 0.1
    end

    puts "\n[etymology:backfill] Done. updated=#{updated} failed=#{failed} total=#{total}"
  end
end

# Extracted helper so it can be called from the rake task body without
# hitting Rake's lack of private/module_function in namespace blocks.
module EtymologyBackfillHelper
  def self.post_message(system_msg, prompt)
    api_key = ENV["ANTHROPIC_API_KEY"].presence || raise("ANTHROPIC_API_KEY is not set")
    uri = URI("https://api.anthropic.com/v1/messages")
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"]          = api_key
    req["anthropic-version"]  = "2023-06-01"
    req["content-type"]       = "application/json"
    req.body = JSON.generate(
      model:      DeckGenerator::MODEL,
      max_tokens: 256,
      system:     system_msg,
      messages:   [{ role: "user", content: prompt }]
    )
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30, open_timeout: 10) do |http|
      http.request(req)
    end
    raise "Anthropic API #{res.code}: #{res.body.to_s.first(300)}" unless res.code.to_i == 200
    JSON.parse(res.body)
  end
end
