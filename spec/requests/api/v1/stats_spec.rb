require "rails_helper"

# GET /api/v1/stats — active words + retired shelf + approaching + totals.
RSpec.describe "Api::V1 stats", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "ready") }
  let!(:term) { create(:term, deck: deck, kind: "word", reviewed: true) }

  before do
    create(:translation, term: term, language: "nl", text: "hond")
    create(:translation, term: term, language: "en", text: "dog")
  end

  it "401s without a token" do
    get "/api/v1/stats"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the stats shape" do
    create(:attempt, user: user, term: term, from_language: "nl", to_language: "en", correct: true)
    get "/api/v1/stats", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)

    expect(json).to include("target" => "nl", "source" => "en")
    expect(json["totals"]).to include("attempts" => 1, "correct" => 1)
    active = json["active_words"].find { |w| w["id"] == term.id }
    expect(active).to include("target" => "hond", "source" => "dog")
    expect(active["status"]).to be_present
    expect(json).to have_key("retired_words")
    expect(json).to have_key("approaching_words")
  end
end
