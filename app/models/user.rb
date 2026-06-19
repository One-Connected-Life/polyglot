class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :terms, through: :decks
  has_many :attempts, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :target_language, inclusion: { in: Translation::LANGUAGES.keys }, allow_nil: true
  validates :source_language, inclusion: { in: Translation::LANGUAGES.keys }
  validate :target_differs_from_source

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
  def drillable_languages
    [target_language, source_language].compact
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
end
