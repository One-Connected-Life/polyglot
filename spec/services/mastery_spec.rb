require "rails_helper"

# The retire-and-celebrate POLICY: when does FSRS say a word is owned for good?
# Pure value-object logic over a card hash — no DB, no gem. (#axis-4)
RSpec.describe Mastery do
  def card(stability:, reps: 5)
    { stability: stability, reps: reps }
  end

  describe "#retired?" do
    it "is true once stability crosses the retire threshold with enough reps" do
      expect(described_class.new(card(stability: 200)).retired?).to be(true)
    end

    it "is false below the stability threshold even with many reps" do
      expect(described_class.new(card(stability: 60)).retired?).to be(false)
    end

    it "does not retire a high-stability card seen too few times (lucky jump guard)" do
      barely_seen = card(stability: 999, reps: described_class::MIN_REPS_TO_RETIRE - 1)
      expect(described_class.new(barely_seen).retired?).to be(false)
    end

    it "tolerates a nil/empty card (brand-new, never-studied)" do
      expect(described_class.new(nil).retired?).to be(false)
      expect(described_class.new({}).retired?).to be(false)
    end
  end

  describe "#progress" do
    it "reports fractional progress toward retirement" do
      half = described_class::RETIRE_STABILITY_DAYS / 2
      expect(described_class.new(card(stability: half)).progress).to be_within(0.01).of(0.5)
    end

    it "caps at 1.0 once retired" do
      expect(described_class.new(card(stability: 10_000)).progress).to eq(1.0)
    end
  end

  describe "#newly_retired_from? (fires the celebrate exactly at the transition)" do
    let(:before_card) { card(stability: 150) }   # not yet retired
    let(:after_card)  { card(stability: 210) }   # crossed the line

    it "is true when the card crossed from not-retired to retired this grade" do
      expect(described_class.new(after_card).newly_retired_from?(before_card)).to be(true)
    end

    it "is false when it was already retired before this grade (no double-celebrate)" do
      already = card(stability: 300)
      expect(described_class.new(after_card).newly_retired_from?(already)).to be(false)
    end

    it "is false when the card is still short of retirement" do
      expect(described_class.new(before_card).newly_retired_from?(card(stability: 100))).to be(false)
    end
  end
end
