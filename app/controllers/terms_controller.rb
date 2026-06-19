class TermsController < ApplicationController
  def show
    @term = Term.includes(:translations).find(params[:id])
  end
end
