require "rails_helper"

RSpec.describe Translator do
  def canned(words)
    { "content" => [{ "type" => "text", "text" => JSON.generate(words) }] }
  end

  let(:user) { create(:user, target_language: "nl", source_language: "en") }

  it "returns the model's word hashes for the entered text" do
    allow_any_instance_of(Translator).to receive(:post_message).and_return(canned([
      { "target" => "brood", "article" => "het", "source" => "bread", "ipa" => "broːt" },
      { "target" => "kaas", "article" => "de", "source" => "cheese" }
    ]))

    words = Translator.new(user, "brood, kaas").call

    expect(words.size).to eq(2)
    expect(words.first["source"]).to eq("bread")
    expect(words.first["ipa"]).to eq("broːt")
  end

  it "returns [] for blank input without calling the model" do
    expect_any_instance_of(Translator).not_to receive(:post_message)
    expect(Translator.new(user, "   ").call).to eq([])
  end

  it "caps the number of items returned" do
    many = Array.new(100) { |i| { "target" => "w#{i}", "source" => "t#{i}" } }
    allow_any_instance_of(Translator).to receive(:post_message).and_return(canned(many))

    expect(Translator.new(user, "long text").call.size).to eq(Translator::MAX_ITEMS)
  end

  it "raises Translator::Error on unparseable output" do
    allow_any_instance_of(Translator).to receive(:post_message)
      .and_return({ "content" => [{ "type" => "text", "text" => "not json" }] })

    expect { Translator.new(user, "hi").call }.to raise_error(Translator::Error)
  end
end
