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

  # transcript: when present, extract the vocabulary that actually appears in this text
  # (audio→vocab, issue #3) instead of generating fresh words from deck.topic.
  # final_status: the status the deck lands in once words are persisted — "ready" for
  # topic decks (drillable immediately), "review" for audio decks (user prunes first).
  def initialize(deck, transcript: nil, final_status: "ready")
    @deck = deck
    @user = deck.user
    @transcript = transcript.to_s.strip.presence
    @final_status = final_status
  end

  def call
    words = fetch_words
    raise Error, "model returned no usable words" if words.blank?
    persist(words)
    @deck.update!(status: @final_status)
  rescue StandardError => e
    @deck.update!(status: "failed")
    Rails.logger.error("[DeckGenerator] deck=#{@deck.id} #{e.class}: #{e.message}")
    raise
  end

  # Run extraction/generation only and return the raw word hashes, without persisting.
  # Used by the audio test harness (lib/tasks/audio.rake) to preview a transcript's deck.
  def candidate_words
    fetch_words
  end

  private

  def fetch_words
    target = @user.target_language_name
    source = @user.source_language_name
    target_code = @user.target_language
    non_latin = Translation::NON_LATIN.include?(target_code)

    system = "You generate vocabulary for language learners. Output ONLY a valid JSON array, no prose, no markdown fences."

    ipa_field = '"ipa": "<IPA pronunciation of the target word, e.g. /xlʲep/ written without slashes>"'
    translit_field = non_latin ?
      '"translit": "<spelling-based romanization of the target word (e.g. Russian хлеб → khleb, final б = b even though pronounced p)>"' :
      '"translit": null'

    task = if @transcript
      <<~TASK
        Below is a transcript of #{target} audio. Extract the useful vocabulary a learner
        would need to understand it — the meaningful words and short phrases that ACTUALLY
        APPEAR in the transcript. Up to #{COUNT} items, fewer if the transcript is short.
        Do NOT invent words that are not in the transcript. Skip filler, names, and trivial
        function words. For a learner whose base language is #{source}.

        TRANSCRIPT:
        \"\"\"
        #{@transcript}
        \"\"\"
      TASK
    else
      <<~TASK
        Generate #{COUNT} common, useful #{target} words or short phrases for the topic
        "#{@deck.topic}", for a learner whose base language is #{source}.
      TASK
    end

    prompt = <<~PROMPT
      #{task}
      Return a JSON array. Each element is an object:
        {
          "target": "<the word in #{target}>",
          "source": "<its #{source} translation>",
          "article": "<the definite article in #{target} if this is a noun that takes one, otherwise null>",
          "etymology": "<short factual origin of the #{target} word>",
          "mnemonic": "<a one-line memory hook in #{source}>",
          #{ipa_field},
          #{translit_field}
        }

      Rules: beginner-to-intermediate, real and natural words, no duplicates, no proper nouns.
      Set "article" correctly for #{target} (e.g. Dutch de/het, German der/die/das, French le/la); use null when the language or the word takes none.
      Do NOT include the article inside the "target" value — the bare word goes in "target", the article only in "article".
      "etymology": factual origin in ≤12 words. For a compound, break it into its parts and their literal meanings (e.g. "ziek (sick) + huis (house)"). Plain text, no "From..." preamble. Use null if you don't actually know.
      "mnemonic": one short memory hook in #{source} that helps recall the #{target} word — a sound-alike, image, or literal-parts link. ≤12 words, no filler. Use null if nothing genuinely helpful comes to mind.
      For "ipa": provide the standard IPA transcription without surrounding slashes or brackets.
      #{non_latin ? 'For "translit": use spelling-based romanization (not phonetic), consistent with how the word is spelled, not how it sounds.' : 'For "translit": always null (Latin-script language, no romanization needed).'}
    PROMPT

    response = post_message(system, prompt)
    text = strip_fences(response.dig("content", 0, "text").to_s)
    return [] if text.blank? # model found nothing usable (e.g. a non-speech transcript)
    JSON.parse(text)
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

        phonetics_json = build_phonetics_json(w, target)

        term = @deck.terms.create!(kind: "word", position: (position += 1))
        term.translations.create!(
          language: target, text: t, article: article,
          etymology: w["etymology"].presence, mnemonic: w["mnemonic"].presence,
          phonetics: phonetics_json
        )
        term.translations.create!(language: source, text: s)
      end
    end
  end

  # Build the phonetics JSON string for a word entry.
  # Non-Latin languages get both ipa + translit; Latin-script langs get ipa only.
  def build_phonetics_json(word, target_code)
    ipa = word["ipa"].to_s.strip.presence
    return nil if ipa.nil?

    data = { "ipa" => ipa }
    if Translation::NON_LATIN.include?(target_code)
      translit = word["translit"].to_s.strip.presence
      data["translit"] = translit if translit
    end
    JSON.generate(data)
  end
end
