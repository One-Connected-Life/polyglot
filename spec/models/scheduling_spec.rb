require "rails_helper"

# FSRS scheduling cache row — validations, scopes, helpers. (#axis-4)
RSpec.describe Scheduling, type: :model do
  let(:user) { create(:user) }
  let(:deck) { create(:deck, user: user) }
  let(:term) { create(:term, deck: deck) }

  def build_scheduling(attrs = {})
    Scheduling.new({
      user:          user,
      term:          term,
      from_language: "nl",
      to_language:   "en",
      ease:          3,
    }.merge(attrs))
  end

  describe "validations" do
    it "is valid with required fields" do
      expect(build_scheduling).to be_valid
    end

    it "rejects ease outside 1–5" do
      expect(build_scheduling(ease: 0)).not_to be_valid
      expect(build_scheduling(ease: 6)).not_to be_valid
    end

    it "requires from_language and to_language" do
      expect(build_scheduling(from_language: nil)).not_to be_valid
      expect(build_scheduling(to_language: nil)).not_to be_valid
    end

    it "enforces uniqueness on (user, term, from, to)" do
      build_scheduling.save!
      dup = build_scheduling
      expect(dup).not_to be_valid
    end
  end

  describe ".due_now scope" do
    let(:now) { Time.current }

    it "includes a NEW card (state=0, never reviewed)" do
      s = build_scheduling(state: 0, due: nil).tap(&:save!)
      expect(Scheduling.due_now(from: "nl", to: "en", now: now)).to include(s)
    end

    it "includes a card whose due date is in the past" do
      s = build_scheduling(state: 2, due: 1.day.ago).tap(&:save!)
      expect(Scheduling.due_now(from: "nl", to: "en", now: now)).to include(s)
    end

    it "excludes a card not yet due" do
      s = build_scheduling(state: 2, due: 1.day.from_now).tap(&:save!)
      expect(Scheduling.due_now(from: "nl", to: "en", now: now)).not_to include(s)
    end

    it "excludes archived cards" do
      s = build_scheduling(state: 0, due: nil, archived: true).tap(&:save!)
      expect(Scheduling.due_now(from: "nl", to: "en", now: now)).not_to include(s)
    end
  end

  describe ".retired scope" do
    it "includes cards at or above the stability + reps threshold" do
      s = build_scheduling(
        stability: Mastery::RETIRE_STABILITY_DAYS,
        reps:      Mastery::MIN_REPS_TO_RETIRE
      ).tap(&:save!)
      expect(Scheduling.retired).to include(s)
    end

    it "excludes cards below stability threshold" do
      s = build_scheduling(stability: 10.0, reps: 10).tap(&:save!)
      expect(Scheduling.retired).not_to include(s)
    end

    it "excludes archived cards" do
      s = build_scheduling(
        stability: Mastery::RETIRE_STABILITY_DAYS + 1,
        reps:      Mastery::MIN_REPS_TO_RETIRE,
        archived:  true
      ).tap(&:save!)
      expect(Scheduling.retired).not_to include(s)
    end
  end

  describe "#card_hash / #update_from_card_hash!" do
    it "round-trips all FSRS card fields" do
      s = build_scheduling(stability: 42.5, reps: 3, lapses: 1)
      s.save!

      hash = s.card_hash
      expect(hash[:stability]).to eq(42.5)
      expect(hash[:reps]).to eq(3)
      expect(hash[:lapses]).to eq(1)

      # Simulate an apply() updating it.
      s.update_from_card_hash!(hash.merge(reps: 4, stability: 55.0))
      s.reload
      expect(s.reps).to eq(4)
      expect(s.stability).to eq(55.0)
    end
  end

  describe "#retired? and #retirement_progress" do
    it "delegates to Mastery correctly" do
      high = build_scheduling(stability: Mastery::RETIRE_STABILITY_DAYS + 1,
                              reps: Mastery::MIN_REPS_TO_RETIRE)
      expect(high.retired?).to be(true)
      expect(high.retirement_progress).to eq(1.0)

      low = build_scheduling(stability: Mastery::RETIRE_STABILITY_DAYS / 2,
                             reps: 10)
      expect(low.retired?).to be(false)
      expect(low.retirement_progress).to be_within(0.01).of(0.5)
    end
  end
end
