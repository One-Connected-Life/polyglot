class IosOauthController < ApplicationController
  # iOS OAuth handoff (App A — Hotwire Native shell). Bug: "Sign in with Google"
  # fails on device with Error 403 disallowed_useragent because Google refuses
  # OAuth inside an embedded WKWebView. The native shell therefore runs the flow
  # in ASWebAuthenticationSession (Safari), and these endpoints bridge the
  # resulting auth back into the WKWebView's cookie jar.
  #
  # Flow:
  #   1. Shell opens  /ios/oauth_start?provider=<slug>&callback_scheme=mynewwords
  #      INSIDE ASWebAuth (Safari). We remember "this OmniAuth flow is a native
  #      handoff" in the Safari-side Rails session, then auto-POST to
  #      /auth/<provider> (preserving omniauth-rails_csrf_protection — GET
  #      initiation stays disabled).
  #   2. Google accepts (real Safari UA) → OmniAuth callback → SessionsController#omniauth.
  #      Because the handoff flag is set, that action mints a one-time OauthHandoff
  #      token and redirects to  mynewwords://auth-complete?handoff=<token>.
  #   3. ASWebAuth hands the custom-scheme URL back to the shell, which routes the
  #      WKWebView to  /ios/session_handoff?token=<token>  — #handoff below — which
  #      redeems the token (single-use) and sets the real signed session cookie in
  #      the WKWebView jar. All tabs become authenticated.
  #
  # Both actions are unauthenticated and onboarding-exempt: the user is mid-login.
  allow_unauthenticated_access only: %i[ start handoff ]
  skip_before_action :require_onboarding, only: %i[ start handoff ]

  # Allowlist of providers we actually serve, mirroring config/initializers/omniauth.rb.
  ALLOWED_PROVIDERS = %w[ google_oauth2 facebook ].freeze

  # GET /ios/oauth_start?provider=<slug>&callback_scheme=mynewwords
  # Runs in Safari (ASWebAuth). Marks the session as a native handoff and
  # auto-submits a CSRF-protected POST to /auth/<provider>.
  def start
    provider = params[:provider].to_s
    scheme   = params[:callback_scheme].to_s

    unless ALLOWED_PROVIDERS.include?(provider) && scheme.present?
      return redirect_to new_session_path, alert: "Unsupported sign-in request."
    end

    # Flag this OmniAuth flow as a native handoff. SessionsController#omniauth
    # reads it to decide between the web redirect and the custom-scheme handoff.
    session[:ios_oauth_handoff] = true
    session[:ios_callback_scheme] = scheme

    @provider_path = "/auth/#{provider}"
    render :start, layout: false
  end

  # GET /ios/session_handoff?token=<one-time-token>
  # Routed here by the shell INSIDE the WKWebView. Redeems the single-use token
  # and establishes the real session cookie, then bounces to the post-auth URL.
  def handoff
    user = OauthHandoff.redeem!(params[:token])

    if user
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path,
        alert: "That sign-in link expired. Please try signing in again."
    end
  end
end
