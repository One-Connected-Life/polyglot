# Backfill the non-surfaced languages onto freshly-captured words (issue #10).
# Translate captures store only the target word + English immediately (so the user
# isn't kept waiting); this job adds the remaining languages (es/fr/it/ro/ru) + their
# IPA in the background. This is dormant data today — only nl/en are drillable — but it
# means every captured word is ready the day we surface another language.
#
# Best-effort: a failure here never affects the user's captured words, so we log and
# move on rather than retry aggressively.
class EnrichTranslationsJob < ApplicationJob
  include AnthropicMessages

  Error = Class.new(StandardError)

  MODEL = "claude-haiku-4-5-20251001"
  queue_as :default

  def perform(term_ids)
    terms = Term.where(id: term_ids).includes(:translations, deck: :user).to_a
    return if terms.empty?

    user = terms.first.deck.user
    target = user.target_language

    # Build one prompt for the whole batch: each word → its missing languages.
    jobs = terms.filter_map do |term|
      tr = term.translation(target)
      word = tr&.text
      next if word.blank?
      missing = Translation::LANGUAGES.keys - term.translations.map(&:language)
      next if missing.empty?
      { term: term, word: tr.with_article, bare: word, missing: missing }
    end
    return if jobs.empty?

    by_word = fetch_translations(jobs, target)
    return if by_word.blank?

    apply(jobs, by_word)
  rescue StandardError => e
    Rails.logger.error("[EnrichTranslationsJob] #{e.class}: #{e.message}")
    # swallow — enrichment is best-effort dormant data
  end

  private

  def fetch_translations(jobs, target_code)
    target = Translation::LANGUAGES[target_code]
    lines = jobs.map { |j| "- #{j[:bare]} → #{j[:missing].map { |l| Translation::LANGUAGES[l] }.join(', ')}" }.join("\n")
    langs_legend = Translation::LANGUAGES.map { |code, name| "#{code} = #{name}" }.join(", ")
    non_latin = Translation::NON_LATIN.join(", ")

    system = "You translate single vocabulary words between languages. Output ONLY a valid JSON array, no prose, no fences."
    prompt = <<~PROMPT
      Each line below is a #{target} word followed by the languages to translate it into.
      Language codes: #{langs_legend}. Non-Latin-script languages (#{non_latin}) also need a
      spelling-based romanization ("translit").

      WORDS:
      #{lines}

      Return a JSON array, one object per #{target} word, in the same order:
        {
          "word": "<the #{target} word, exactly as given>",
          "translations": {
            "<lang code>": { "text": "<translation>", "ipa": "<IPA without slashes>", "translit": "<romanization or null>" }
          }
        }
      Include only the requested language codes for each word. Keep "translit" null unless the language is non-Latin-script.
    PROMPT

    response = post_message(system, prompt, model: MODEL)
    raw = strip_fences(message_text(response))
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    return {} unless parsed.is_a?(Array)
    parsed.index_by { |h| h["word"].to_s.strip.downcase }
  rescue JSON::ParserError => e
    raise Error, "could not parse enrichment output: #{e.message}"
  end

  def apply(jobs, by_word)
    Term.transaction do
      jobs.each do |j|
        entry = by_word[j[:bare].to_s.strip.downcase] || by_word[j[:word].to_s.strip.downcase]
        translations = entry && entry["translations"]
        next if translations.blank?

        existing = j[:term].translations.map(&:language).to_set
        j[:missing].each do |lang|
          data = translations[lang]
          text = data && data["text"].to_s.strip.presence
          next if text.blank? || existing.include?(lang)

          j[:term].translations.create!(
            language: lang, text: text,
            phonetics: phonetics_for(lang, data)
          )
          existing << lang
        end
      end
    end
  end

  def phonetics_for(lang, data)
    ipa = data["ipa"].to_s.strip.presence
    return nil if ipa.nil?

    out = { "ipa" => ipa }
    if Translation::NON_LATIN.include?(lang)
      translit = data["translit"].to_s.strip.presence
      out["translit"] = translit if translit
    end
    JSON.generate(out)
  end
end
