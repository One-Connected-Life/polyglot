require "rails_helper"

# Contract for "add more words to an existing deck" — generates a fresh cohort in the
# background; the deck stays drillable, new words land reviewed: false to await review.
RSpec.describe "Deck expand", type: :request do
  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, topic: "technical", status: "ready") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  before { sign_in(user) }

  it "queues an append job, flags the deck expanding, and counts a generation" do
    expect {
      post expand_deck_path(deck)
    }.to have_enqueued_job(ExpandDeckJob).and change { user.reload.generations_count }.by(1)

    expect(deck.reload.expanding).to be(true)
    expect(response).to redirect_to(root_path)
  end

  it "refuses to expand a deck with no topic (e.g. an audio deck)" do
    audio = create(:deck, user: user, topic: nil, status: "ready", slug: "voicemail")
    expect { post expand_deck_path(audio) }.not_to have_enqueued_job(ExpandDeckJob)
    expect(audio.reload.expanding).to be(false)
  end

  it "won't double-queue while a deck is already expanding" do
    deck.update!(expanding: true)
    expect { post expand_deck_path(deck) }.not_to have_enqueued_job(ExpandDeckJob)
  end

  it "blocks expansion once the generation cap is reached" do
    user.update!(generations_count: User::GENERATION_CAP)
    expect { post expand_deck_path(deck) }.not_to have_enqueued_job(ExpandDeckJob)
    expect(deck.reload.expanding).to be(false)
  end
end
