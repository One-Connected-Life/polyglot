require "rails_helper"

# Multi-language drill request specs.
# These are CONTRACT specs: assert HTTP status, redirects, JSON shape, auth.
# They do NOT assert rendered HTML (that belongs in feature specs).
RSpec.describe "Multi-language drill", type: :request do
  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def build_multi_user
    user = create(:user,
      source_language: "en",
      target_language: "nl",
      learning_languages: %w[nl es fr],
      drill_direction: "forward")
    deck  = create(:deck, user: user)
    term  = create(:term, deck: deck)
    create(:translation, term: term, language: "en", text: "bread")
    create(:translation, term: term, language: "nl", text: "brood")
    create(:translation, term: term, language: "es", text: "pan")
    create(:translation, term: term, language: "fr", text: "pain")
    user
  end

  describe "GET /play?multi=1" do
    it "redirects unauthenticated visitors" do
      get play_path(multi: "1")
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 200 for an authenticated multi-language user" do
      user = build_multi_user
      sign_in(user)
      get play_path(multi: "1", from: "en")
      expect(response).to have_http_status(:ok)
    end

    it "falls back to single-language when the user has only one learning language" do
      user = create(:user, source_language: "en", target_language: "nl")
      sign_in(user)
      get play_path(multi: "1", from: "en")
      # @multi will be false → renders single card, still 200
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("multiCard")
    end

    context "when user has multi-language configured" do
      it "includes multi-card JSON in the page" do
        user = build_multi_user
        sign_in(user)
        get play_path(multi: "1", from: "en")
        # JSON in data attributes is HTML-entity-escaped in the response body.
        expect(response.body).to include("kind")
        expect(response.body).to include("multi")
        expect(response.body).to include("targets")
        # The multi card DOM should be present.
        expect(response.body).to include("multiCard")
      end

      it "skips a concept when none of the learning languages have translations" do
        user = create(:user,
          source_language: "en",
          target_language: "nl",
          learning_languages: %w[nl es])
        deck = create(:deck, user: user)
        term = create(:term, deck: deck)
        create(:translation, term: term, language: "en", text: "hello")
        # No nl or es translations → concept skipped → nothing to drill
        sign_in(user)
        get play_path(multi: "1", from: "en")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Nothing to drill")
      end

      it "only includes targets for languages the concept HAS translations in" do
        user = create(:user,
          source_language: "en",
          target_language: "nl",
          learning_languages: %w[nl es fr])
        deck = create(:deck, user: user)
        term = create(:term, deck: deck)
        create(:translation, term: term, language: "en", text: "bread")
        create(:translation, term: term, language: "nl", text: "brood")
        # No es or fr translation — those targets should be skipped, not error
        sign_in(user)
        get play_path(multi: "1", from: "en")
        expect(response).to have_http_status(:ok)
        # The multi card DOM should be present (concept has at least 1 target).
        expect(response.body).to include("multiCard")
        # The data-attribute JSON is HTML-escaped; check the escaped form.
        expect(response.body).to include("&quot;lang&quot;:&quot;nl&quot;")
        expect(response.body).not_to include("&quot;lang&quot;:&quot;es&quot;")
        expect(response.body).not_to include("&quot;lang&quot;:&quot;fr&quot;")
      end
    end
  end

  describe "POST /attempts (multi-language recording)" do
    it "records one attempt per target language" do
      user = build_multi_user
      sign_in(user)
      term = user.terms.first

      expect {
        # Simulate two separate attempt records (nl and es targets)
        post attempts_path, params: { term_id: term.id, from: "en", to: "nl", correct: true, given: "brood" },
          as: :json
        post attempts_path, params: { term_id: term.id, from: "en", to: "es", correct: false, given: "pan wrong" },
          as: :json
      }.to change(Attempt, :count).by(2)

      nl_attempt = user.attempts.find_by(from_language: "en", to_language: "nl", term: term)
      es_attempt = user.attempts.find_by(from_language: "en", to_language: "es", term: term)

      expect(nl_attempt).to be_correct
      expect(es_attempt).not_to be_correct
    end

    it "returns JSON with correct_count and newly_owned" do
      user = build_multi_user
      sign_in(user)
      term = user.terms.first

      post attempts_path, params: { term_id: term.id, from: "en", to: "nl", correct: true, given: "brood" },
        as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("correct_count", "newly_owned")
    end
  end
end
