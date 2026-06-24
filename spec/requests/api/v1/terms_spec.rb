require "rails_helper"

# GET /api/v1/terms/:id (+ ease / unretire tweaks).
RSpec.describe "Api::V1 terms", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "ready") }
  let(:term) { create(:term, deck: deck, reviewed: true) }

  before do
    create(:translation, term: term, language: "nl", text: "hond", article: "de")
    create(:translation, term: term, language: "en", text: "dog")
  end

  it "401s without a token" do
    get "/api/v1/terms/#{term.id}"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the term with all translations + attempt history" do
    create(:attempt, user: user, term: term, from_language: "nl", to_language: "en", correct: false, given: "cat")
    get "/api/v1/terms/#{term.id}", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)

    t = json["term"]
    expect(t["id"]).to eq(term.id)
    nl = t["translations"].find { |x| x["lang"] == "nl" }
    expect(nl).to include("text" => "hond", "article" => "de", "with_article" => "de hond")
    expect(t["attempts"].first).to include("correct" => false, "given" => "cat", "from" => "nl", "to" => "en")
  end

  it "404s for another user's term" do
    other = create(:user)
    get "/api/v1/terms/#{term.id}", headers: auth_headers(other)
    expect(response).to have_http_status(:not_found)
  end

  describe "PATCH ease" do
    it "nudges ease and returns it" do
      patch "/api/v1/terms/#{term.id}/ease",
            params: { ease: 5, from: "nl", to: "en" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["ease"]).to eq(5)
      expect(user.schedulings.find_by(term: term, from_language: "nl", to_language: "en").ease).to eq(5)
    end
  end

  describe "PATCH unretire" do
    it "unretires an existing scheduling row" do
      sched = create(:scheduling, user: user, term: term,
                     from_language: "nl", to_language: "en",
                     stability: Mastery::RETIRE_STABILITY_DAYS + 50, reps: 5)
      patch "/api/v1/terms/#{term.id}/unretire", headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["unretired"]).to eq(true)
      expect(sched.reload.stability).to be < Mastery::RETIRE_STABILITY_DAYS
    end
  end
end
