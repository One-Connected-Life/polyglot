require "rails_helper"

RSpec.describe "OmniAuth callback", type: :request do
  before(:all) { OmniAuth.config.test_mode = true }
  after(:all)  { OmniAuth.config.test_mode = false }

  before { OmniAuth.config.mock_auth[:google_oauth2] = nil }

  def stub_google(uid: "google-123", email: "oauth@example.com", name: "OAuth Person")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { "email" => email, "name" => name, "image" => "http://img/x.png" }
    )
  end

  it "creates a user, sets the session cookie, and redirects to root on first login" do
    stub_google
    expect {
      get "/auth/google_oauth2/callback"
    }.to change(User, :count).by(1)

    user = User.find_by(provider: "google_oauth2", uid: "google-123")
    expect(user).to be_present
    expect(user.email_address).to eq("oauth@example.com")

    # Session established the same way password login does: a Session row + signed cookie.
    expect(user.sessions.count).to eq(1)
    expect(response.cookies["session_id"]).to be_present
    expect(response).to redirect_to(root_path) # onboarded user lands at root
  end

  it "is idempotent — a repeat login finds the same user, no new account" do
    stub_google
    get "/auth/google_oauth2/callback"
    expect {
      get "/auth/google_oauth2/callback"
    }.not_to change(User, :count)
    expect(response).to redirect_to(root_path)
  end

  it "actually authenticates — the session is live, not bounced to sign-in" do
    stub_google
    get "/auth/google_oauth2/callback"
    follow_redirect! # to root
    # A brand-new OAuth user has no target_language yet, so require_onboarding sends
    # them to onboarding — NOT to /session/new. That redirect proves the session is live.
    expect(response).to redirect_to(onboarding_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "LINKS a verified-email Google login onto an existing password account (no takeover dead-end)" do
    existing = create(:user, email_address: "collide@example.com", password: "password")
    stub_google(uid: "google-collide", email: "collide@example.com")
    expect {
      get "/auth/google_oauth2/callback"
    }.not_to change(User, :count)                 # linked onto the existing account, not created
    existing.reload
    expect(existing.provider).to eq("google_oauth2")
    expect(existing.uid).to eq("google-collide")
    expect(response.cookies["session_id"]).to be_present  # actually signed in
    expect(response).to redirect_to(root_path)
  end

  it "redirects to sign-in with a flash on provider failure" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    get "/auth/google_oauth2/callback"
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to be_present
  end
end
