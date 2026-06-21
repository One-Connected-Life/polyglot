require "rails_helper"

# DrillsController#play under FSRS (#5) — the product invariant:
# PRACTICE IS ALWAYS AVAILABLE. There is never "nothing to drill" because a word
# isn't "due"; FSRS orders, it does not gate. Only retired / cognate / archived
# words are held back. See memory language_app_practice_always_available.
RSpec.describe "Drill play (FSRS)", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user) }

  def word(nl:, en:)
    t = create(:term, deck: deck, kind: "word")
    create(:translation, term: t, language: "nl", text: nl)
    create(:translation, term: t, language: "en", text: en)
    t
  end

  around do |ex|
    old = ENV["FSRS_ENABLED"]; ENV["FSRS_ENABLED"] = "1"
    ex.run
    old.nil? ? ENV.delete("FSRS_ENABLED") : ENV["FSRS_ENABLED"] = old
  end

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "still drills a resting (not-due) word — never 'nothing to drill'" do
    w = word(nl: "fiets", en: "bicycle")
    # Resting: reviewed, due far in the future, but NOT retired.
    create(:scheduling, user: user, term: w, from_language: "nl", to_language: "en",
           state: 2, stability: 30.0, reps: 2, due: 60.days.from_now)

    get play_path(deck: "all", from: "nl", to: "en")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("fiets")
    expect(response.body).not_to include("Nothing to drill")
  end

  it "drills a direction that has no scheduling rows yet (en→nl)" do
    word(nl: "boom", en: "tree")
    # Rows only exist for nl→en after prior play; en→nl starts empty.
    get play_path(deck: "all", from: "en", to: "nl")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("tree") # prompt is the English word in en→nl
    expect(response.body).not_to include("Nothing to drill")
  end

  it "holds back retired, cognate, and archived words" do
    retired = word(nl: "huis", en: "house")
    cognate = word(nl: "appel", en: "apple")
    archived = word(nl: "kat", en: "cat")
    keep = word(nl: "vlinder", en: "butterfly")

    create(:scheduling, user: user, term: retired, from_language: "nl", to_language: "en",
           stability: 365.0, reps: 5) # retired
    create(:scheduling, user: user, term: cognate, from_language: "nl", to_language: "en", ease: 1)
    create(:scheduling, user: user, term: archived, from_language: "nl", to_language: "en", archived: true)

    get play_path(deck: "all", from: "nl", to: "en")

    expect(response.body).to include("vlinder")
    expect(response.body).not_to include("huis")
    expect(response.body).not_to include("appel")
    expect(response.body).not_to include("kat")
  end
end
