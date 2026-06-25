module Api
  module V1
    # PATCH /api/v1/onboarding — mirrors the web OnboardingController#update:
    # normalizes learning_languages (drops blanks/sentinels) and keeps
    # target_language in sync with the first chosen learning language.
    class OnboardingController < BaseController
      def update
        user  = current_user
        attrs = onboarding_params

        if attrs.key?(:learning_languages)
          langs = Array(attrs[:learning_languages]).reject(&:blank?)
          attrs = attrs.merge(learning_languages: langs)
          attrs = attrs.merge(target_language: langs.first) if langs.any? && attrs[:target_language].blank?
        end

        if user.update(attrs)
          render json: { user: UserSerializer.call(user) }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def onboarding_params
        params.require(:user).permit(
          :name, :target_language, :source_language, :drill_direction,
          :drill_order, :skip_easy, :hide_mastered, :autoplay_prompt, :autoplay_wrong,
          :drill_recall_first,
          learning_languages: []
        )
      end
    end
  end
end
