require "rails_helper"

# AttemptsController — FSRS grading path (FSRS_ENABLED=1). (#axis-4)
#
# Contract: POST /attempts returns JSON with newly_retired + FSRS fields
# when the flag is on, and falls through to legacy newly_owned when it's off.
RSpec.describe "Attempts (FSRS)", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user) }
  let(:term) { create(:term, deck: deck) }

  before do
    create(:translation, term: term, language: "nl", text: "hond")
    create(:translation, term: term, language: "en", text: "dog")
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def post_attempt(correct:, fsrs_enabled: "1")
    old = ENV["FSRS_ENABLED"]
    ENV["FSRS_ENABLED"] = fsrs_enabled
    post attempts_path, params: {
      term_id: term.id,
      from:    "nl",
      to:      "en",
      correct: correct,
      given:   correct ? "dog" : "wrong",
    }, as: :json
  ensure
    old.nil? ? ENV.delete("FSRS_ENABLED") : ENV["FSRS_ENABLED"] = old
  end

  context "with FSRS_ENABLED=1" do
    it "creates an Attempt record" do
      expect { post_attempt(correct: true) }.to change(Attempt, :count).by(1)
    end

    it "creates or updates a Scheduling row" do
      expect { post_attempt(correct: true) }.to change(Scheduling, :count).by(1)
    end

    it "returns newly_retired: false for a first correct answer" do
      post_attempt(correct: true)
      expect(response.parsed_body["newly_retired"]).to be(false)
    end

    it "returns FSRS metadata fields" do
      post_attempt(correct: true)
      body = response.parsed_body
      expect(body).to have_key("reps")
      expect(body).to have_key("stability")
      expect(body).to have_key("due")
    end

    it "increments reps on the scheduling row" do
      post_attempt(correct: true)
      expect(Scheduling.last.reps).to eq(1)
    end
  end

  context "with FSRS_ENABLED=0 (legacy path)" do
    it "returns newly_owned on reaching 2 correct answers" do
      post_attempt(correct: true, fsrs_enabled: "0")
      post_attempt(correct: true, fsrs_enabled: "0")
      expect(response.parsed_body["newly_owned"]).to be(true)
    end

    it "does not create Scheduling rows" do
      expect { post_attempt(correct: true, fsrs_enabled: "0") }.not_to change(Scheduling, :count)
    end
  end
end
