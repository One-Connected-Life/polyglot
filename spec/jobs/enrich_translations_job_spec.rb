require "rails_helper"

RSpec.describe EnrichTranslationsJob do
  def canned(array)
    { "content" => [{ "type" => "text", "text" => JSON.generate(array) }] }
  end

  let(:user) { create(:user, target_language: "nl", source_language: "en") }
  let(:deck) { create(:deck, user: user, status: "ready") }

  def captured_word(nl, en, article: nil)
    term = create(:term, deck: deck, reviewed: true)
    create(:translation, term: term, language: "nl", text: nl, article: article)
    create(:translation, term: term, language: "en", text: en)
    term
  end

  it "adds the missing languages onto each captured word" do
    term = captured_word("brood", "bread", article: "het")

    allow_any_instance_of(EnrichTranslationsJob).to receive(:post_message).and_return(canned([
      { "word" => "brood", "translations" => {
        "es" => { "text" => "pan", "ipa" => "pan", "translit" => nil },
        "fr" => { "text" => "pain", "ipa" => "pɛ̃", "translit" => nil },
        "it" => { "text" => "pane" }, "ro" => { "text" => "pâine" },
        "ru" => { "text" => "хлеб", "ipa" => "xlʲep", "translit" => "khleb" }
      } }
    ]))

    EnrichTranslationsJob.perform_now([term.id])
    term.reload

    expect(term.translation("es").text).to eq("pan")
    expect(term.translation("fr").ipa).to eq("pɛ̃")
    expect(term.translation("ru").text).to eq("хлеб")
    expect(term.translation("ru").translit).to eq("khleb")   # non-Latin gets translit
    # nl + en already existed + 5 new = 7
    expect(term.translations.count).to eq(7)
  end

  it "does not duplicate languages a term already has" do
    term = captured_word("brood", "bread")

    allow_any_instance_of(EnrichTranslationsJob).to receive(:post_message).and_return(canned([
      { "word" => "brood", "translations" => { "en" => { "text" => "loaf" }, "es" => { "text" => "pan" } } }
    ]))

    EnrichTranslationsJob.perform_now([term.id])
    term.reload

    expect(term.translation("en").text).to eq("bread")       # original en untouched
    expect(term.translation("es").text).to eq("pan")
  end

  it "swallows API errors (best-effort dormant data)" do
    term = captured_word("brood", "bread")
    allow_any_instance_of(EnrichTranslationsJob).to receive(:post_message).and_raise(StandardError, "boom")

    expect { EnrichTranslationsJob.perform_now([term.id]) }.not_to raise_error
    expect(term.reload.translations.count).to eq(2)          # unchanged
  end

  it "no-ops on empty term list" do
    expect_any_instance_of(EnrichTranslationsJob).not_to receive(:post_message)
    expect { EnrichTranslationsJob.perform_now([]) }.not_to raise_error
  end
end
