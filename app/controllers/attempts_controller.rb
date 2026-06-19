class AttemptsController < ApplicationController
  def create
    term = Term.find(params[:term_id])
    term.attempts.create!(
      from_language: params[:from],
      to_language: params[:to],
      correct: ActiveModel::Type::Boolean.new.cast(params[:correct]),
      given: params[:given].to_s.first(255)
    )
    head :no_content
  end
end
