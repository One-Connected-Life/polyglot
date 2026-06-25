class OnboardingController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user
    attrs = onboarding_params

    # Normalize the learning_languages multi-select: params sends an array;
    # filter out blank values (hidden sentinel) and the user's source language.
    if attrs.key?(:learning_languages)
      langs = Array(attrs[:learning_languages]).reject(&:blank?)
      attrs = attrs.merge(learning_languages: langs)
      # Keep target_language in sync with the first chosen learning language.
      attrs = attrs.merge(target_language: langs.first) if langs.any? && attrs[:target_language].blank?
    end

    if @user.update(attrs)
      redirect_to root_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def onboarding_params
    params.require(:user).permit(
      :name, :target_language, :source_language, :drill_direction,
      # Drill options (Finding A): persisted per-user, edited here in Settings.
      :drill_order, :skip_easy, :hide_mastered, :autoplay_prompt, :autoplay_wrong,
      :drill_recall_first,
      learning_languages: [],
    )
  end
end
