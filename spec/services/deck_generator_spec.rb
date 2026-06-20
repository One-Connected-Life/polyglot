require "rails_helper"

RSpec.describe DeckGenerator do
  def canned(words)
    { "content" => [{ "type" => "text", "text" => JSON.generate(words) }] }
  end

  it "persists words in the user's target+source languages, stripping doubled articles" do
    user = create(:user, target_language: "fr", source_language: "en")
    deck = create(:deck, user: user, topic: "cooking", status: "pending")

    allow_any_instance_of(DeckGenerator).to receive(:post_message).and_return(canned([
      { "target" => "la cuisine", "article" => "la", "source" => "kitchen" },
      { "target" => "couteau", "article" => "le", "source" => "knife" },
      { "target" => "", "article" => nil, "source" => "skip me" }
    ]))

    DeckGenerator.new(deck).call
    deck.reload

    expect(deck.status).to eq("ready")
    expect(deck.terms.count).to eq(2) # blank target skipped

    cuisine = deck.terms.order(:position).first.translation("fr")
    expect(cuisine.text).to eq("cuisine")          # "la " stripped from the bare word
    expect(cuisine.with_article).to eq("la cuisine")
    expect(deck.terms.order(:position).first.translation("en").text).to eq("kitchen")
  end

  it "stores etymology and mnemonic on the target translation when the model returns them" do
    user = create(:user, target_language: "nl", source_language: "en")
    deck = create(:deck, user: user, topic: "health", status: "pending")

    allow_any_instance_of(DeckGenerator).to receive(:post_message).and_return(canned([
      { "target" => "ziekenhuis", "article" => "het", "source" => "hospital",
        "etymology" => "ziek (sick) + huis (house)", "mnemonic" => "a house for the sick" },
      { "target" => "tafel", "article" => "de", "source" => "table",
        "etymology" => nil, "mnemonic" => "" } # blanks must not persist as empty strings
    ]))

    DeckGenerator.new(deck).call

    nl_first = deck.terms.order(:position).first.translation("nl")
    expect(nl_first.etymology).to eq("ziek (sick) + huis (house)")
    expect(nl_first.mnemonic).to eq("a house for the sick")

    nl_second = deck.terms.order(:position).second.translation("nl")
    expect(nl_second.etymology).to be_nil
    expect(nl_second.mnemonic).to be_nil

    # The source-language row never carries lore — it's a property of the word being learned.
    expect(deck.terms.order(:position).first.translation("en").etymology).to be_nil
  end

  it "marks the deck failed and re-raises on API error" do
    deck = create(:deck, status: "pending")
    allow_any_instance_of(DeckGenerator).to receive(:post_message).and_raise(DeckGenerator::Error, "boom")

    expect { DeckGenerator.new(deck).call }.to raise_error(DeckGenerator::Error)
    expect(deck.reload.status).to eq("failed")
  end
end
