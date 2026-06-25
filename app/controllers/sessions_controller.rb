class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create omniauth omniauth_failure ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  # OAuth callback (Google / Facebook). The OmniAuth middleware has already
  # validated the provider handshake and populated request.env["omniauth.auth"].
  # We find-or-create the user, then establish the session the exact same way
  # email/password login does (start_new_session_for → signed httponly cookie).
  def omniauth
    auth = request.env["omniauth.auth"]
    user = auth && User.from_omniauth(auth)

    if user&.persisted?
      # iOS handoff (App A): the flow ran in ASWebAuthenticationSession (Safari),
      # so this Safari-side session cookie is useless to the WKWebView. Instead
      # mint a one-time token and bounce out to the custom URL scheme; the shell
      # redeems it at /ios/session_handoff to set the real WKWebView cookie.
      # See IosOauthController for the full handoff dance.
      if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
        handoff = OauthHandoff.issue!(user)
        return redirect_to "#{scheme}://auth-complete?handoff=#{handoff.token}",
          allow_other_host: true
      end

      start_new_session_for user
      redirect_to after_authentication_url
    elsif user && !user.persisted?
      # Most likely an email/password account already owns this email — see the
      # collision policy in User.from_omniauth. Steer them to password sign-in.
      redirect_to new_session_path,
        alert: "That email already has a password account here. Sign in with your password instead."
    else
      redirect_to new_session_path, alert: "We couldn't sign you in. Please try again."
    end
  end

  # OmniAuth failure handler (user denied access, CSRF/state mismatch, provider error).
  def omniauth_failure
    # In an iOS handoff, ASWebAuth is waiting for the custom URL scheme — bounce
    # back to it (no token) so the session closes cleanly rather than dead-ending
    # on an HTML page inside Safari. The shell treats a tokenless callback as a
    # silent abort.
    if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
      return redirect_to "#{scheme}://auth-complete", allow_other_host: true
    end

    redirect_to new_session_path,
      alert: "Social sign-in didn't complete (#{params[:message].presence || 'cancelled'}). Try again."
  end
end
