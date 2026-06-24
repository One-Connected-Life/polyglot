require "rails_helper"

# Contract for the Translate-first home (issue #10): the HTTP behavior of translating
# entered text and capturing it into the rolling "My Words" deck. The translation itself
# (Translator) and enrichment (EnrichTranslationsJob) are stubbed/spec'd separately.
RSpec.describe "Translate", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def stub_translator(words)
    allow_any_instance_of(Translator).to receive(:call).and_return(words)
  end

  before { sign_in(user) }

  it "translates and captures a small batch straight into My Words (drillable)" do
    stub_translator([
      { "target" => "brood", "article" => "het", "source" => "bread", "ipa" => "broːt" },
      { "target" => "kaas", "article" => "de", "source" => "cheese" }
    ])

    expect {
      post translate_path, params: { text: "brood, kaas", capture: "1" }
    }.to have_enqueued_job(EnrichTranslationsJob)

    expect(response).to have_http_status(:ok)
    deck = user.decks.find_by(slug: User::MY_WORDS_SLUG)
    expect(deck).to be_present
    expect(deck.terms.count).to eq(2)
    expect(deck.terms.all?(&:reviewed)).to be(true)         # ≤9 → drillable now
    expect(user.terms.drillable.count).to eq(2)
    expect(deck.terms.first.translation("nl").text).to eq("brood")
    expect(deck.terms.first.translation("en").text).to eq("bread")
  end

  it "translates without capturing when the checkbox is off" do
    stub_translator([{ "target" => "brood", "source" => "bread" }])

    expect {
      post translate_path, params: { text: "brood", capture: "0" }
    }.not_to have_enqueued_job(EnrichTranslationsJob)

    expect(response).to have_http_status(:ok)
    expect(user.decks.find_by(slug: User::MY_WORDS_SLUG)).to be_nil
  end

  it "routes a big batch (10+) to the review screen as unreviewed" do
    big = Array.new(12) { |i| { "target" => "woord#{i}", "source" => "word#{i}" } }
    stub_translator(big)

    post translate_path, params: { text: "a lot of text", capture: "1" }

    deck = user.decks.find_by(slug: User::MY_WORDS_SLUG)
    expect(response).to redirect_to(review_deck_path(deck))
    expect(deck.terms.count).to eq(12)
    expect(deck.terms.none?(&:reviewed)).to be(true)        # awaits pruning
    expect(user.terms.drillable.count).to eq(0)
  end

  it "appends later captures into the same My Words deck, skipping dupes" do
    stub_translator([{ "target" => "brood", "source" => "bread" }])
    post translate_path, params: { text: "brood", capture: "1" }

    stub_translator([
      { "target" => "brood", "source" => "bread" },   # dupe → skipped
      { "target" => "melk", "source" => "milk" }
    ])
    post translate_path, params: { text: "brood, melk", capture: "1" }

    deck = user.decks.find_by(slug: User::MY_WORDS_SLUG)
    expect(user.decks.where(slug: User::MY_WORDS_SLUG).count).to eq(1)
    expect(deck.terms.count).to eq(2)
  end

  it "reads text from an uploaded image, then translates and captures it" do
    allow_any_instance_of(ImageReader).to receive(:call).and_return("brood")
    stub_translator([{ "target" => "brood", "source" => "bread" }])
    image = Rack::Test::UploadedFile.new(StringIO.new("imgbytes"), "image/jpeg", original_filename: "sign.jpg")

    post translate_path, params: { image: image, capture: "1" }

    expect(response).to have_http_status(:ok)
    deck = user.decks.find_by(slug: User::MY_WORDS_SLUG)
    expect(deck.terms.first.translation("nl").text).to eq("brood")
  end

  it "redirects home when no target-language text is found in the image" do
    allow_any_instance_of(ImageReader).to receive(:call).and_return("")
    image = Rack::Test::UploadedFile.new(StringIO.new("imgbytes"), "image/jpeg", original_filename: "blank.jpg")

    post translate_path, params: { image: image, capture: "1" }
    expect(response).to redirect_to(root_path)
  end

  it "redirects home with an alert on blank text" do
    post translate_path, params: { text: "  ", capture: "1" }
    expect(response).to redirect_to(root_path)
  end

  it "redirects home when there's nothing usable to translate" do
    stub_translator([])
    post translate_path, params: { text: "...", capture: "1" }
    expect(response).to redirect_to(root_path)
  end
end
