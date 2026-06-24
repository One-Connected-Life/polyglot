module Api
  module V1
    # Sign-up for native clients. Mirrors the web RegistrationsController (create
    # a User, start a session), returning a bearer token + user. The client then
    # PATCHes /api/v1/onboarding to pick languages (web redirects to onboarding).
    class RegistrationsController < BaseController
      skip_before_action :authenticate_api!, only: :create

      # POST /api/v1/registrations { name, email_address, password, password_confirmation }
      def create
        user = User.new(registration_params)
        if user.save
          session = Session.start_for_api!(
            user,
            user_agent: request.user_agent,
            ip_address: request.remote_ip
          )
          render json: { token: session.api_token, user: UserSerializer.call(user) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def registration_params
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
