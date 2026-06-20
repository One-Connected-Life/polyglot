require "net/http"
require "uri"
require "json"

# Generates a vocabulary deck for a user's target language from a topic,
# via the Anthropic Messages API (Mihai's key). Net::HTTP, no gem dependency.
class DeckGenerator
  Error = Class.new(StandardError)

  MODEL = "claude-haiku-4-5-20251001" # cheap + capable enough for vocab
  COUNT = 30
  ENDPOINT = "https://api.anthropic.com/v1/messages"

  def initialize(deck)
    @deck = deck
    @user = deck.user
  end

  def call
    words = fetch_words
    raise Error, "model returned no usable words" if words.blank?
    persist(words)
    @deck.update!(status: "ready")
  rescue StandardError => e
    @deck.update!(status: "failed")
    Rails.logger.error("[DeckGenerator] deck=#{@deck.id} #{e.class}: #{e.message}")
    raise
  end

  private

  def fetch_words
    target = @user.target_language_name
    source = @user.source_language_name

    system = "You generate vocabulary for language learners. Output ONLY a valid JSON array, no prose, no markdown fences."
    prompt = <<~PROMPT
      Generate #{COUNT} common, useful #{target} words or short phrases for the topic "#{@deck.topic}",
      for a learner whose base language is #{source}.

      Return a JSON array. Each element is an object:
        {"target": "<the word in #{target}>", "source": "<its #{source} translation>", "article": "<the definite article in #{target} if this is a noun that takes one, otherwise null>", "etymology": "<short factual origin of the #{target} word>", "mnemonic": "<a one-line memory hook in #{source}>"}

      Rules: beginner-to-intermediate, real and natural words, no duplicates, no proper nouns.
      Set "article" correctly for #{target} (e.g. Dutch de/het, German der/die/das, French le/la); use null when the language or the word takes none.
      Do NOT include the article inside the "target" value — the bare word goes in "target", the article only in "article".
      "etymology": factual origin in ≤12 words. For a compound, break it into its parts and their literal meanings (e.g. "ziek (sick) + huis (house)"). Plain text, no "From..." preamble. Use null if you don't actually know.
      "mnemonic": one short memory hook in #{source} that helps recall the #{target} word — a sound-alike, image, or literal-parts link. ≤12 words, no filler. Use null if nothing genuinely helpful comes to mind.
    PROMPT

    response = post_message(system, prompt)
    text = response.dig("content", 0, "text").to_s
    JSON.parse(strip_fences(text))
  rescue JSON::ParserError => e
    raise Error, "could not parse model output: #{e.message}"
  end

  def strip_fences(text)
    text.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
  end

  def post_message(system, prompt)
    uri = URI(ENDPOINT)
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"] = api_key
    req["anthropic-version"] = "2023-06-01"
    req["content-type"] = "application/json"
    req.body = JSON.generate(
      model: MODEL,
      max_tokens: 4000,
      system: system,
      messages: [{ role: "user", content: prompt }]
    )

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
      http.request(req)
    end
    raise Error, "Anthropic API #{res.code}: #{res.body.to_s.first(300)}" unless res.code.to_i == 200

    JSON.parse(res.body)
  end

  def api_key
    ENV["ANTHROPIC_API_KEY"].presence || raise(Error, "ANTHROPIC_API_KEY is not set")
  end

  # Models often repeat the article inside the word ("la cuisine" + article "la").
  # Strip it so with_article doesn't double it ("la la cuisine").
  def strip_redundant_article(text, article)
    return text if article.blank?

    art = article.to_s.strip
    pattern = art.end_with?("'") ? /\A#{Regexp.escape(art)}\s*/i : /\A#{Regexp.escape(art)}\s+/i
    text.sub(pattern, "")
  end

  def persist(words)
    target = @user.target_language
    source = @user.source_language
    seen = Set.new
    position = 0

    Term.transaction do
      words.each do |w|
        article = w["article"].presence
        t = strip_redundant_article(w["target"].to_s.strip, article)
        s = w["source"].to_s.strip
        next if t.blank? || s.blank?

        key = t.downcase
        next if seen.include?(key)
        seen << key

        term = @deck.terms.create!(kind: "word", position: (position += 1))
        term.translations.create!(
          language: target, text: t, article: article,
          etymology: w["etymology"].presence, mnemonic: w["mnemonic"].presence
        )
        term.translations.create!(language: source, text: s)
      end
    end
  end
end
