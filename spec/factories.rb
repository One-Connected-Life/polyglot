FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password" }
    name { "Test" }
    target_language { "nl" }
    source_language { "en" }
    learning_languages { nil }  # pass a Ruby Array (not .to_json) when overriding
    drill_direction { "forward" }
  end

  factory :deck do
    user
    sequence(:name) { |n| "Deck #{n}" }
  end

  factory :term do
    deck
    kind { "word" }
  end

  factory :translation do
    term
    language { "nl" }
    text { "woord" }
  end

  factory :attempt do
    user
    term
    from_language { "nl" }
    to_language { "en" }
    correct { true }
  end

  # FSRS scheduling cache row (#axis-4).
  factory :scheduling do
    user
    term
    from_language { "nl" }
    to_language   { "en" }
    ease          { 3 }
    state         { 0 }   # Fsrs::State::NEW
    stability     { 0.0 }
    difficulty    { 0.0 }
    backfilled    { false }
    archived      { false }
  end
end
