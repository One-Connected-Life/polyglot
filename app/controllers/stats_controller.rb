class StatsController < ApplicationController
  def index
    @target = current_user.target_language
    @source = current_user.source_language
    @words  = current_user.terms.drillable.where(kind: "word").includes(:translations).to_a

    # [term_id, from, to] => { correct:, wrong:, latest_correct: }
    @summary = Hash.new { |h, k| h[k] = { correct: 0, wrong: 0, latest_correct: nil } }
    current_user.attempts.order(:id).find_each do |a|
      s = @summary[[a.term_id, a.from_language, a.to_language]]
      a.correct ? s[:correct] += 1 : s[:wrong] += 1
      s[:latest_correct] = a.correct
    end

    @resting = current_user.attempts.resting_term_ids(from: @target, to: @source).to_set

    # FSRS-specific collections (only populated when flag is on).
    if fsrs_enabled?
      retired_ids = current_user.schedulings.retired
                                .where(from_language: @target, to_language: @source)
                                .pluck(:term_id)
                                .to_set

      approaching_ids = current_user.schedulings.approaching_retirement
                                    .where(from_language: @target, to_language: @source)
                                    .pluck(:term_id)
                                    .to_set

      # Retired scheduling rows carry the stability value needed for display.
      @retired_schedulings   = current_user.schedulings.retired
                                           .where(from_language: @target, to_language: @source)
                                           .index_by(&:term_id)
      @approaching_schedulings = current_user.schedulings.approaching_retirement
                                             .where(from_language: @target, to_language: @source)
                                             .index_by(&:term_id)

      @retired_words     = @words.select { |t| retired_ids.include?(t.id) }
      @approaching_words = @words.select { |t| approaching_ids.include?(t.id) }
      @fsrs_enabled      = true
    else
      @retired_words        = []
      @approaching_words    = []
      @retired_schedulings  = {}
      @approaching_schedulings = {}
      @fsrs_enabled         = false
    end

    # Retired words live on the shelf — exclude from the main active table.
    retired_id_set = @retired_words.map(&:id).to_set
    @active_words  = @words.reject { |t| retired_id_set.include?(t.id) }

    # Most-drilled first (by target->source activity), then alphabetical.
    @active_words.sort_by! do |t|
      s = @summary[[t.id, @target, @source]]
      [-(s[:correct] + s[:wrong]), t.translation(@source)&.text.to_s]
    end

    @totals = {
      attempts: current_user.attempts.count,
      correct:  current_user.attempts.where(correct: true).count,
      owned:    @active_words.count { |t| @summary[[t.id, @target, @source]][:correct] >= 2 },
      retired:  @retired_words.size,
    }
  end

  helper_method :word_status
  def word_status(term)
    # Retired words are shown on the shelf, not in the active table.
    s = @summary[[term.id, @target, @source]]
    return "new"             if s[:correct] + s[:wrong] == 0
    return "owned · resting" if @resting.include?(term.id)
    return "owned · due"     if s[:correct] >= 2
    return "missed"          if s[:latest_correct] == false
    "learning #{s[:correct]}/2"
  end

  private

  def fsrs_enabled?
    ENV["FSRS_ENABLED"].to_s == "1"
  end
end
