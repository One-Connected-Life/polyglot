module Api
  module V1
    # Single source of truth for the `user` JSON shape returned across the API
    # (login, registration, /me). Includes onboarding state + language config so
    # the native client can route to onboarding or the drill home.
    module UserSerializer
      module_function

      def call(user)
        {
          id:                 user.id,
          name:               user.name,
          email_address:      user.email_address,
          onboarded:          user.onboarded?,
          source_language:    user.source_language,
          target_language:    user.target_language,
          learning_languages: user.active_learning_languages,
          drill_direction:    user.drill_direction,
          drill_order:        user.drill_order,
          drill_recall_first: user.drill_recall_first?,
          skip_easy:          user.skip_easy?,
          hide_mastered:      user.hide_mastered?,
          autoplay_prompt:    user.autoplay_prompt?,
          autoplay_wrong:     user.autoplay_wrong?,
          multi_language:     user.multi_language_drill?,
          generations_left:   user.generations_left,
        }
      end
    end
  end
end
