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
  # Email-collision policy (documented, deliberately conservative):
  #   We key the OAuth identity on [provider, uid] — the provider's stable user id,
  #   never the email. If a [provider, uid] row exists we sign that user in.
  #   Otherwise we create a NEW OAuth user. We do NOT auto-link an OAuth login to a
  #   pre-existing email/password account that happens to share the same email,
  #   because the email coming back from the provider is attacker-influenceable for
  #   some providers and silent account-takeover is the classic OAuth pitfall.
  #   So if someone signed up with email+password and later "Continue with Google"
  #   using the same address, account creation fails on the unique email index and
  #   `from_omniauth` returns an unsaved, invalid User — the caller surfaces a
  #   "sign in with your password instead" message. Explicit account-linking (while
  #   already signed in) is a deliberate future feature, not an implicit side effect.
  def self.from_omniauth(auth)
    provider = auth.provider.to_s
    uid      = auth.uid.to_s
    info     = auth.info || {}

    user = find_by(provider: provider, uid: uid)
    return user if user

    create do |u|
      u.provider      = provider
      u.uid           = uid
      u.email_address = info["email"] || info[:email]
      u.name          = info["name"]  || info[:name]
      u.avatar_url    = info["image"] || info[:image]
    end
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
