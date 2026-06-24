require "rails_helper"

# Contract for the audio-deck review step (issue #3): prune/edit candidates, then
# promote the deck to drillable. Also asserts un-reviewed terms stay out of practice.
RSpec.describe "Deck review", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, name: "Voicemail", status: "review") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def candidate(nl, en)
    term = create(:term, deck: deck)
    create(:translation, term: term, language: "nl", text: nl)
    create(:translation, term: term, language: "en", text: en)
    term
  end

  before { sign_in(user) }

  it "renders the review page without error for a deck awaiting review" do
    term = candidate("afspraak", "appointment")
    term.translation("nl").update!(article: "de", etymology: "af + spraak", phonetics: { ipa: "ˈɑfspraːk" }.to_json)

    get review_deck_path(deck)

    # 200 (not a 500) confirms review.html.erb rendered the rich term data without raising.
    expect(response).to have_http_status(:ok)
  end

  it "keeps checked terms, drops the rest, and makes the deck drillable" do
    keep = candidate("afspraak", "appointment")
    drop = candidate("gelderland", "(noise)")

    patch review_deck_path(deck), params: { keep: [keep.id.to_s] }

    expect(deck.reload.status).to eq("ready")
    expect(Term.exists?(keep.id)).to be(true)
    expect(Term.exists?(drop.id)).to be(false)
    expect(response).to redirect_to(play_path(deck: deck.slug, from: "en", to: "nl"))
  end

  it "applies edits to a kept term's translations" do
    term = candidate("afsprak", "appointmnt")

    patch review_deck_path(deck), params: {
      keep: [term.id.to_s],
      terms: { term.id.to_s => { target: "afspraak", source: "appointment" } }
    }

    expect(term.translation("nl").reload.text).to eq("afspraak")
    expect(term.translation("en").reload.text).to eq("appointment")
  end

  it "discards the deck when nothing is kept" do
    candidate("afspraak", "appointment")
    patch review_deck_path(deck), params: { keep: [] }

    expect(Deck.exists?(deck.id)).to be(false)
    expect(response).to redirect_to(root_path)
  end

  it "does not let a review-status deck's words leak into the drill pool" do
    candidate("afspraak", "appointment")
    expect(user.terms.drillable.count).to eq(0)

    patch review_deck_path(deck), params: { keep: user.terms.pluck(:id).map(&:to_s) }
    expect(user.terms.drillable.count).to eq(1)
  end

  it "won't review a deck that isn't awaiting review" do
    deck.update!(status: "ready")
    get review_deck_path(deck)
    expect(response).to redirect_to(root_path)
  end

  context "reviewing a fresh cohort appended to an already-drillable deck" do
    let(:deck) { create(:deck, user: user, name: "Technical", topic: "technical", status: "ready") }

    def reviewed_word(nl, en)
      candidate(nl, en).tap { |t| t.update!(reviewed: true) }
    end

    def appended_word(nl, en)
      candidate(nl, en).tap { |t| t.update!(reviewed: false) }
    end

    it "reviews only the new cohort and leaves existing drilling words untouched" do
      old  = reviewed_word("computer", "computer")
      keep = appended_word("toetsenbord", "keyboard")
      drop = appended_word("ruis", "(noise)")

      # Drill pool sees only the already-reviewed word while the cohort is pending.
      expect(user.terms.drillable.pluck(:id)).to eq([old.id])

      patch review_deck_path(deck), params: { keep: [keep.id.to_s] }

      expect(deck.reload.status).to eq("ready")
      expect(Term.exists?(old.id)).to be(true)   # never offered for deletion
      expect(Term.exists?(keep.id)).to be(true)
      expect(Term.exists?(drop.id)).to be(false)
      expect(keep.reload.reviewed).to be(true)
      expect(user.terms.drillable.pluck(:id)).to match_array([old.id, keep.id])
    end
  end
end
