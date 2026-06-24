class User < ApplicationRecord
  # OAuth users (Google/Facebook) have no password, so we opt out of the built-in
  # presence/confirmation validations and enforce password presence ourselves only
  # for non-OAuth accounts. `authenticate_by` / `authenticate` still work for
  # password users, and OAuth users simply have a nil digest they never authenticate
  # against. (oauth-providers)
  has_secure_password validations: false
  validates :password, length: { minimum: 6 }, allow_nil: true
  validates :password, presence: true, on: :create, unless: :oauth_user?
  validate :password_confirmation_matches

  has_many :sessions, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :terms, through: :decks
  has_many :attempts, dependent: :destroy
  has_many :schedulings, dependent: :destroy  # FSRS cache rows (#axis-4)

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Mirror the DB unique index as a model validation so a colliding email (e.g. an
  # OAuth login matching an existing password account) fails gracefully instead of
  # raising a SQLite constraint exception. See `from_omniauth` collision policy.
  validates :email_address, presence: true, uniqueness: { case_sensitive: false }

  # learning_languages stored as JSON array: ["nl", "es", "fr"]
  serialize :learning_languages, coder: JSON

  validates :target_language, inclusion: { in: Translation::LANGUAGES.keys }, allow_nil: true
  validates :source_language, inclusion: { in: Translation::LANGUAGES.keys }
  validates :drill_direction, inclusion: { in: %w[forward random] }
  validates :drill_order, inclusion: { in: %w[smart shuffle] }
  validate :target_differs_from_source
  validate :learning_languages_are_valid

  # Cost guard: cap AI deck generations per user (Mihai's API key pays for all).
  GENERATION_CAP = 25

  # The single rolling deck that Translate captures melt into (issue #10).
  MY_WORDS_SLUG = "my-words"

  # Find-or-create the user's "My Words" deck — always drillable (status "ready"),
  # not topic-based (no auto-expand), captured words append into it.
  def my_words_deck
    decks.find_or_create_by!(slug: MY_WORDS_SLUG) do |d|
      d.name     = "My Words"
      d.status   = "ready"
      d.position = (decks.maximum(:position) || -1) + 1
    end
  end

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

  # Is this account backed by an external identity provider (Google/Facebook)?
  def oauth_user?
    provider.present? && uid.present?
  end

  # Find-or-create a user from an OmniAuth auth hash.
  #
  # Identity is keyed on [provider, uid] (the provider's stable id), never email.
  # Email-collision policy:
  #   - [provider, uid] already exists                  → sign that user in.
  #   - email matches an existing account AND the provider VERIFIED the email
  #     (Google does) → LINK the identity onto that account and sign in. A verified
  #     email means the provider proved the person controls the address, so linking
  #     is safe — and it spares the legit owner the "use your password" dead-end.
  #   - email matches but is NOT verified (unverified provider) → refuse to link
  #     (the classic OAuth account-takeover vector); return an unsaved User so the
  #     caller steers them to password sign-in.
  #   - no email match                                  → create a new OAuth user.
  def self.from_omniauth(auth)
    provider = auth.provider.to_s
    uid      = auth.uid.to_s
    info     = auth.info || {}
    email    = (info["email"] || info[:email]).to_s.strip.downcase

    user = find_by(provider: provider, uid: uid)
    return user if user

    if email.present? && (existing = find_by(email_address: email))
      # Unverified provider email → don't link; unsaved User triggers the
      # "sign in with your password instead" path in the caller.
      return new(email_address: email) unless provider_email_verified?(auth)

      existing.update(
        provider:   provider,
        uid:        uid,
        name:       existing.name.presence       || info["name"]  || info[:name],
        avatar_url: existing.avatar_url.presence || info["image"] || info[:image]
      )
      return existing
    end

    create do |u|
      u.provider      = provider
      u.uid           = uid
      u.email_address = email
      u.name          = info["name"]  || info[:name]
      u.avatar_url    = info["image"] || info[:image]
    end
  end

  # A provider "verifies" an email when it proves the person controls it. Google
  # always verifies the account email, so we trust google_oauth2 outright; other
  # providers must send an explicit truthy email_verified flag.
  def self.provider_email_verified?(auth)
    return true if auth.provider.to_s == "google_oauth2"
    flag = auth.info && auth.info["email_verified"]
    flag = auth.dig("extra", "raw_info", "email_verified") if flag.nil?
    ActiveModel::Type::Boolean.new.cast(flag)
  end

  private

  def password_confirmation_matches
    return if password_confirmation.nil?
    errors.add(:password_confirmation, "doesn't match Password") if password != password_confirmation
  end

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
