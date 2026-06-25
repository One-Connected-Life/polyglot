Rails.application.routes.draw do
  # Throwaway design preview — compare candidate iOS tab bars in the browser (no app build).
  get "design/tabs", to: "design#tabs"
  get "design/app",  to: "design#app"   # navigable 5-tab tree prototype

  resource :session
  resource :registration, only: [:new, :create]
  resources :passwords, param: :token

  # Social login (Google + Facebook) via OmniAuth. The provider kicks the flow off
  # at GET/POST /auth/:provider (handled by OmniAuth middleware), then redirects back
  # to this callback. Failures route to #omniauth_failure (see omniauth.rb).
  get  "/auth/:provider/callback", to: "sessions#omniauth", as: :omniauth_callback
  get  "/auth/failure",            to: "sessions#omniauth_failure"

  # iOS OAuth handoff (App A). Google blocks OAuth inside an embedded WKWebView,
  # so the native shell runs the flow in ASWebAuthenticationSession (Safari) and
  # bridges the result back via a one-time token. See IosOauthController.
  get "/ios/oauth_start",     to: "ios_oauth#start",   as: :ios_oauth_start
  get "/ios/session_handoff", to: "ios_oauth#handoff", as: :ios_session_handoff

  get "onboarding", to: "onboarding#show"
  patch "onboarding", to: "onboarding#update"

  # ── Versioned JSON API for native clients (iOS/Android) ─────────────────────
  # Token auth (Authorization: Bearer <session.api_token>), not the cookie flow.
  # Mirrors the web controllers exactly — same models, same services, same shapes.
  namespace :api do
    namespace :v1 do
      post   "sessions",      to: "sessions#create"   # email_address + password → { token, user }
      delete "session",       to: "sessions#destroy"  # revoke the bearer token
      post   "registrations", to: "registrations#create"

      get   "me",         to: "me#show"
      patch "onboarding", to: "onboarding#update"

      get  "drills/play", to: "drills#play"
      post "attempts",    to: "attempts#create"
      get  "stats",       to: "stats#index"

      resources :terms, only: [:show] do
        member do
          patch :ease
          patch :unretire
        end
      end

      resources :decks, only: [:index, :create, :destroy] do
        member do
          get   :review
          patch :review, action: :update_review
          post  :expand
        end
      end

      resources :audio_decks, only: [:create]

      get "languages", to: "languages#index"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Transcription stack sanity check (issue 3) — hittable over HTTP so prod can be
  # verified without a container shell. ?deep=1 runs a real end-to-end transcription.
  get "up/audio" => "audio_health#show", as: :audio_health

  # PWA manifest (add-to-home-screen). Renders app/views/pwa/manifest.json.erb.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  root "drills#home"

  # Translate-first home (issue #10): translate target-lang text → source, optionally
  # capturing the words into the rolling "My Words" deck.
  post "translate", to: "translate#create", as: :translate

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
      post  :expand   # generate an additional cohort of words for an existing topic deck
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
