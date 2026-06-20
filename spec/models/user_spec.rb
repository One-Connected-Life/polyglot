require "rails_helper"

RSpec.describe User, type: :model do
  describe "#active_learning_languages" do
    it "returns the stored learning languages when set" do
      user = build(:user, learning_languages: %w[nl es fr])
      expect(user.active_learning_languages).to eq(%w[nl es fr])
    end

    it "falls back to [target_language] when learning_languages is nil" do
      user = build(:user, target_language: "nl", learning_languages: nil)
      expect(user.active_learning_languages).to eq(["nl"])
    end

    it "falls back to [target_language] when learning_languages is empty" do
      user = build(:user, target_language: "nl", learning_languages: [])
      expect(user.active_learning_languages).to eq(["nl"])
    end

    it "filters out unknown language codes" do
      # Build with skip_validate so invalid code doesn't fail the build
      user = build(:user, learning_languages: %w[nl xx es])
      # Bypass validation to test the filter logic directly
      user.define_singleton_method(:learning_languages_are_valid) { }
      expect(user.active_learning_languages).to eq(%w[nl es])
    end
  end

  describe "#multi_language_drill?" do
    it "returns true when user has 2+ learning languages" do
      user = build(:user, learning_languages: %w[nl es])
      expect(user.multi_language_drill?).to be true
    end

    it "returns false when user has only 1 learning language" do
      user = build(:user, target_language: "nl", learning_languages: nil)
      expect(user.multi_language_drill?).to be false
    end
  end

  describe "validations" do
    it "is invalid when learning_languages includes an unknown code" do
      user = build(:user, learning_languages: %w[nl xx])
      expect(user).not_to be_valid
      expect(user.errors[:learning_languages]).to be_present
    end

    it "is invalid when learning_languages includes the source language" do
      user = build(:user, source_language: "en", learning_languages: %w[en nl])
      expect(user).not_to be_valid
      expect(user.errors[:learning_languages]).to be_present
    end

    it "is valid with a proper multi-language setup" do
      user = build(:user, source_language: "en", target_language: "nl",
                   learning_languages: %w[nl es fr])
      expect(user).to be_valid
    end

    it "is valid when learning_languages is nil (not yet set)" do
      user = build(:user, learning_languages: nil)
      expect(user).to be_valid
    end

    it "validates drill_direction" do
      user = build(:user, drill_direction: "sideways")
      expect(user).not_to be_valid
      expect(user.errors[:drill_direction]).to be_present
    end
  end
end
