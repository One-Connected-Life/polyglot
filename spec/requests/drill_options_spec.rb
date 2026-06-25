require "rails_helper"

# Finding A: the drill options cluster moved off the play screen into Settings,
# and the options are now persisted per-user (not session/localStorage).
RSpec.describe "Drill options relocation (Finding A)", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  before do
    sign_in(user)
    deck = create(:deck, user: user, status: "ready")
    term = create(:term, deck: deck, kind: "word", reviewed: true)
    create(:translation, term: term, language: "nl", text: "brood")
    create(:translation, term: term, language: "en", text: "bread")
  end

  it "no longer renders the old top option cluster on the drill screen" do
    get play_path
    expect(response).to have_http_status(:ok)
    # The old toggle labels lived in the drill header; they belong in Settings now.
    expect(response.body).not_to include("easy cognates: shown")
    expect(response.body).not_to include("mastered: shown")
    expect(response.body).not_to include("auto-play prompt")
    expect(response.body).not_to include("read answer if wrong")
  end

  it "carries the user's saved autoplay prefs into the drill controller dataset" do
    user.update!(autoplay_prompt: true, autoplay_wrong: true)
    get play_path
    expect(response.body).to include('data-drill-autoplay-prompt-value="true"')
    expect(response.body).to include('data-drill-autoplay-wrong-value="true"')
  end

  it "still honors a skip_easy URL param by persisting it to the user" do
    expect { get play_path(skip_easy: "1") }
      .to change { user.reload.skip_easy? }.from(false).to(true)
  end

  describe "single-language is the default; weave is opt-in (#fix-1)" do
    it "defaults show_other_languages to OFF for a new user" do
      expect(user.show_other_languages?).to be(false)
    end

    it "renders the single-language card (not the weave) by default" do
      get play_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("multiCard")
    end

    it "persists the show_other_languages pref through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], show_other_languages: "1" }
      }
      expect(user.reload.show_other_languages?).to be(true)
    end

    it "exposes a Show other languages toggle on the Settings page" do
      get onboarding_path
      expect(response.body).to include("Show other languages")
    end
  end

  describe "default direction is a respected Settings preference (coordinator add)" do
    it "defaults bare /play to the recall-first direction (target→source, NL→EN)" do
      # New users default to recall_first = true (recognition, the easier path).
      expect(user.drill_recall_first).to be(true)
      get play_path
      expect(response).to have_http_status(:ok)
      # The drill header shows the resolved direction; NL→EN, not EN→NL.
      expect(response.body).to include("Dutch → English")
      expect(response.body).not_to include("English → Dutch")
    end

    it "respects a saved production preference (source→target, EN→NL)" do
      user.update!(drill_recall_first: false)
      get play_path
      expect(response.body).to include("English → Dutch")
    end

    it "lets an explicit from/to override the saved default for that request" do
      get play_path(from: "en", to: "nl")  # explicit EN→NL (swap), overrides recall-first
      expect(response.body).to include("English → Dutch")
    end

    it "persists the direction pref through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], drill_recall_first: "false" }
      }
      expect(user.reload.drill_recall_first).to be(false)
    end
  end

  describe "interleaved sentences are a respected Settings toggle" do
    before do
      s = create(:term, deck: Deck.find_by(user: user), kind: "sentence", reviewed: true)
      create(:translation, term: s, language: "nl", text: "Ik eet brood.")
      create(:translation, term: s, language: "en", text: "I eat bread.")
    end

    it "defaults drill_sentences ON for a new user" do
      expect(user.drill_sentences?).to be(true)
    end

    it "sprinkles sentence cards into the drill by default" do
      get play_path
      expect(response.body).not_to include('data-drill-sentences-value="[]"')
    end

    it "omits sentence cards when the user turns interleaving off" do
      user.update!(drill_sentences: false)
      get play_path
      expect(response.body).to include('data-drill-sentences-value="[]"')
    end

    it "persists the drill_sentences pref through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], drill_sentences: "0" }
      }
      expect(user.reload.drill_sentences?).to be(false)
    end

    it "exposes an Interleave sentences toggle on the Settings page" do
      get onboarding_path
      expect(response.body).to include("Interleave sentences")
    end
  end
end
