require "net/http"
require "uri"
require "json"
require "yaml"
require "set"

# Builds the "Basics" category — the language-agnostic foundation every learner needs:
# pronouns, articles, prepositions, conjunctions, question words, adverbs, modals,
# numbers, adjectives, time words, colors, core nouns, social formulas, and the core
# verbs drilled ONE conjugated form per card ("I eat", "you see", "he ate").
#
#   rake basics:generate   # English master list -> all 7 languages via Anthropic -> db/seeds/basics.yml
#   rake basics:import      # idempotently attach the Basics decks to a user (SAFE on prod)
#   rake basics:count       # print how many cards the master list expands to
#
# basics.yml uses the same schema as db/seeds/vocabulary.yml so db:seed loads it too.
namespace :basics do
  MODEL = ENV.fetch("BASICS_MODEL", "claude-sonnet-4-6")
  ENDPOINT = "https://api.anthropic.com/v1/messages"
  TARGET_LANGS = %w[nl es fr it ro ru].freeze # en is the source/canonical label
  PERSONS = %w[I you he she we they].freeze
  BATCH = 16
  OUT = "db/seeds/basics.yml"

  # ---- The master English list -----------------------------------------------
  # Plain-word groups: deck name => array of English items. Each becomes one card.
  GROUPS = {
    "Pronouns" => %w[I you he she it we they me him her us them
                     my your his our their mine yours hers ours theirs
                     this that these those
                     someone something anyone anything nobody nothing everyone everything],
    "Articles & Determiners" => ["the", "a", "some", "any", "no", "every", "all", "both",
                                 "much", "many", "more", "few", "another", "other"],
    "Question Words" => ["who", "what", "where", "when", "why", "how", "which", "whose",
                         "how much", "how many"],
    "Conjunctions" => %w[and or but so because if while although that than
                         before after until since though],
    "Prepositions" => %w[in on at to from with without for of about by near under over
                         between into through against around],
    "Yes / No / Negation" => ["yes", "no", "not", "never", "maybe"],
    "Adverbs" => ["now", "then", "today", "tomorrow", "yesterday", "soon", "already",
                  "still", "yet", "always", "often", "sometimes", "here", "there",
                  "very", "too", "almost", "only", "just", "well", "fast", "together",
                  "again", "also"],
    "Modal Verbs" => ["can", "could", "will", "would", "should", "must", "may", "might",
                      "want to", "have to", "need to"],
    "Numbers" => %w[zero one two three four five six seven eight nine ten
                    eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen
                    nineteen twenty thirty forty fifty sixty seventy eighty ninety
                    hundred thousand first second third],
    "Adjectives" => %w[big small good bad hot cold new old fast slow easy hard
                       near far high low happy sad open closed full empty same different
                       long short right wrong young strong],
    "Time Words" => ["day", "week", "month", "year", "hour", "minute", "morning",
                     "afternoon", "evening", "night", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday", "Sunday", "weekend", "tonight",
                     "always"],
    "Colors" => %w[red blue green yellow black white gray brown orange pink purple],
    "Core Nouns" => %w[person man woman child family friend thing place home city
                       country water food money time name word hand eye],
    "Social Phrases" => ["hello", "goodbye", "please", "thank you", "you're welcome",
                         "sorry", "excuse me", "good morning", "good night", "how are you"],
  }.freeze

  # Core verbs: [base, 3rd-singular present, simple past]. "be" is special-cased below.
  VERBS = [
    %w[have has had], %w[do does did], %w[go goes went], %w[come comes came],
    %w[get gets got], %w[make makes made], %w[take takes took], %w[give gives gave],
    %w[say says said], %w[see sees saw], %w[know knows knew], %w[think thinks thought],
    %w[want wants wanted], %w[need needs needed], %w[like likes liked], %w[use uses used],
    %w[find finds found], %w[work works worked], %w[eat eats ate], %w[drink drinks drank],
    %w[sleep sleeps slept], %w[live lives lived], %w[speak speaks spoke], %w[feel feels felt],
    %w[become becomes became], %w[leave leaves left], %w[put puts put], %w[keep keeps kept],
    %w[begin begins began], %w[help helps helped], %w[show shows showed], %w[hear hears heard],
    %w[play plays played], %w[run runs ran], %w[ask asks asked], %w[try tries tried],
    %w[call calls called], %w[tell tells told], %w[love loves loved], %w[read reads read],
  ].freeze

  # ---- English card expansion ------------------------------------------------
  # Returns [{key:, deck:, en:, type:}] for every card in the master list.
  # key is a stable, content-derived id (e.g. "pronouns/her", "verbs/i-eat") used as
  # the idempotency anchor for import — survives reordering and appends. Exact-duplicate
  # English within a deck (object vs possessive "her"; present vs past "I read") gets a
  # "-2" suffix so each card keeps a distinct, stable identity.
  def self.cards
    list = []
    GROUPS.each do |deck, items|
      type = noun_group?(deck) ? "noun" : "word"
      items.each { |en| list << { "deck" => "Basics: #{deck}", "en" => en, "type" => type } }
    end
    list.concat(verb_cards)
    assign_keys(list)
    list
  end

  def self.slug(str)
    str.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def self.assign_keys(list)
    occ = Hash.new(0)
    list.each do |c|
      base = "#{slug(c["deck"].sub(/\ABasics: /, ""))}/#{slug(c["en"])}"
      occ[base] += 1
      c["key"] = occ[base] > 1 ? "#{base}-#{occ[base]}" : base
    end
  end

  # Legacy basics.yml entries (written before keys existed) get keys assigned by
  # matching each [deck, en] to the master list in order. No API calls.
  def self.backfill_keys(existing, all)
    queues = Hash.new { |h, k| h[k] = [] }
    all.each { |c| queues[[c["deck"], c["en"]]] << c["key"] }
    existing.each do |e|
      next if e["key"]
      e["key"] = queues[[e["deck"], e["en"]]].shift
    end
    existing
  end

  def self.noun_group?(deck)
    ["Core Nouns", "Time Words", "Colors"].include?(deck)
  end

  # One card per conjugated form: "I eat", "he eats", "they ate", "you will eat", ...
  def self.verb_cards
    out = []
    verbs = [["be", :be]] + VERBS.map { |b, p3, past| [b, p3, past] }
    verbs.each do |spec|
      base = spec[0]
      forms = spec[1] == :be ? be_forms : regular_forms(*spec)
      forms.each do |en|
        out << { "deck" => "Basics: Verbs", "en" => en, "type" => "verb" }
      end
    end
    out
  end

  def self.regular_forms(base, p3, past)
    present = PERSONS.map { |p| %w[he she].include?(p) ? "#{p} #{p3}" : "#{p} #{base}" }
    past_f  = PERSONS.map { |p| "#{p} #{past}" }
    future  = PERSONS.map { |p| "#{p} will #{base}" }
    present + past_f + future
  end

  def self.be_forms
    pres = { "I" => "am", "you" => "are", "he" => "is", "she" => "is", "we" => "are", "they" => "are" }
    pst  = { "I" => "was", "you" => "were", "he" => "was", "she" => "was", "we" => "were", "they" => "were" }
    PERSONS.map { |p| "#{p} #{pres[p]}" } +
      PERSONS.map { |p| "#{p} #{pst[p]}" } +
      PERSONS.map { |p| "#{p} will be" }
  end

  # ---- Tasks -----------------------------------------------------------------
  desc "Print how many cards the Basics master list expands to (per deck + total)"
  task :count do
    by_deck = cards.group_by { |c| c["deck"] }
    by_deck.sort.each { |deck, cs| puts format("%5d  %s", cs.size, deck) }
    puts format("%5d  TOTAL  (%d languages = %d translations)", cards.size, 7, cards.size * 7)
  end

  desc "Generate db/seeds/basics.yml: translate every Basics card into all 7 languages (resumable)"
  task :generate do
    all = cards
    order = all.each_with_index.to_h { |c, idx| [c["key"], idx] }
    existing = File.exist?(OUT) ? (YAML.load_file(OUT) || []) : []
    existing = backfill_keys(existing, all)
    done = existing.map { |e| e["key"] }.compact.to_set
    todo = all.reject { |c| done.include?(c["key"]) }

    puts "Basics: #{all.size} cards total, #{done.size} already done, #{todo.size} to generate."
    accumulated = existing.dup
    # Always reflush once so legacy entries pick up their backfilled keys, even with no API work.
    flush = lambda do
      accumulated.sort_by! { |e| order.fetch(e["key"], 1 << 30) }
      File.write(OUT, yaml_header + accumulated.to_yaml.sub(/\A---\n/, ""))
    end
    flush.call

    failed = 0
    todo.each_slice(BATCH).with_index do |batch, i|
      print "  batch #{i + 1} (#{batch.size} items)… "
      begin
        accumulated.concat(translate_batch(batch))
        flush.call
        puts "ok (#{accumulated.size}/#{all.size})"
      rescue => e
        failed += 1
        puts "FAILED (#{e.message.to_s[0, 100]}) — skipping, re-run to resume"
      end
    end
    puts "Wrote #{OUT}. #{failed} batch(es) failed#{' — re-run `rake basics:generate` to fill them' if failed.positive?}."
  end

  desc "Idempotently attach the Basics decks to a user. SAFE on prod (no wipe). Usage: rake basics:import[email]"
  task :import, [:email] => :environment do |_t, args|
    email = args[:email].presence || ENV["BASICS_EMAIL"].presence ||
            User.order(:id).first&.email_address
    abort "No user found / no email given." unless email
    owner = User.find_by!(email_address: email)
    entries = YAML.load_file(Rails.root.join(OUT))
    created = 0

    updated = 0
    entries.group_by { |e| e["deck"] }.each do |deck_name, rows|
      deck = owner.decks.find_or_create_by!(name: deck_name) do |d|
        d.position = owner.decks.count
      end
      rows.each_with_index do |row, idx|
        # Match on the stable key first (survives label edits/renames); fall back to the
        # English label for terms imported before keys existed, then stamp the key on them.
        # term_id never churns -> FSRS schedulings + attempts (which hang off term_id) survive.
        term = (deck.terms.find_by(key: row["key"]) if row["key"].present?)
        term ||= deck.terms.joins(:translations)
                     .where(translations: { language: "en", text: row["en"] })
                     .where(key: nil).first
        if term
          attrs = {}
          attrs[:key]  = row["key"] if row["key"].present? && term.key != row["key"]
          attrs[:kind] = term_kind(row) if term.kind != term_kind(row)
          term.update!(attrs) if attrs.any?
        else
          term = deck.terms.create!(key: row["key"].presence, kind: term_kind(row), position: idx + 1)
          created += 1
        end
        updated += 1 if upsert_translations(term, row)
      end
    end
    puts "Basics import for #{email}: +#{created} new terms, #{updated} terms with translation upserts " \
         "(#{Deck.where(user: owner).where("name LIKE 'Basics:%'").count} Basics decks). No data destroyed."
  end

  # ---- helpers ---------------------------------------------------------------
  def self.term_kind(row)
    %w[verb].include?(row["type"]) ? "phrase" : "word"
  end

  # Create-or-update each language translation in place. Returns true if anything changed.
  def self.upsert_translations(term, row)
    changed = false
    (%w[en] + TARGET_LANGS).each do |lang|
      val = row[lang]
      next if val.nil?
      text    = val.is_a?(Hash) ? val["text"] : val.to_s
      article = val.is_a?(Hash) ? val["article"] : nil
      next if text.to_s.strip.empty?

      tr = term.translations.find_or_initialize_by(language: lang)
      tr.text = text
      tr.article = article
      if tr.changed?
        tr.save!
        changed = true
      end
    end
    changed
  end

  def self.yaml_header
    <<~H
      # The "Basics" category — language-agnostic foundation, generated by `rake basics:generate`.
      # Same schema as vocabulary.yml. en = canonical label; verbs are one conjugated form per card.
      # Regenerate (resumable) rather than hand-editing; run `rake basics:import` to load onto prod.
    H
  end

  def self.translate_batch(batch)
    items = batch.each_with_index.map do |c, i|
      { "id" => i, "en" => c["en"], "type" => c["type"] }
    end
    prompt = <<~PROMPT
      Translate each English item below into these languages: Dutch (nl), Spanish (es),
      French (fr), Italian (it), Romanian (ro), Russian (ru). Give the natural, most
      common everyday form a beginner needs.

      - type "verb": the item is a conjugated English phrase like "he eats" / "they ate" /
        "you will go". Return the natural equivalent INCLUDING the subject pronoun
        (e.g. nl "hij eet", es "él come", fr "il mange", it "lui mangia", ro "el mănâncă",
        ru "он ест"). Match person, number, and tense exactly. article = null.
      - type "noun": return the bare noun in "text" and its definite article in "article"
        for languages that use one (nl de/het, es el/la, fr le/la, it il/la/lo/l', ro -ul/-a
        as a suffixed article -> use null and keep the article in text only if inseparable;
        otherwise null), else null.
      - all other types: return the single most common word; article = null.

      Output ONLY a JSON array, no prose, no markdown fences. One object per input id:
      {"id": <id>, "nl": {"text": "...", "article": "de|het|null"},
       "es": {"text":"...","article":null}, "fr": {...}, "it": {...},
       "ro": {"text":"...","article":null}, "ru": {"text":"...","article":null}}
      Use null (not "null" string) for absent articles.

      ITEMS:
      #{JSON.pretty_generate(items)}
    PROMPT

    # Retry the call when the model returns prose instead of JSON (non-deterministic).
    parsed = nil
    tries = 0
    begin
      tries += 1
      raw = post_message("You are a precise multilingual lexicographer. Output only valid JSON.", prompt)
      parsed = JSON.parse(strip_fences(raw))
    rescue JSON::ParserError
      retry if tries < 4
      raise
    end
    by_id = parsed.to_h { |r| [r["id"], r] }

    batch.each_with_index.map do |c, i|
      r = by_id[i] || {}
      entry = { "key" => c["key"], "deck" => c["deck"], "en" => c["en"], "type" => c["type"] }
      TARGET_LANGS.each do |lang|
        cell = r[lang]
        next unless cell
        text = cell.is_a?(Hash) ? cell["text"] : cell
        art  = cell.is_a?(Hash) ? cell["article"] : nil
        next if text.to_s.strip.empty?
        entry[lang] = art.to_s.strip.empty? ? text.to_s.strip : { "text" => text.to_s.strip, "article" => art.to_s.strip }
      end
      entry
    end
  end

  def self.strip_fences(text)
    text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
  end

  # Retries on rate-limit (429) and overload/5xx (Sonnet returns 529 under load) with
  # exponential backoff. Raises (not aborts) so the caller can skip a batch and resume.
  def self.post_message(system, prompt)
    key = ENV["ANTHROPIC_API_KEY"].presence or abort "ANTHROPIC_API_KEY is not set"
    uri = URI(ENDPOINT)
    attempt = 0
    begin
      attempt += 1
      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = key
      req["anthropic-version"] = "2023-06-01"
      req["content-type"] = "application/json"
      req.body = JSON.generate(model: MODEL, max_tokens: 8000, system: system,
                               messages: [{ role: "user", content: prompt }])
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120, open_timeout: 15) do |http|
        http.request(req)
      end
      code = res.code.to_i
      raise "Anthropic API #{code}: #{res.body.to_s.first(200)}" if code == 429 || code >= 500
      raise "Anthropic API #{code}: #{res.body.to_s.first(300)}" unless code == 200
      JSON.parse(res.body).dig("content", 0, "text").to_s
    rescue => e
      if attempt < 6
        sleep([2**attempt, 30].min)
        retry
      end
      raise
    end
  end
end
