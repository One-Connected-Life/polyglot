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

  REST_DAYS_AFTER_2 = 7   # learned twice -> rest a week
  REST_DAYS_AFTER_3 = 14  # learned 3+ times -> rest a fortnight

  # Terms to rest (skip) right now in this direction: latest attempt correct,
  # >= 2 correct total, and still inside the cooldown window measured from the
  # last correct answer. After the window they resurface for review (spaced rep).
  def self.resting_term_ids(from:, to:, now: Time.current)
    scope = where(from_language: from, to_language: to)
    latest = where(id: scope.group(:term_id).maximum(:id).values).index_by(&:term_id)
    return [] if latest.empty?

    correct_counts = scope.where(correct: true).group(:term_id).count

    latest.filter_map do |term_id, attempt|
      next unless attempt.correct
      count = correct_counts[term_id].to_i
      next if count < 2

      window = (count >= 3 ? REST_DAYS_AFTER_3 : REST_DAYS_AFTER_2).days
      term_id if attempt.created_at > now - window
    end
  end

  # { ["nl","en"] => count, ... } for surfaced directions that have any misses.
  def self.miss_counts
    Translation::SURFACED.permutation(2).each_with_object({}) do |(from, to), acc|
      count = missed_term_ids(from: from, to: to).size
      acc[[from, to]] = count if count.positive?
    end
  end
end
