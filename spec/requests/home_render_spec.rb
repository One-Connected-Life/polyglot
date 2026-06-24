require "rails_helper"

# Guards the home view against render-time regressions (it 500s, not just fails a
# matcher, if a helper or partial breaks). Covers the deck table + add-more button.
RSpec.describe "Home render", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  before { sign_in(user) }

  it "renders a drillable topic deck with the add-more button and a pending cohort banner" do
    deck = create(:deck, user: user, name: "Technical", topic: "technical", status: "ready")

    drilling = create(:term, deck: deck, position: 1, reviewed: true)
    create(:translation, term: drilling, language: "nl", text: "computer")
    create(:translation, term: drilling, language: "en", text: "computer")

    pending = create(:term, deck: deck, position: 2, reviewed: false)
    create(:translation, term: pending, language: "nl", text: "toetsenbord")
    create(:translation, term: pending, language: "en", text: "keyboard")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("+ words")          # add-more entry point
    expect(response.body).to include("ready to review")  # pending-cohort banner
  end
end
