require "rails_helper"

# /api/v1 auth surface: token login, registration, /me, logout, and the
# 401-without-token contract every endpoint shares.
RSpec.describe "Api::V1 auth", type: :request do
  let(:user) { create(:user, name: "Pat", target_language: "nl", source_language: "en") }

  describe "POST /api/v1/sessions" do
    it "returns a token + user on valid credentials" do
      post "/api/v1/sessions", params: { email_address: user.email_address, password: "password" }, as: :json
      expect(response).to have_http_status(:created)
      expect(json["token"]).to be_present
      expect(json["user"]).to include(
        "id" => user.id, "email_address" => user.email_address,
        "onboarded" => true, "target_language" => "nl", "source_language" => "en"
      )
      expect(json["user"]["learning_languages"]).to eq(["nl"])
    end

    it "mints a real Session row with the returned token" do
      expect {
        post "/api/v1/sessions", params: { email_address: user.email_address, password: "password" }, as: :json
      }.to change(Session, :count).by(1)
      expect(Session.find_by(api_token: json["token"]).user).to eq(user)
    end

    it "401s on bad password" do
      post "/api/v1/sessions", params: { email_address: user.email_address, password: "nope" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("invalid_credentials")
    end
  end

  describe "POST /api/v1/registrations" do
    it "creates a user and returns token + user" do
      expect {
        post "/api/v1/registrations", params: {
          user: { name: "New", email_address: "new@example.com", password: "secret123", password_confirmation: "secret123" }
        }, as: :json
      }.to change(User, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["token"]).to be_present
      expect(json["user"]).to include("email_address" => "new@example.com", "onboarded" => false)
    end

    it "422s with errors on invalid input (password mismatch)" do
      post "/api/v1/registrations", params: {
        user: { name: "X", email_address: "x@example.com", password: "secret123", password_confirmation: "different" }
      }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "GET /api/v1/me" do
    it "401s without a token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("unauthorized")
    end

    it "401s with a bogus token" do
      get "/api/v1/me", headers: { "Authorization" => "Bearer not-a-real-token" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user with a valid token" do
      get "/api/v1/me", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["user"]["id"]).to eq(user.id)
    end
  end

  describe "DELETE /api/v1/session" do
    it "revokes the token" do
      token = api_token_for(user)
      headers = { "Authorization" => "Bearer #{token}" }
      delete "/api/v1/session", headers: headers
      expect(response).to have_http_status(:no_content)
      # token no longer authenticates
      get "/api/v1/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/onboarding" do
    it "401s without a token" do
      patch "/api/v1/onboarding", params: { user: { learning_languages: ["nl"] } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "saves languages and syncs target_language to the first" do
      u = create(:user, source_language: "en", target_language: nil)
      patch "/api/v1/onboarding",
            params: { user: { source_language: "en", learning_languages: ["", "es", "fr"] } },
            headers: auth_headers(u), as: :json
      expect(response).to have_http_status(:ok)
      u.reload
      expect(u.active_learning_languages).to eq(%w[es fr])
      expect(u.target_language).to eq("es")
    end

    it "422s on invalid languages" do
      u = create(:user, source_language: "en", target_language: "nl")
      patch "/api/v1/onboarding",
            params: { user: { source_language: "en", learning_languages: ["", "en"] } },
            headers: auth_headers(u), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "GET /api/v1/languages" do
    it "returns the language registry" do
      get "/api/v1/languages", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["languages"]).to include({ "code" => "nl", "name" => "Dutch" })
      expect(json["non_latin"]).to include("ru")
    end

    it "401s without a token" do
      get "/api/v1/languages"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
