module Api
  module V1
    # GET /api/v1/me — current user + onboarding state + language config.
    class MeController < BaseController
      def show
        render json: { user: UserSerializer.call(current_user) }
      end
    end
  end
end
