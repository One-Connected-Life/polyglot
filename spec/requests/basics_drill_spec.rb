require "rails_helper"

# Contract for the "Basics" category: the home index and the virtual `deck=basics`
# drill scope must serve 200 (not 500) once Basics decks exist. The scope aggregates
# every "Basics: *" deck and, unlike `deck=all`, includes verb phrases (kind: "phrase").
RSpec.describe "Basics drill scope", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  before do
    verbs = create(:deck, user: user, name: "Basics: Verbs")
    pron  = create(:deck, user: user, name: "Basics: Pronouns")

    eat = create(:term, deck: verbs, kind: "phrase", key: "verbs/i-eat")
    create(:translation, term: eat, language: "nl", text: "ik eet")
    create(:translation, term: eat, language: "en", text: "I eat")

    i = create(:term, deck: pron, kind: "word", key: "pronouns/i")
    create(:translation, term: i, language: "nl", text: "ik")
    create(:translation, term: i, language: "en", text: "I")

    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "renders the home index with Basics decks present" do
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "serves the aggregate Basics drill (deck=basics)" do
    get play_path(deck: "basics", from: "nl", to: "en")
    expect(response).to have_http_status(:ok)
  end
end
