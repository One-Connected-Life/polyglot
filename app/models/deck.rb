class Deck < ApplicationRecord
  belongs_to :user
  has_many :terms, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  before_validation :set_slug, on: :create

  def to_param
    slug
  end

  # Words awaiting the user's review. For a brand-new deck (status "review") that's
  # every word; for an already-drillable deck it's just a freshly-appended cohort
  # (reviewed: false). Either way these are what the review screen shows.
  def pending_review_terms
    status == "review" ? terms : terms.where(reviewed: false)
  end

  # In-memory variant for the home page, which has terms preloaded — avoids N+1.
  def pending_review_count
    status == "review" ? terms.size : terms.count { |t| !t.reviewed }
  end

  def needs_review?
    pending_review_count.positive?
  end

  # Absorb a batch of model-produced word hashes into this deck (issue #10). Creates
  # one Term per word with its target + source Translation rows, continuing positions,
  # skipping words already on the deck and dupes within the batch. Shared by every
  # import path — topic/audio generation (DeckGenerator) and the Translate capture flow.
  # Returns the Terms it created (skipped dupes excluded).
  #
  # word hash: { "target","source","article","etymology","mnemonic","ipa","translit" }
  # reviewed: true → drillable immediately; false → waits in the review screen.
  def absorb(words, reviewed: true)
    target = user.target_language
    source = user.source_language
    seen = existing_target_words.map(&:downcase).to_set
    position = terms.maximum(:position) || 0
    created = []

    Term.transaction do
      words.each do |w|
        article = w["article"].presence
        t = strip_redundant_article(w["target"].to_s.strip, article)
        s = w["source"].to_s.strip
        next if t.blank? || s.blank?

        key = t.downcase
        next if seen.include?(key)
        seen << key

        term = terms.create!(kind: "word", position: (position += 1), reviewed: reviewed)
        term.translations.create!(
          language: target, text: t, article: article,
          etymology: w["etymology"].presence, mnemonic: w["mnemonic"].presence,
          phonetics: phonetics_json(w, target)
        )
        term.translations.create!(language: source, text: s)
        created << term
      end
    end

    created
  end

  # Target-language words already on this deck (for dedupe + telling the generator
  # what not to repeat on append).
  def existing_target_words
    target = user.target_language
    terms.flat_map(&:translations)
         .select { |tr| tr.language == target }
         .filter_map { |tr| tr.text.presence }
  end

  private

  # Models often repeat the article inside the word ("la cuisine" + article "la").
  # Strip it so with_article doesn't double it ("la la cuisine").
  def strip_redundant_article(text, article)
    return text if article.blank?

    art = article.to_s.strip
    pattern = art.end_with?("'") ? /\A#{Regexp.escape(art)}\s*/i : /\A#{Regexp.escape(art)}\s+/i
    text.sub(pattern, "")
  end

  # Build the phonetics JSON string for a word entry. Non-Latin target languages get
  # both ipa + translit; Latin-script langs get ipa only. nil when no IPA was given.
  def phonetics_json(word, target_code)
    ipa = word["ipa"].to_s.strip.presence
    return nil if ipa.nil?

    data = { "ipa" => ipa }
    if Translation::NON_LATIN.include?(target_code)
      translit = word["translit"].to_s.strip.presence
      data["translit"] = translit if translit
    end
    JSON.generate(data)
  end

  # Slug is unique per user. Labels/topics/filenames repeat, so suffix on collision
  # (-2, -3, …) instead of letting the uniqueness validation fail. Centralised here so
  # every import path (topic, audio, text) gets dedupe for free.
  def set_slug
    return if slug.present?

    base = name.to_s.parameterize
    candidate = base
    n = 1
    while user && user.decks.where.not(id: id).exists?(slug: candidate)
      n += 1
      candidate = "#{base}-#{n}"
    end
    self.slug = candidate
  end
end
