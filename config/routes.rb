Rails.application.routes.draw do
  resource :session
  resource :registration, only: [:new, :create]
  resources :passwords, param: :token

  get "onboarding", to: "onboarding#show"
  patch "onboarding", to: "onboarding#update"

  get "up" => "rails/health#show", as: :rails_health_check

  # Transcription stack sanity check (issue 3) — hittable over HTTP so prod can be
  # verified without a container shell. ?deep=1 runs a real end-to-end transcription.
  get "up/audio" => "audio_health#show", as: :audio_health

  # PWA manifest (add-to-home-screen). Renders app/views/pwa/manifest.json.erb.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  root "drills#home"

  # The drill runner: ?deck=<slug|all|misses>&from=<lang>&to=<lang>
  get "play", to: "drills#play", as: :play

  # Records one graded answer (fire-and-forget from the drill).
  post "attempts", to: "attempts#create"

  # Stable per-word page — reload to re-test pronunciation, see all languages.
  resources :terms, only: [:show]

  # FSRS hand-tweaks (#axis-4): un-retire a word from the /stats shelf, or nudge
  # its ease 1–5 mid-drill. Both keyed by term id (direction inferred / passed).
  patch "terms/:id/unretire", to: "schedulings#unretire", as: :unretire_term
  patch "terms/:id/ease",     to: "schedulings#nudge",     as: :ease_term

  # Every word + your attempt history (right/wrong) and status.
  get "stats", to: "stats#index"

  # AI-generate a deck from a topic, or remove one. Audio decks (issue #3) get a
  # review step before they go drillable.
  resources :decks, only: [:new, :create, :destroy] do
    member do
      get   :review
      patch :review, action: :update_review
    end
  end

  # Upload your own audio → extract a vocabulary deck (issue #3).
  resources :audio_decks, only: [:new, :create]

  # IPA cheat sheet — compact legend reachable from any drill card phonetic line.
  get "ipa-guide", to: "phonetics#guide", as: :ipa_guide

  # Owner-only design mocks for the four differentiators (issue #5). Stub data,
  # no live behavior. Specific routes BEFORE the :slug catch-all.
  get "mocks", to: "mocks#index", as: :mocks
  get "mocks/phonetics", to: "mocks#phonetics", as: :mock_phonetics
  get "mocks/retire", to: "mocks#retire_celebrate", as: :mock_retire
  get "mocks/:slug", to: "mocks#show", as: :mock
end
