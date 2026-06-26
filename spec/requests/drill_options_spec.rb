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
    # The drill header no longer prints "Dutch → English" (cluster moved to
    # Settings); direction now shows on the card itself — the answer input's
    # placeholder is the TO language ("english…" for NL→EN, "dutch…" for EN→NL).
    it "defaults bare /play to the recall-first direction (target→source, NL→EN)" do
      # New users default to recall_first = true (recognition, the easier path).
      expect(user.drill_recall_first).to be(true)
      get play_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('placeholder="english…"')
      expect(response.body).not_to include('placeholder="dutch…"')
    end

    it "respects a saved production preference (source→target, EN→NL)" do
      user.update!(drill_recall_first: false)
      get play_path
      expect(response.body).to include('placeholder="dutch…"')
    end

    it "lets an explicit from/to override the saved default for that request" do
      get play_path(from: "en", to: "nl")  # explicit EN→NL (swap), overrides recall-first
      expect(response.body).to include('placeholder="dutch…"')
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

  describe "show_other_languages gates the card reveal panel, not just the weave" do
    before do
      deck = Deck.find_by(user: user)
      t = create(:term, deck: deck, kind: "word", reviewed: true)
      create(:translation, term: t, language: "nl", text: "hond")
      create(:translation, term: t, language: "en", text: "dog")
      create(:translation, term: t, language: "es", text: "perro") # an OTHER language
    end

    it "omits other-language translations from the card when the toggle is OFF" do
      user.update!(show_other_languages: false)
      get play_path
      expect(response.body).not_to include("perro")
    end

    it "includes other-language translations when the toggle is ON" do
      user.update!(show_other_languages: true)
      get play_path
      expect(response.body).to include("perro")
    end
  end

  describe "FSRS-superseded toggles are greyed out, not silently dead" do
    it "leaves skip_easy/hide_mastered interactive when FSRS is off (legacy path)" do
      get onboarding_path
      expect(response.body).not_to include("Handled automatically")
    end

    context "with FSRS_ENABLED=1 (the live prod path)" do
      around do |example|
        old = ENV["FSRS_ENABLED"]
        ENV["FSRS_ENABLED"] = "1"
        example.run
        old.nil? ? ENV.delete("FSRS_ENABLED") : ENV["FSRS_ENABLED"] = old
      end

      it "greys out both toggles with an explanation that FSRS handles them" do
        get onboarding_path
        # one caption per superseded toggle
        expect(response.body.scan("Handled automatically").size).to eq(2)
        # the inputs are disabled so they can't masquerade as live controls
        expect(response.body).to include('disabled="disabled"')
      end
    end
  end

  describe "no keyboard hints inside the native iOS app (touch, no keyboard)" do
    it "shows keyboard hints (Space / Enter) on the web" do
      get play_path
      expect(response.body).to include("Space")
    end

    it "omits keyboard hints in the Hotwire Native shell" do
      get play_path, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }
      expect(response.body).not_to include("Space")
    end
  end

  describe "flow mode — hands-free listen (hear prompt, gap, hear answer, gap, next)" do
    it "defaults flow_mode OFF with 3s / 6s gaps for a new user" do
      expect(user.flow_mode?).to be(false)
      expect(user.flow_gap_prompt).to eq(3)
      expect(user.flow_gap_next).to eq(6)
    end

    it "carries the saved flow prefs into the drill controller dataset" do
      user.update!(flow_mode: true, flow_gap_prompt: 5, flow_gap_next: 7)
      get play_path
      expect(response.body).to include('data-drill-flow-mode-value="true"')
      expect(response.body).to include('data-drill-flow-gap-prompt-value="5"')
      expect(response.body).to include('data-drill-flow-gap-next-value="7"')
    end

    it "defaults the flow dataset to off / 3 / 6 for a new user" do
      get play_path
      expect(response.body).to include('data-drill-flow-mode-value="false"')
      expect(response.body).to include('data-drill-flow-gap-prompt-value="3"')
      expect(response.body).to include('data-drill-flow-gap-next-value="6"')
    end

    it "forces the single-language card (no weave) when flow mode is on" do
      # Even with the weave opted in, flow mode runs single-card.
      user.update!(show_other_languages: true, learning_languages: %w[nl es], flow_mode: true)
      get play_path
      expect(response.body).not_to include("multiCard")
    end

    it "persists the flow prefs through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"],
                flow_mode: "1", flow_gap_prompt: "4", flow_gap_next: "8" }
      }
      user.reload
      expect(user.flow_mode?).to be(true)
      expect(user.flow_gap_prompt).to eq(4)
      expect(user.flow_gap_next).to eq(8)
    end

    it "rejects out-of-range gaps (keeps timings sane)" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], flow_gap_prompt: "999" }
      }
      expect(user.reload.flow_gap_prompt).to eq(3) # unchanged — validation blocked it
    end

    it "exposes a Flow mode control on the Settings page" do
      get onboarding_path
      expect(response.body).to include("Flow mode")
    end
  end

  describe "answer mode — type vs speak the answer aloud" do
    it "defaults answer_mode to 'type' for a new user" do
      expect(user.answer_mode).to eq("type")
    end

    it "carries the saved answer_mode into the drill controller dataset" do
      get play_path
      expect(response.body).to include('data-drill-answer-mode-value="type"')
    end

    it "carries a saved 'speak' answer_mode into the drill dataset" do
      user.update!(answer_mode: "speak")
      get play_path
      expect(response.body).to include('data-drill-answer-mode-value="speak"')
    end

    it "persists the answer_mode pref through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], answer_mode: "speak" }
      }
      expect(user.reload.answer_mode).to eq("speak")
    end

    it "rejects an invalid answer_mode (keeps it sane)" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], answer_mode: "telepathy" }
      }
      expect(user.reload.answer_mode).to eq("type")
    end

    it "exposes an 'Answer by' control on the Settings page" do
      get onboarding_path
      expect(response.body).to include("Answer by")
    end
  end

  describe "correct-answer audio feedback (no longer silent on correct)" do
    it "defaults to 'word' (an enthusiastic Yes!)" do
      expect(user.correct_feedback).to eq("word")
    end

    it "carries the saved choice into the drill dataset" do
      user.update!(correct_feedback: "sound")
      get play_path
      expect(response.body).to include('data-drill-correct-feedback-value="sound"')
    end

    it "ships the English word on each card for the 'speak the answer' option" do
      get play_path
      # card JSON is HTML-escaped inside the data attribute (" -> &quot;)
      expect(response.body).to include("&quot;english&quot;")
    end

    it "persists the choice through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], correct_feedback: "none" }
      }
      expect(user.reload.correct_feedback).to eq("none")
    end

    it "exposes the 'On a correct answer' control on the Settings page" do
      get onboarding_path
      expect(response.body).to include("On a correct answer")
    end
  end

  describe "Flow teaches on the answer beat (etymology + phonetics)" do
    it "defaults flow_teach ON for a new user" do
      expect(user.flow_teach?).to be(true)
    end

    it "carries flow_teach=true into the drill dataset by default" do
      get play_path
      expect(response.body).to include('data-drill-flow-teach-value="true"')
    end

    it "reflects flow_teach=false in the drill dataset when turned off" do
      user.update!(flow_teach: false)
      get play_path
      expect(response.body).to include('data-drill-flow-teach-value="false"')
    end

    it "persists the flow_teach pref through Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], flow_teach: "0" }
      }
      expect(user.reload.flow_teach?).to be(false)
    end

    it "exposes the 'Show etymology & phonetics in Flow' control on the Settings page" do
      get onboarding_path
      expect(response.body).to include("Show etymology")
    end
  end

  describe "pronunciation is first-class — autoplay_prompt defaults ON (review 13)" do
    it "defaults autoplay_prompt ON for a new user" do
      expect(user.autoplay_prompt?).to be(true)
    end

    it "carries autoplay_prompt=true into the drill dataset by default" do
      get play_path
      expect(response.body).to include('data-drill-autoplay-prompt-value="true"')
    end

    it "still lets the user turn it off in Settings" do
      patch onboarding_path, params: {
        user: { source_language: "en", learning_languages: ["", "nl"], autoplay_prompt: "0" }
      }
      expect(user.reload.autoplay_prompt?).to be(false)
    end
  end
end
