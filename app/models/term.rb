class Term < ApplicationRecord
  belongs_to :deck
  has_many :translations, dependent: :destroy
  has_many :attempts, dependent: :destroy
  has_many :schedulings, dependent: :destroy  # FSRS cache rows (#axis-4)

  accepts_nested_attributes_for :translations

  # Only terms from saved, drillable decks — excludes decks still transcribing or
  # awaiting review (issue #3), so un-reviewed audio words never enter practice/stats.
  # Also excludes individually-unreviewed words: a fresh cohort appended to an already
  # "ready" deck (reviewed: false) waits here until the user accepts it.
  scope :drillable, -> { joins(:deck).where(decks: { status: "ready" }).where(reviewed: true) }

  # Translation in a given language (string or symbol code), or nil.
  def translation(language)
    translations.detect { |t| t.language == language.to_s }
  end

  # Human-readable label for admin/debug — falls back to any translation.
  def label
    (translation("en") || translations.first)&.text
  end

  # How far the target word is from the source word, as a difficulty bucket.
  # Cognates (sorry/sorry, dokter/doctor) come out :easy and can be filtered.
  def difficulty(lang_a, lang_b)
    a_text = translation(lang_a)&.text
    b_text = translation(lang_b)&.text
    return :unknown unless a_text && b_text

    a = self.class.normalize_for_distance(a_text)
    b = self.class.normalize_for_distance(b_text)
    return :hard if a.empty? || b.empty?

    distance = self.class.levenshtein(a, b).to_f / [a.length, b.length].max
    return :easy   if distance <= 0.34
    return :medium if distance <= 0.6
    :hard
  end

  def self.normalize_for_distance(string)
    string.to_s.downcase.unicode_normalize(:nfd).gsub(/[^a-z]/, "")
  end

  def self.levenshtein(a, b)
    return b.length if a.empty?
    return a.length if b.empty?

    prev = (0..b.length).to_a
    a.each_char.with_index do |ca, i|
      curr = [i + 1]
      b.each_char.with_index do |cb, j|
        cost = ca == cb ? 0 : 1
        curr << [prev[j + 1] + 1, curr[j] + 1, prev[j] + cost].min
      end
      prev = curr
    end
    prev[b.length]
  end
end
