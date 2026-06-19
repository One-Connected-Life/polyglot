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

  def set_slug
    self.slug ||= name.to_s.parameterize
  end
end
