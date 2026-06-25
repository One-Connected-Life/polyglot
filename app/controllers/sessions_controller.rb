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

    handoff_flag = session[:ios_oauth_handoff].present?
    Rails.logger.info(
      "[iOS-OAuth] #omniauth reached handoff_flag=#{handoff_flag} " \
      "auth_present=#{!auth.nil?} user_persisted=#{user&.persisted? || false}"
    )

    if user&.persisted?
      # iOS handoff (App A): the flow ran in ASWebAuthenticationSession (Safari),
      # so this Safari-side session cookie is useless to the WKWebView. Instead
      # mint a one-time token and bounce out to the custom URL scheme; the shell
      # redeems it at /ios/session_handoff to set the real WKWebView cookie.
      # See IosOauthController for the full handoff dance.
      if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
        handoff = OauthHandoff.issue!(user)
        Rails.logger.info(
          "[iOS-OAuth] #omniauth handoff_token_issued=true scheme=#{scheme} " \
          "redirect_target=#{scheme}://auth-complete?handoff=[redacted]"
        )
        return redirect_to "#{scheme}://auth-complete?handoff=#{handoff.token}",
          allow_other_host: true
      end

      start_new_session_for user
      redirect_to after_authentication_url
    elsif user && !user.persisted?
      # Most likely an email/password account already owns this email — see the
      # collision policy in User.from_omniauth. Steer them to password sign-in.
      if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
        Rails.logger.warn("[iOS-OAuth] #omniauth email_collision scheme=#{scheme}")
        return redirect_to "#{scheme}://auth-complete?error=email_has_password_account",
          allow_other_host: true
      end
      redirect_to new_session_path,
        alert: "That email already has a password account here. Sign in with your password instead."
    else
      if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
        Rails.logger.warn("[iOS-OAuth] #omniauth no_user scheme=#{scheme}")
        return redirect_to "#{scheme}://auth-complete?error=signin_failed",
          allow_other_host: true
      end
      redirect_to new_session_path, alert: "We couldn't sign you in. Please try again."
    end
  end

  # OmniAuth failure handler (user denied access, CSRF/state mismatch, provider error).
  def omniauth_failure
    reason = params[:message].presence || "cancelled"

    # In an iOS handoff, ASWebAuth is waiting for the custom URL scheme — bounce
    # back to it WITH an error reason so the shell surfaces it on-device instead
    # of dead-ending on an HTML page inside Safari. (Previously this returned a
    # tokenless callback the shell treated as a silent abort — exactly the
    # invisible-failure we're instrumenting away.)
    if (scheme = session.delete(:ios_callback_scheme)) && session.delete(:ios_oauth_handoff)
      Rails.logger.warn("[iOS-OAuth] #omniauth_failure reason=#{reason} scheme=#{scheme}")
      return redirect_to "#{scheme}://auth-complete?error=#{CGI.escape(reason.to_s)}",
        allow_other_host: true
    end

    Rails.logger.warn("[iOS-OAuth] #omniauth_failure (web) reason=#{reason}")
    redirect_to new_session_path,
      alert: "Social sign-in didn't complete (#{reason}). Try again."
  end
end
