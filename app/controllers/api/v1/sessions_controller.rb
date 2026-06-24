module Api
  module V1
    # Token login/logout for native clients. Mirrors the web SessionsController
    # (authenticate_by → start a Session), but returns a bearer token instead of
    # setting a signed cookie.
    class SessionsController < BaseController
      skip_before_action :authenticate_api!, only: :create

      # POST /api/v1/sessions  { email_address, password } → { token, user }
      def create
        user = User.authenticate_by(
          email_address: params[:email_address],
          password:      params[:password]
        )
        if user
          session = Session.start_for_api!(
            user,
            user_agent: request.user_agent,
            ip_address: request.remote_ip
          )
          render json: { token: session.api_token, user: UserSerializer.call(user) }, status: :created
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end

      # DELETE /api/v1/session — revoke the current bearer token.
      def destroy
        Current.session&.destroy
        head :no_content
      end
    end
  end
end
