# Social login via OmniAuth (Google + Facebook). Additive to email/password.
#
# Each provider is registered ONLY when its ENV credentials are present, so a
# production box without creds configured simply has no /auth/<provider> route
# instead of booting with a half-configured strategy. The login view mirrors this
# (it renders a provider button only when the same ENV is present), so the UI and
# the middleware never disagree.
#
# ENV expected:
#   GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
#   FACEBOOK_APP_ID  / FACEBOOK_APP_SECRET
Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
    provider :google_oauth2,
             ENV["GOOGLE_CLIENT_ID"],
             ENV["GOOGLE_CLIENT_SECRET"],
             scope: "email,profile",
             prompt: "select_account"
  end

  if ENV["FACEBOOK_APP_ID"].present? && ENV["FACEBOOK_APP_SECRET"].present?
    provider :facebook,
             ENV["FACEBOOK_APP_ID"],
             ENV["FACEBOOK_APP_SECRET"],
             scope: "email",
             info_fields: "name,email,picture"
  end
end

# On any OmniAuth failure (user denied, bad state, provider error) send the user
# back to the sign-in page with a flash rather than rendering OmniAuth's raw page.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:omniauth_failure).call(env)
end

# Quieter logs; the strategy still raises in dev for real misconfig.
OmniAuth.config.logger = Rails.logger
