class AttemptsController < ApplicationController
  def create
    term = current_user.terms.find(params[:term_id])
    correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
    current_user.attempts.create!(
      term: term,
      from_language: params[:from],
      to_language: params[:to],
      correct: correct,
      given: params[:given].to_s.first(255)
    )

    correct_count = current_user.attempts
                        .where(term_id: term.id, from_language: params[:from], to_language: params[:to], correct: true)
                        .count

    # newly_owned: this correct answer is the one that first reaches 2 corrects.
    render json: { correct_count: correct_count, newly_owned: correct && correct_count == 2 }
  end
end
