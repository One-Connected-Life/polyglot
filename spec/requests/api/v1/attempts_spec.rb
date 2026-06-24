require "rails_helper"

# POST /api/v1/attempts — same JSON contract as the web AttemptsController.
RSpec.describe "Api::V1 attempts", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "ready") }
  let(:term) { create(:term, deck: deck, reviewed: true) }

  before do
    create(:translation, term: term, language: "nl", text: "hond")
    create(:translation, term: term, language: "en", text: "dog")
  end

  def post_attempt(correct:, headers:, fsrs: "0")
    old = ENV["FSRS_ENABLED"]
    ENV["FSRS_ENABLED"] = fsrs
    post "/api/v1/attempts",
         params: { term_id: term.id, from: "nl", to: "en", correct: correct, given: "dog" },
         headers: headers, as: :json
  ensure
    old.nil? ? ENV.delete("FSRS_ENABLED") : ENV["FSRS_ENABLED"] = old
  end

  it "401s without a token" do
    post "/api/v1/attempts", params: { term_id: term.id, from: "nl", to: "en", correct: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "records the attempt and returns the legacy shape when FSRS off" do
    headers = auth_headers(user)
    expect { post_attempt(correct: true, headers: headers, fsrs: "0") }.to change(Attempt, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(json).to include("correct_count" => 1, "newly_owned" => false)
  end

  it "returns the FSRS shape when FSRS on" do
    headers = auth_headers(user)
    post_attempt(correct: true, headers: headers, fsrs: "1")
    expect(response).to have_http_status(:ok)
    expect(json.keys).to include("newly_owned", "newly_retired", "reps", "stability", "due")
    expect(json["reps"]).to eq(1)
  end

  it "scopes the attempt to the authenticated user (no cross-tenant write)" do
    other = create(:user, target_language: "nl", source_language: "en")
    headers = auth_headers(other)
    post "/api/v1/attempts",
         params: { term_id: term.id, from: "nl", to: "en", correct: true }, headers: headers, as: :json
    # term belongs to `user`, not `other` → not found
    expect(response).to have_http_status(:not_found)
  end
end
