class TermsController < ApplicationController
  def show
    @term = current_user.terms.includes(:translations).find(params[:id])
  end
end
