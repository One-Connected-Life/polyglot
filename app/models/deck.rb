class Deck < ApplicationRecord
  belongs_to :user
  has_many :terms, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  before_validation :set_slug, on: :create

  def to_param
    slug
  end

  private

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
