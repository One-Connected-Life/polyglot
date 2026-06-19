class OnboardingController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(onboarding_params)
      redirect_to root_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def onboarding_params
    params.require(:user).permit(:name, :target_language, :source_language)
  end
end
