class Attempt < ApplicationRecord
  belongs_to :term

  validates :from_language, :to_language, presence: true

  # Term ids whose MOST RECENT attempt in this direction was wrong.
  # Get one right and it leaves your misses; miss it again and it returns.
  def self.missed_term_ids(from:, to:)
    scope = where(from_language: from, to_language: to)
    latest_ids = scope.group(:term_id).maximum(:id).values
    where(id: latest_ids, correct: false).pluck(:term_id)
  end

  # { ["nl","en"] => count, ... } for surfaced directions that have any misses.
  def self.miss_counts
    Translation::SURFACED.permutation(2).each_with_object({}) do |(from, to), acc|
      count = missed_term_ids(from: from, to: to).size
      acc[[from, to]] = count if count.positive?
    end
  end
end
