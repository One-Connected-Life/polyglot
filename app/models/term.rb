class Term < ApplicationRecord
  belongs_to :deck
  has_many :translations, dependent: :destroy
  has_many :attempts, dependent: :destroy

  accepts_nested_attributes_for :translations

  # Translation in a given language (string or symbol code), or nil.
  def translation(language)
    translations.detect { |t| t.language == language.to_s }
  end

  # Human-readable label for admin/debug — falls back to any translation.
  def label
    (translation("en") || translations.first)&.text
  end

  # How far the Dutch is from the English, as a learning-difficulty bucket.
  # Cognates (sorry/sorry, dokter/doctor) come out :easy and can be filtered.
  def difficulty
    nl = translation("nl")&.text
    en = translation("en")&.text
    return :unknown unless nl && en

    a = self.class.normalize_for_distance(nl)
    b = self.class.normalize_for_distance(en)
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
