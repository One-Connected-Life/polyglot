require "rails_helper"

RSpec.describe OauthHandoff, type: :model do
  let(:user) { create(:user) }

  describe ".issue!" do
    it "mints a unique token that expires in the future" do
      h = described_class.issue!(user)
      expect(h.token).to be_present
      expect(h.expires_at).to be > Time.current
      expect(h.redeemed_at).to be_nil
    end
  end

  describe ".redeem!" do
    it "returns the user and marks the token redeemed" do
      h = described_class.issue!(user)
      expect(described_class.redeem!(h.token)).to eq(user)
      expect(h.reload.redeemed_at).to be_present
    end

    it "is single-use — a second redeem returns nil" do
      token = described_class.issue!(user).token
      expect(described_class.redeem!(token)).to eq(user)
      expect(described_class.redeem!(token)).to be_nil
    end

    it "returns nil for an expired token" do
      h = described_class.issue!(user)
      h.update_column(:expires_at, 1.second.ago)
      expect(described_class.redeem!(h.token)).to be_nil
    end

    it "returns nil for a blank or unknown token" do
      expect(described_class.redeem!(nil)).to be_nil
      expect(described_class.redeem!("")).to be_nil
      expect(described_class.redeem!("nope")).to be_nil
    end
  end
end
