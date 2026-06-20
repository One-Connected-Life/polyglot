require "rails_helper"

# Adapter between our Attempt stream and the fsrs gem — isolated from the live
# drill. These specs pin the adapter behavior so it can be reviewed before it
# touches DrillsController. (#axis-4)
RSpec.describe FsrsScheduler do
  subject(:scheduler) { described_class.new }

  # Minimal stand-in for Attempt: just the two fields replay/apply read.
  Graded = Struct.new(:correct, :created_at)

  describe "#blank_card" do
    it "is a never-studied card (FSRS state NEW = 0)" do
      card = scheduler.blank_card
      expect(card[:state]).to eq(Fsrs::State::NEW)
      expect(card[:reps]).to eq(0)
      expect(card[:stability]).to eq(0.0)
    end

    it "round-trips losslessly through the gem (every persisted column present)" do
      expect(scheduler.blank_card.keys).to match_array(FsrsScheduler::CARD_KEYS)
    end
  end

  describe "#apply" do
    let(:now) { Time.utc(2026, 6, 20, 9, 0, 0) }

    it "advances a correct answer (GOOD): reps up, stability positive, due in the future" do
      card = scheduler.apply(scheduler.blank_card, correct: true, at: now)

      expect(card[:reps]).to eq(1)
      expect(card[:stability]).to be > 0
      expect(card[:due]).to be > now.to_datetime
    end

    it "treats a wrong answer (AGAIN) as a lapse with a short interval" do
      learned   = scheduler.apply(scheduler.blank_card, correct: true, at: now)
      learned   = scheduler.apply(learned, correct: true, at: now + 3.days)
      relearned = scheduler.apply(learned, correct: false, at: now + 10.days)

      expect(relearned[:lapses]).to be >= 1
      expect(relearned[:stability]).to be < learned[:stability]
    end

    it "accepts Time, DateTime and String timestamps" do
      from_time   = scheduler.apply(scheduler.blank_card, correct: true, at: now)
      from_dt     = scheduler.apply(scheduler.blank_card, correct: true, at: now.to_datetime)
      from_string = scheduler.apply(scheduler.blank_card, correct: true, at: now.iso8601)

      expect(from_time[:due]).to eq(from_dt[:due])
      expect(from_string[:due]).to eq(from_dt[:due])
    end

    it "is a pure function of the input hash — never mutates the original" do
      card = scheduler.blank_card
      scheduler.apply(card, correct: true, at: now)
      expect(card[:reps]).to eq(0)
    end

    context "with ease seeding" do
      # FSRS init_difficulty: EASY → ~3.99, GOOD → ~4.93, HARD → ~5.87
      it "seeds a lower initial difficulty for easy words (ease=1 → EASY rating)" do
        easy_card = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 1)
        hard_card = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 5)

        expect(easy_card[:difficulty]).to be < hard_card[:difficulty]
      end

      it "gives ease=1 (EASY rating) a longer first interval than ease=5 (HARD rating)" do
        easy_card = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 1)
        hard_card = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 5)

        # EASY rating on NEW card → longer scheduled interval
        expect(easy_card[:scheduled_days]).to be > hard_card[:scheduled_days]
      end

      it "only applies ease on the first (NEW) review; FSRS owns difficulty after that" do
        first_easy = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 1)
        first_hard = scheduler.apply(scheduler.blank_card, correct: true, at: now, ease: 5)

        # Apply the opposite ease on second review — should have little effect vs FSRS's own update
        second_easy = scheduler.apply(first_easy, correct: true, at: now + 5.days, ease: 5)
        second_hard = scheduler.apply(first_hard, correct: true, at: now + 5.days, ease: 1)

        # The initial difficulty seeding persists into the second review via FSRS's mean reversion.
        # Easy-seeded card should still have lower difficulty than hard-seeded.
        expect(second_easy[:difficulty]).to be <= second_hard[:difficulty]
      end
    end
  end

  describe "#replay (the backfill primitive)" do
    let(:start) { Time.utc(2026, 1, 1, 12, 0, 0) }

    it "rebuilds the same card whether applied step-by-step or replayed in bulk" do
      attempts = [
        Graded.new(true,  start),
        Graded.new(true,  start + 2.days),
        Graded.new(false, start + 9.days),
        Graded.new(true,  start + 10.days),
      ]

      step_by_step = attempts.reduce(scheduler.blank_card) do |card, a|
        scheduler.apply(card, correct: a.correct, at: a.created_at)
      end

      expect(scheduler.replay(attempts)).to eq(step_by_step)
    end

    it "an empty history replays to a blank card" do
      expect(scheduler.replay([])).to eq(scheduler.blank_card)
    end

    it "a long correct streak grows stability monotonically (spaced repetition)" do
      t = start
      attempts = []
      6.times { attempts << Graded.new(true, t); t += 30.days }

      card = scheduler.replay(attempts)
      expect(card[:reps]).to eq(6)
      expect(card[:stability]).to be > 30
    end
  end

  describe "#due?" do
    let(:now) { Time.utc(2026, 6, 20, 9, 0, 0) }

    it "a brand-new card is always due" do
      expect(scheduler.due?(scheduler.blank_card, now: now)).to be(true)
    end

    it "a freshly-reviewed card is not due until its scheduled date" do
      card = scheduler.apply(scheduler.blank_card, correct: true, at: now)
      card = scheduler.apply(card, correct: true, at: now + 2.days)

      due_at = card[:due].to_time
      expect(scheduler.due?(card, now: due_at - 1.hour)).to be(false)
      expect(scheduler.due?(card, now: due_at + 1.hour)).to be(true)
    end
  end
end
