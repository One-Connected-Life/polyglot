require "rails_helper"

RSpec.describe User, type: :model do
  describe ".from_omniauth" do
    def auth_hash(provider: "google_oauth2", uid: "123", email: "new@example.com", name: "New Person", image: "http://img/a.png")
      OmniAuth::AuthHash.new(
        provider: provider,
        uid: uid,
        info: { "email" => email, "name" => name, "image" => image }
      )
    end

    it "creates a new user from the auth hash, filling provider/uid/email/name/avatar" do
      expect {
        @user = User.from_omniauth(auth_hash)
      }.to change(User, :count).by(1)

      expect(@user).to be_persisted
      expect(@user.provider).to eq("google_oauth2")
      expect(@user.uid).to eq("123")
      expect(@user.email_address).to eq("new@example.com")
      expect(@user.name).to eq("New Person")
      expect(@user.avatar_url).to eq("http://img/a.png")
      expect(@user.oauth_user?).to be true
    end

    it "finds the existing user on a repeat login (idempotent by [provider, uid])" do
      existing = User.from_omniauth(auth_hash)
      expect {
        found = User.from_omniauth(auth_hash)
        expect(found.id).to eq(existing.id)
      }.not_to change(User, :count)
    end

    it "distinguishes the same uid across different providers" do
      g = User.from_omniauth(auth_hash(provider: "google_oauth2", uid: "777", email: "g@example.com"))
      f = User.from_omniauth(auth_hash(provider: "facebook", uid: "777", email: "f@example.com"))
      expect(g.id).not_to eq(f.id)
    end

    it "LINKS a verified-email provider (Google) onto an existing password account" do
      existing = create(:user, email_address: "taken@example.com") # password account
      result = User.from_omniauth(auth_hash(provider: "google_oauth2", uid: "999", email: "taken@example.com"))
      expect(result).to be_persisted
      expect(result.id).to eq(existing.id)        # same account, now linked
      expect(result.provider).to eq("google_oauth2")
      expect(result.uid).to eq("999")
    end

    it "does NOT link an UNVERIFIED-email provider to an existing password account (returns unsaved)" do
      create(:user, email_address: "taken2@example.com") # password account
      result = User.from_omniauth(auth_hash(provider: "facebook", uid: "888", email: "taken2@example.com"))
      expect(result).not_to be_persisted
    end

    it "creates an OAuth user with no password and still validates" do
      user = User.from_omniauth(auth_hash(uid: "555", email: "nopass@example.com"))
      expect(user).to be_persisted
      expect(user.password_digest).to be_nil
    end
  end

  describe "password validation (additive)" do
    it "still requires a password for non-OAuth users on create" do
      user = User.new(email_address: "p@example.com", source_language: "en")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "lets a password user authenticate via authenticate_by" do
      create(:user, email_address: "auth@example.com", password: "password")
      expect(User.authenticate_by(email_address: "auth@example.com", password: "password")).to be_present
      expect(User.authenticate_by(email_address: "auth@example.com", password: "wrong")).to be_nil
    end
  end
end
