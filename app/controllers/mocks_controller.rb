class MocksController < ApplicationController
  # Owner-only design mocks (merged from the four differentiator mock agents,
  # issue #5). This app has no admin flag and we don't want a migration for a
  # mock, so we gate on "first user = the owner" — the lightweight solo-app
  # pattern. All pages carry stub data and no live behavior. Swap for a real
  # admin? if/when one lands.
  before_action :require_owner
  skip_before_action :require_onboarding

  # Slug-based mocks, rendered via show -> _<slug> partial.
  MOCKS = {
    "multi-language-drill" => "Multi-language drill — one concept, several tongues",
    "etymology-mnemonic" => "Etymology & memory hook on the reveal card",
  }.freeze

  # Mocks with their own stub data live in dedicated actions: slug => title.
  EXTRA = {
    "phonetics" => "Phonetic transcription — IPA / romanized / native toggle",
    "retire" => "Retire & celebrate — the mastery moment",
  }.freeze

  # Stub word for the phonetics mock, shaped like a drill card so the real
  # partials could consume it once Translation grows a `phonetics` column.
  SAMPLE = {
    prompt: "het brood",
    answer: "bread",
    from_name: "Dutch",
    to_name: "English",
    phonetics: {
      "ipa" => "ɦət broːt",
      "romanized" => "huht broht",
      "native" => "het brood",
    },
    others: [
      { prompt: "хлеб", from_name: "Russian", phonetics: { "ipa" => "xlʲep", "romanized" => "khlyep", "native" => "хлеб" } },
      { prompt: "le pain", from_name: "French", phonetics: { "ipa" => "lə pɛ̃", "romanized" => "luh pan", "native" => "le pain" } },
    ],
  }.freeze

  # Stub words for the retire-and-celebrate mock, shaped like drill cards.
  RETIRE_SAMPLE = {
    just_retired: { word: "het brood", gloss: "bread", stability_days: 184 },
    shelf: [
      { word: "de hond", gloss: "dog", stability_days: 372, retired_on: "3 weeks ago" },
      { word: "water", gloss: "water", stability_days: 610, retired_on: "2 months ago" },
      { word: "het huis", gloss: "house", stability_days: 240, retired_on: "5 weeks ago" },
      { word: "danken", gloss: "to thank", stability_days: 198, retired_on: "6 days ago" },
    ],
    approaching: [
      { word: "de fiets", gloss: "bicycle", stability_days: 142 },
      { word: "morgen", gloss: "morning", stability_days: 96 },
    ],
  }.freeze

  def index
    @mocks = MOCKS
    @extra = EXTRA
  end

  def show
    @slug = params[:slug]
    head :not_found unless MOCKS.key?(@slug)
  end

  def phonetics
    @sample = SAMPLE
  end

  def retire_celebrate
    @sample = RETIRE_SAMPLE
    @retire_threshold = 180 # Mastery::RETIRE_STABILITY_DAYS, inlined for the mock
  end

  private

  def require_owner
    head :forbidden unless current_user && current_user == User.order(:id).first
  end
end
