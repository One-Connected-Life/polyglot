require "rails_helper"

# /api/v1/decks — list, create (enqueues GenerateDeckJob), destroy, review, expand.
RSpec.describe "Api::V1 decks", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  it "401s without a token" do
    get "/api/v1/decks"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET index" do
    it "lists the user's decks" do
      deck = create(:deck, user: user, name: "Kitchen", status: "ready")
      get "/api/v1/decks", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      d = json["decks"].find { |x| x["id"] == deck.id }
      expect(d).to include("name" => "Kitchen", "slug" => deck.slug, "status" => "ready")
    end
  end

  describe "POST create" do
    it "creates a pending deck and enqueues GenerateDeckJob" do
      expect {
        post "/api/v1/decks", params: { deck: { topic: "cooking", label: "Kitchen" } },
             headers: auth_headers(user), as: :json
      }.to have_enqueued_job(GenerateDeckJob)
      expect(response).to have_http_status(:accepted)
      expect(json["deck"]).to include("name" => "Kitchen", "status" => "pending")
      expect(user.reload.generations_count).to eq(1)
    end

    it "422s on a blank topic" do
      post "/api/v1/decks", params: { deck: { topic: "  " } }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("topic_required")
    end
  end

  describe "DELETE destroy" do
    it "removes the deck" do
      deck = create(:deck, user: user, status: "ready")
      expect {
        delete "/api/v1/decks/#{deck.slug}", headers: auth_headers(user)
      }.to change(Deck, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET review" do
    it "returns the pending cohort" do
      deck = create(:deck, user: user, status: "review")
      term = create(:term, deck: deck, reviewed: false)
      create(:translation, term: term, language: "nl", text: "hond")
      create(:translation, term: term, language: "en", text: "dog")
      get "/api/v1/decks/#{deck.slug}/review", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["terms"].first).to include("target" => "hond", "source" => "dog")
    end
  end

  describe "PATCH review (apply)" do
    it "keeps kept terms, drops the rest, marks the deck ready" do
      deck = create(:deck, user: user, status: "review")
      keep_term = create(:term, deck: deck, reviewed: false)
      create(:translation, term: keep_term, language: "nl", text: "hond")
      create(:translation, term: keep_term, language: "en", text: "dog")
      drop_term = create(:term, deck: deck, reviewed: false)
      create(:translation, term: drop_term, language: "nl", text: "kat")
      create(:translation, term: drop_term, language: "en", text: "cat")

      patch "/api/v1/decks/#{deck.slug}/review",
            params: { keep: [keep_term.id] }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("saved")
      expect(deck.reload.status).to eq("ready")
      expect(Term.exists?(keep_term.id)).to be(true)
      expect(Term.exists?(drop_term.id)).to be(false)
    end
  end

  describe "POST expand" do
    it "enqueues ExpandDeckJob for a topic deck" do
      deck = create(:deck, user: user, status: "ready", topic: "cooking")
      expect {
        post "/api/v1/decks/#{deck.slug}/expand", headers: auth_headers(user), as: :json
      }.to have_enqueued_job(ExpandDeckJob)
      expect(response).to have_http_status(:accepted)
      expect(deck.reload.expanding).to be(true)
    end

    it "422s when the deck has no topic" do
      deck = create(:deck, user: user, status: "ready", topic: nil)
      post "/api/v1/decks/#{deck.slug}/expand", headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("deck_has_no_topic")
    end
  end
end
