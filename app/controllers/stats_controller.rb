class StatsController < ApplicationController
  def index
    @target = current_user.target_language
    @source = current_user.source_language
    @words = current_user.terms.where(kind: "word").includes(:translations).to_a

    # [term_id, from, to] => { correct:, wrong:, latest_correct: }
    @summary = Hash.new { |h, k| h[k] = { correct: 0, wrong: 0, latest_correct: nil } }
    current_user.attempts.order(:id).find_each do |a|
      s = @summary[[a.term_id, a.from_language, a.to_language]]
      a.correct ? s[:correct] += 1 : s[:wrong] += 1
      s[:latest_correct] = a.correct
    end

    @resting = current_user.attempts.resting_term_ids(from: @target, to: @source).to_set

    # Most-drilled first (by target->source activity), then alphabetical by source word.
    @words.sort_by! do |t|
      s = @summary[[t.id, @target, @source]]
      [-(s[:correct] + s[:wrong]), t.translation(@source)&.text.to_s]
    end

    @totals = {
      attempts: current_user.attempts.count,
      correct: current_user.attempts.where(correct: true).count,
      owned: @words.count { |t| @summary[[t.id, @target, @source]][:correct] >= 2 },
    }
  end

  helper_method :word_status
  def word_status(term)
    s = @summary[[term.id, @target, @source]]
    return "new" if s[:correct] + s[:wrong] == 0
    return "owned · resting" if @resting.include?(term.id)
    return "owned · due" if s[:correct] >= 2
    return "missed" if s[:latest_correct] == false
    "learning #{s[:correct]}/2"
  end
end
