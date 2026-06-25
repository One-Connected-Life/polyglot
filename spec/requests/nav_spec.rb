require "rails_helper"

# Contract for the nav-rework tab pages (web side): the Add hub launcher, and the
# My Words (/stats) segmented filter. Request spec = HTTP status + key content/links.
RSpec.describe "Nav rework", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  before { sign_in(user) }

  describe "Add hub (/add)" do
    it "renders and links to the deck-creation flows" do
      get add_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(new_deck_path)
      expect(response.body).to include(new_audio_deck_path)
    end
  end

  describe "Drill straight-in (/play)" do
    it "starts an all-words drill with no params (always available)" do
      deck = create(:deck, user: user, status: "ready")
      term = create(:term, deck: deck, kind: "word", reviewed: true)
      create(:translation, term: term, language: "nl", text: "brood")
      create(:translation, term: term, language: "en", text: "bread")

      get play_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "My Words segmented filter (/stats)" do
    before do
      @deck = create(:deck, user: user, status: "ready")
      # An owned word (2 correct) and a learning word (1 correct, 1 wrong).
      @owned = create(:term, deck: @deck, kind: "word", reviewed: true)
      create(:translation, term: @owned, language: "nl", text: "brood")
      create(:translation, term: @owned, language: "en", text: "bread")
      2.times { create(:attempt, user: user, term: @owned, from_language: "nl", to_language: "en", correct: true) }

      @learning = create(:term, deck: @deck, kind: "word", reviewed: true)
      create(:translation, term: @learning, language: "nl", text: "kaas")
      create(:translation, term: @learning, language: "en", text: "cheese")
      create(:attempt, user: user, term: @learning, from_language: "nl", to_language: "en", correct: true)
      create(:attempt, user: user, term: @learning, from_language: "nl", to_language: "en", correct: false)
    end

    it "defaults to All and shows every active word" do
      get stats_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("brood")
      expect(response.body).to include("kaas")
    end

    it "Learning renders and includes a not-yet-owned word" do
      get stats_path(seg: "learning")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("kaas")     # learning word present
    end

    it "Retired renders without error (empty shelf when nothing retired)" do
      get stats_path(seg: "retired")
      expect(response).to have_http_status(:ok)
    end

    it "ignores an invalid filter and falls back to All" do
      get stats_path(seg: "bogus")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("brood")
    end
  end
end
