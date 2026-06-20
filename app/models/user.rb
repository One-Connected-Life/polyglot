class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :terms, through: :decks
  has_many :attempts, dependent: :destroy
  has_many :schedulings, dependent: :destroy  # FSRS cache rows (#axis-4)

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # learning_languages stored as JSON array: ["nl", "es", "fr"]
  serialize :learning_languages, coder: JSON

  validates :target_language, inclusion: { in: Translation::LANGUAGES.keys }, allow_nil: true
  validates :source_language, inclusion: { in: Translation::LANGUAGES.keys }
  validates :drill_direction, inclusion: { in: %w[forward random] }
  validate :target_differs_from_source
  validate :learning_languages_are_valid

  # Cost guard: cap AI deck generations per user (Mihai's API key pays for all).
  GENERATION_CAP = 25

  # Onboarded once they've chosen what they're learning.
  def onboarded?
    target_language.present?
  end

  def can_generate?
    generations_count < GENERATION_CAP
  end

  def generations_left
    [GENERATION_CAP - generations_count, 0].max
  end

  # The two languages this user drills between (target first).
  # Used for legacy single-target drill; still needed by Attempt#miss_counts etc.
  def drillable_languages
    [target_language, source_language].compact
  end

  # The full list of languages this user is actively learning (multi-language drill).
  # Falls back to [target_language] if learning_languages is not yet set.
  def active_learning_languages
    list = Array(learning_languages).select { |l| Translation::LANGUAGES.key?(l) }
    list.presence || [ target_language ].compact
  end

  # Whether multi-language drill mode is available (user has 2+ target languages).
  def multi_language_drill?
    active_learning_languages.size >= 2
  end

  def target_language_name
    Translation::LANGUAGES[target_language]
  end

  def source_language_name
    Translation::LANGUAGES[source_language]
  end

  private

  def target_differs_from_source
    return if target_language.blank?
    errors.add(:target_language, "must differ from the language you already know") if target_language == source_language
  end

  def learning_languages_are_valid
    return if learning_languages.blank?
    invalid = Array(learning_languages) - Translation::LANGUAGES.keys
    errors.add(:learning_languages, "includes unknown languages: #{invalid.join(', ')}") if invalid.any?
    if Array(learning_languages).include?(source_language)
      errors.add(:learning_languages, "cannot include the language you already speak")
    end
  end
end
