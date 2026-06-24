# Translate user-entered text in the target language into the source language (+ the
# lore a learner wants: article, etymology, mnemonic, IPA), via the Anthropic Messages
# API. Powers the Translate-first home (issue #10). Returns word hashes shaped exactly
# like DeckGenerator's, so Deck#absorb can capture them unchanged. Only nl→en (the two
# surfaced languages) are produced here; the other languages ride in later via
# EnrichTranslationsJob so they never delay the user.
class Translator
  include AnthropicMessages

  Error = Class.new(StandardError)

  MODEL = "claude-haiku-4-5-20251001" # cheap + capable enough for vocab
  MAX_ITEMS = 40 # safety cap on how many items we'll translate at once

  def initialize(user, text)
    @user = user
    @text = text.to_s.strip
  end

  # Returns an array of word hashes; [] when there's nothing usable to translate.
  def call
    return [] if @text.blank?

    response = post_message(system_prompt, user_prompt, model: MODEL)
    raw = strip_fences(message_text(response))
    return [] if raw.blank?

    words = JSON.parse(raw)
    return [] unless words.is_a?(Array)
    words.first(MAX_ITEMS)
  rescue JSON::ParserError => e
    raise Error, "could not parse model output: #{e.message}"
  end

  private

  def system_prompt
    "You translate vocabulary for language learners. Output ONLY a valid JSON array, no prose, no markdown fences."
  end

  def user_prompt
    target = @user.target_language_name
    source = @user.source_language_name
    target_code = @user.target_language
    non_latin = Translation::NON_LATIN.include?(target_code)

    ipa_field = '"ipa": "<IPA pronunciation of the target word, e.g. /xlʲep/ written without slashes>"'
    translit_field = non_latin ?
      '"translit": "<spelling-based romanization of the target word (e.g. Russian хлеб → khleb)>"' :
      '"translit": null'

    <<~PROMPT
      The user is learning #{target} (their base language is #{source}). They entered the
      #{target} text below and want it translated so they can add it to their vocabulary.

      If the text is a single word or one short phrase, return exactly ONE item — that
      word or phrase. If it's longer (a sentence, a list, or a paragraph), extract the
      distinct useful vocabulary items (words and short phrases) a learner would want —
      skip filler, names, and trivial function words. Up to #{MAX_ITEMS} items.

      Translate each item from #{target} into #{source}.

      TEXT:
      \"\"\"
      #{@text}
      \"\"\"

      Return a JSON array. Each element is an object:
        {
          "target": "<the word/phrase in #{target}>",
          "source": "<its #{source} translation>",
          "article": "<the definite article in #{target} if this is a noun that takes one, otherwise null>",
          "etymology": "<short factual origin of the #{target} word>",
          "mnemonic": "<a one-line memory hook in #{source}>",
          #{ipa_field},
          #{translit_field}
        }

      Rules: real and natural translations, no duplicates.
      Set "article" correctly for #{target} (e.g. Dutch de/het, French le/la); use null when the word takes none.
      Do NOT include the article inside the "target" value — the bare word goes in "target", the article only in "article".
      "etymology": factual origin in ≤12 words. For a compound, break it into its parts and their literal meanings (e.g. "ziek (sick) + huis (house)"). Plain text, no "From..." preamble. Use null if you don't actually know.
      "mnemonic": one short memory hook in #{source} (≤12 words). Use null if nothing genuinely helpful comes to mind.
      For "ipa": standard IPA transcription without surrounding slashes or brackets.
      #{non_latin ? 'For "translit": spelling-based romanization, consistent with spelling not sound.' : 'For "translit": always null (Latin-script language).'}
    PROMPT
  end
end
