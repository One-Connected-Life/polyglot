class AttemptsController < ApplicationController
  def create
    term = Term.find(params[:term_id])
    correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
    term.attempts.create!(
      from_language: params[:from],
      to_language: params[:to],
      correct: correct,
      given: params[:given].to_s.first(255)
    )

    correct_count = term.attempts
                        .where(from_language: params[:from], to_language: params[:to], correct: true)
                        .count

    # newly_owned: this correct answer is the one that first reaches 2 corrects.
    render json: { correct_count: correct_count, newly_owned: correct && correct_count == 2 }
  end
end
