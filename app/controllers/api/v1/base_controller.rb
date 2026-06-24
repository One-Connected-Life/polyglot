module Api
  module V1
    # Base for all /api/v1 controllers. Authenticates native clients by bearer
    # token (Authorization: Bearer <session.api_token>) and sets Current.session
    # so `current_user` works exactly like the web side. No cookies, no CSRF.
    class BaseController < ActionController::API
      before_action :authenticate_api!

      # 404 on a missing/foreign record → consistent JSON, not an HTML error page.
      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end

      private

      def authenticate_api!
        token = bearer_token
        session = Session.find_by(api_token: token) if token.present?
        if session
          Current.session = session
        else
          render json: { error: "unauthorized" }, status: :unauthorized
        end
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        header[/\ABearer (.+)\z/, 1]
      end

      def current_user
        Current.user
      end

      # FSRS feature flag — same gate the web controllers use, so the API mirrors
      # whichever path (FSRS / legacy) prod is running.
      def fsrs_enabled?
        ENV["FSRS_ENABLED"].to_s == "1"
      end
    end
  end
end
