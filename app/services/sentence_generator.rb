require "net/http"
require "uri"
require "json"

# Builds short practice sentences "backwards from the words" — it takes the vocabulary
# the user has RECENTLY practiced and weaves natural beginner sentences that each use at
# least one of those words. The sentences land in a per-user "Recent sentences" deck as
# kind: "sentence" terms, which the drill already sprinkles in ~1-in-3 between word cards.
#
# Runs in the BACKGROUND (GenerateSentencesJob) and replaces the pool each time, so drills
# stay instant and the interludes always reflect what the learner is currently working on.
class SentenceGenerator
  Error = Class.new(StandardError)

  DECK_NAME    = "Recent sentences".freeze
  MODEL        = ENV.fetch("SENTENCE_MODEL", "claude-sonnet-4-6") # grammar accuracy matters
  ENDPOINT     = "https://api.anthropic.com/v1/messages"
  COUNT        = 8     # sentences per refresh
  RECENT_WORDS = 18    # how many recently-practiced words to draw from
  MIN_WORDS    = 4     # below this, leave it to the seeded sentences

  # Stale when there's no pool yet, it's thin, or it's older than `within`. Cheap enough to
  # check on every drill load; the job itself is the only thing that costs an API call.
  def self.stale?(user, within: 30.minutes)
    deck = user.decks.find_by(name: DECK_NAME)
    return true if deck.nil?
    count = deck.terms.count
    return true if count < COUNT
    newest = deck.terms.maximum(:updated_at)
    newest.nil? || newest < within.ago
  end

  def initialize(user)
    @user = user
  end

  def call
    words = recent_words
    return if words.size < MIN_WORDS # not enough practiced yet — seeded sentences carry it

    sentences = fetch(words)
    return if sentences.blank?
    persist(sentences)
  rescue StandardError => e
    Rails.logger.error("[SentenceGenerator] user=#{@user.id} #{e.class}: #{e.message}")
    raise
  end

  private

  # The languages this user actually drills, so each sentence renders in any direction.
  def langs
    ([@user.source_language, @user.target_language] + Array(@user.active_learning_languages))
      .compact.uniq.select { |l| Translation::LANGUAGES.key?(l) }
  end

  # Distinct target-language words from the user's most recent attempts (newest first).
  def recent_words
    term_ids = @user.attempts.order(created_at: :desc).limit(120).pluck(:term_id).uniq.first(RECENT_WORDS)
    Term.where(id: term_ids).includes(:translations)
        .filter_map { |t| t.translation(@user.target_language)&.text }
        .uniq
  end

  def fetch(words)
    target = @user.target_language_name
    lang_list = langs.map { |l| "#{Translation::LANGUAGES[l]} (#{l})" }.join(", ")

    system = "You write short, natural, grammatically correct sentences for language learners. Output ONLY a valid JSON array, no prose, no markdown fences."
    prompt = <<~PROMPT
      The learner is studying #{target} and has recently practiced these #{target} words:
      #{words.map { |w| "- #{w}" }.join("\n")}

      Write #{COUNT} short, natural, beginner-level #{target} sentences. EACH sentence must
      use AT LEAST ONE of the words above (prefer 2 where it stays natural). Keep them simple,
      everyday, and grammatically correct (articles, conjugation, word order all matter).

      Return a JSON array. Each element:
        { #{langs.map { |l| %("#{l}": "<the sentence in #{Translation::LANGUAGES[l]}>") }.join(", ")} }
      Provide every listed language: #{lang_list}. No duplicates. No proper nouns.
    PROMPT

    text = strip_fences(post_message(system, prompt))
    return [] if text.blank?
    JSON.parse(text)
  rescue JSON::ParserError => e
    raise Error, "could not parse model output: #{e.message}"
  end

  def persist(sentences)
    Deck.transaction do
      deck = @user.decks.find_or_create_by!(name: DECK_NAME) do |d|
        d.position = (@user.decks.maximum(:position) || -1) + 1
      end
      deck.update!(status: "ready")
      deck.terms.destroy_all # replace the pool — always reflects the latest words

      sentences.each_with_index do |row, i|
        next unless row.is_a?(Hash)
        term = deck.terms.create!(kind: "sentence", position: i + 1)
        langs.each do |lang|
          text = row[lang].to_s.strip
          next if text.empty?
          term.translations.create!(language: lang, text: text)
        end
        # Drop a sentence that somehow came back with no usable translations.
        term.destroy if term.translations.empty?
      end
    end
  end

  def strip_fences(text)
    text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
  end

  def post_message(system, prompt)
    key = ENV["ANTHROPIC_API_KEY"].presence or raise(Error, "ANTHROPIC_API_KEY is not set")
    uri = URI(ENDPOINT)
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"] = key
    req["anthropic-version"] = "2023-06-01"
    req["content-type"] = "application/json"
    req.body = JSON.generate(model: MODEL, max_tokens: 2000, system: system,
                             messages: [{ role: "user", content: prompt }])
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
      http.request(req)
    end
    raise Error, "Anthropic API #{res.code}: #{res.body.to_s.first(300)}" unless res.code.to_i == 200
    JSON.parse(res.body).dig("content", 0, "text").to_s
  end
end
