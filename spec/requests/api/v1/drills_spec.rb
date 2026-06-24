require "rails_helper"

# GET /api/v1/drills/play — { cards: [...], sentences: [...] }. Cards must match
# the web build_card / build_multi_card shape exactly.
RSpec.describe "Api::V1 drills", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "ready") }
  let!(:term) { create(:term, deck: deck, kind: "word", reviewed: true) }

  before do
    create(:translation, term: term, language: "nl", text: "hond", article: "de")
    create(:translation, term: term, language: "en", text: "dog")
  end

  it "401s without a token" do
    get "/api/v1/drills/play"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns cards in the build_card shape (nl→en)" do
    get "/api/v1/drills/play", params: { deck: "all", from: "nl", to: "en" }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)

    expect(json).to have_key("cards")
    expect(json).to have_key("sentences")

    card = json["cards"].find { |c| c["id"] == term.id }
    expect(card).to include(
      "id"      => term.id,
      "kind"    => "word",
      "prompt"  => "de hond",
      "answer"  => "dog",
      "accept"  => ["dog"],
    )
    # card carries the full keyset the web emits
    %w[prompt_ipa prompt_translit prompt_non_latin answer_article
       answer_ipa answer_translit answer_non_latin difficulty
       etymology mnemonic translations ease].each do |key|
      expect(card).to have_key(key)
    end
    expect(card["translations"]).to include({ "lang" => "en", "text" => "dog" })
  end

  it "returns a multi card when multi=1 and the user has 2+ targets" do
    user.update!(learning_languages: %w[nl es], target_language: "nl")
    create(:translation, term: term, language: "es", text: "perro")

    get "/api/v1/drills/play",
        params: { from: "en", to: "nl", multi: "1", targets: "nl,es" },
        headers: auth_headers(user)
    expect(response).to have_http_status(:ok)

    card = json["cards"].find { |c| c["id"] == term.id }
    expect(card["kind"]).to eq("multi")
    expect(card["targets"].map { |t| t["lang"] }).to match_array(%w[nl es])
    expect(card["targets"].find { |t| t["lang"] == "es" }).to include("answer" => "perro")
  end
end
