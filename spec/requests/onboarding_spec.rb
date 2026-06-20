require "rails_helper"

RSpec.describe "Onboarding", type: :request do
  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  describe "PATCH /onboarding (learning_languages)" do
    it "saves multiple learning languages" do
      user = create(:user, source_language: "en", target_language: nil)
      sign_in(user)
      patch onboarding_path, params: {
        user: {
          source_language: "en",
          learning_languages: ["", "nl", "es", "fr"],  # "" is the sentinel hidden input
        }
      }
      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.active_learning_languages).to eq(%w[nl es fr])
    end

    it "sets target_language to the first learning language when not provided" do
      user = create(:user, source_language: "en", target_language: nil)
      sign_in(user)
      patch onboarding_path, params: {
        user: {
          source_language: "en",
          learning_languages: ["", "es", "fr"],
        }
      }
      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.target_language).to eq("es")
    end

    it "strips blank sentinel values from learning_languages" do
      user = create(:user, source_language: "en", target_language: "nl")
      sign_in(user)
      patch onboarding_path, params: {
        user: {
          source_language: "en",
          learning_languages: [""],  # only sentinel
        }
      }
      # With only blank entries, learning_languages becomes [] → falls back gracefully
      expect(response).to redirect_to(root_path)
    end

    it "saves drill_direction" do
      user = create(:user, source_language: "en", target_language: "nl")
      sign_in(user)
      patch onboarding_path, params: {
        user: {
          source_language: "en",
          learning_languages: ["", "nl"],
          drill_direction: "random",
        }
      }
      expect(response).to redirect_to(root_path)
      expect(user.reload.drill_direction).to eq("random")
    end

    it "re-renders on invalid learning_languages" do
      user = create(:user, source_language: "en", target_language: "nl")
      sign_in(user)
      patch onboarding_path, params: {
        user: {
          source_language: "en",
          learning_languages: ["", "en", "nl"],  # en = source language, invalid
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
