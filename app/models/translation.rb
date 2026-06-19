class Translation < ApplicationRecord
  # ISO 639-1 code => display name. Adding a language is a data change, not a migration.
  LANGUAGES = {
    "en" => "English",
    "nl" => "Dutch",
    "es" => "Spanish",
    "fr" => "French",
    "it" => "Italian",
    "ro" => "Romanian",
    "ru" => "Russian",
  }.freeze

  # Languages currently drillable in the UI. The rest ride along as dormant data
  # until we verify them and switch them on.
  SURFACED = %w[nl en].freeze

  belongs_to :term

  validates :language, presence: true, inclusion: { in: LANGUAGES.keys }
  validates :text, presence: true
  validates :language, uniqueness: { scope: :term_id }

  def language_name
    LANGUAGES[language]
  end

  # Extra acceptable answers beyond the primary text (pipe-separated).
  def alternate_list
    alternates.to_s.split("|").map(&:strip).reject(&:blank?)
  end

  # Everything that should be graded correct when this translation is the answer.
  def accepted_answers
    [text, *alternate_list]
  end

  # "het brood" when an article is set, otherwise just the word.
  def with_article
    article.present? ? "#{article} #{text}" : text
  end
end
