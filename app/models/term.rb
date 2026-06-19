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
end
