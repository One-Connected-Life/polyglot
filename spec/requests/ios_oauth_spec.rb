require "rails_helper"

# Contract specs for the iOS OAuth handoff (App A). Google blocks OAuth inside an
# embedded WKWebView, so the native shell runs the flow in
# ASWebAuthenticationSession (Safari) and bridges the result back through these
# endpoints with a one-time token. See IosOauthController.
RSpec.describe "iOS OAuth handoff", type: :request do
  describe "GET /ios/oauth_start" do
    it "flags the session and renders an auto-submitting POST form to /auth/<provider>" do
      get "/ios/oauth_start", params: { provider: "google_oauth2", callback_scheme: "mynewwords" }

      expect(response).to have_http_status(:ok)
      # A real <form method="post" action="/auth/google_oauth2"> that auto-submits.
      # The POST (not a GET link) preserves omniauth-rails_csrf_protection — GET
      # initiation stays disabled.
      expect(response.body).to include('action="/auth/google_oauth2"')
      expect(response.body).to include('method="post"')
      expect(response.body).to include('document.getElementById("oauth-form").submit()')
    end

    it "emits a CSRF authenticity_token when forgery protection is on (prod parity)" do
      # Test env disables forgery protection, so form_with omits the token by
      # default. Flip it on for this one case to prove the form carries the token
      # omniauth-rails_csrf_protection requires at the POST step in production.
      allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)
      get "/ios/oauth_start", params: { provider: "google_oauth2", callback_scheme: "mynewwords" }
      expect(response.body).to include('name="authenticity_token"')
    end

    it "rejects an unknown provider" do
      get "/ios/oauth_start", params: { provider: "evil", callback_scheme: "mynewwords" }
      expect(response).to redirect_to(new_session_path)
    end

    it "rejects a missing callback scheme" do
      get "/ios/oauth_start", params: { provider: "google_oauth2" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "OmniAuth callback during a native handoff" do
    before(:all) { OmniAuth.config.test_mode = true }
    after(:all)  { OmniAuth.config.test_mode = false }
    before { OmniAuth.config.mock_auth[:google_oauth2] = nil }

    def stub_google(uid: "g-ios-1", email: "ios@example.com")
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: uid,
        info: { "email" => email, "name" => "iOS User" }
      )
    end

    it "redirects to the custom URL scheme with a one-time token (NOT the web cookie redirect)" do
      stub_google
      # Arm the handoff flag the way /ios/oauth_start would have.
      get "/ios/oauth_start", params: { provider: "google_oauth2", callback_scheme: "mynewwords" }

      expect { get "/auth/google_oauth2/callback" }.to change(OauthHandoff, :count).by(1)

      token = OauthHandoff.last.token
      expect(response).to redirect_to("mynewwords://auth-complete?handoff=#{token}")
      # The Safari-side cookie is intentionally NOT the bridge — the WKWebView gets
      # its cookie later, at /ios/session_handoff. No session_id is granted here.
      expect(response.cookies["session_id"]).to be_blank
    end

    it "falls back to the normal web cookie flow when NOT a native handoff" do
      stub_google
      expect { get "/auth/google_oauth2/callback" }.not_to change(OauthHandoff, :count)
      expect(response.cookies["session_id"]).to be_present
      expect(response).to redirect_to(root_path)
    end
  end

  describe "OmniAuth failure during a native handoff" do
    before(:all) { OmniAuth.config.test_mode = true }
    after(:all)  { OmniAuth.config.test_mode = false }

    it "bounces back to the custom scheme (no token) so ASWebAuth closes cleanly" do
      OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
      get "/ios/oauth_start", params: { provider: "google_oauth2", callback_scheme: "mynewwords" }
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to("mynewwords://auth-complete")
    end
  end

  # The native shell can only intercept a GET link tap (OAuthCoordinator
  # .isOAuthStartURL). A POST button_to would submit inside the WKWebView and hit
  # Google's disallowed_useragent 403. So under the Hotwire Native UA the login
  # view MUST render the Google control as a GET <a>, not a POST <form>.
  describe "login view OAuth control by client" do
    around do |ex|
      ENV["GOOGLE_CLIENT_ID"] = "x"
      ENV["GOOGLE_CLIENT_SECRET"] = "y"
      ex.run
    ensure
      ENV.delete("GOOGLE_CLIENT_ID")
      ENV.delete("GOOGLE_CLIENT_SECRET")
    end

    it "renders a GET link to /auth/google_oauth2 under the Hotwire Native UA" do
      get "/session/new", headers: { "HTTP_USER_AGENT" => "MyApp Hotwire Native iOS" }
      # A GET anchor — the shell intercepts this and diverts to ASWebAuth.
      expect(response.body).to match(%r{<a[^>]+href="/auth/google_oauth2"})
      expect(response.body).not_to match(%r{<form[^>]+action="/auth/google_oauth2"})
    end

    it "renders a POST form to /auth/google_oauth2 in a normal browser" do
      get "/session/new", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh) Safari" }
      expect(response.body).to match(%r{<form[^>]+action="/auth/google_oauth2"})
    end
  end

  describe "GET /ios/session_handoff" do
    let(:user) { create(:user) }

    it "redeems a valid token, sets the real session cookie, and redirects" do
      token = OauthHandoff.issue!(user).token

      get "/ios/session_handoff", params: { token: token }

      expect(response.cookies["session_id"]).to be_present
      expect(user.sessions.count).to eq(1)
      # Onboarded user → root.
      expect(response).to redirect_to(root_path)
    end

    it "is single-use — a replayed token is rejected" do
      token = OauthHandoff.issue!(user).token
      get "/ios/session_handoff", params: { token: token }
      expect(response.cookies["session_id"]).to be_present

      # Replay: token already redeemed → no cookie, bounced to sign-in.
      get "/ios/session_handoff", params: { token: token }
      expect(response).to redirect_to(new_session_path)
    end

    it "rejects an expired token" do
      handoff = OauthHandoff.issue!(user)
      handoff.update_column(:expires_at, 1.minute.ago)

      get "/ios/session_handoff", params: { token: handoff.token }
      expect(response).to redirect_to(new_session_path)
      expect(response.cookies["session_id"]).to be_blank
    end

    it "rejects a bogus token" do
      get "/ios/session_handoff", params: { token: "not-a-real-token" }
      expect(response).to redirect_to(new_session_path)
    end
  end
end
