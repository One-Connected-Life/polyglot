Rails.application.routes.draw do
  resource :session
  resource :registration, only: [:new, :create]
  resources :passwords, param: :token

  get "onboarding", to: "onboarding#show"
  patch "onboarding", to: "onboarding#update"

  get "up" => "rails/health#show", as: :rails_health_check

  root "drills#home"

  # The drill runner: ?deck=<slug|all|misses>&from=<lang>&to=<lang>
  get "play", to: "drills#play", as: :play

  # Records one graded answer (fire-and-forget from the drill).
  post "attempts", to: "attempts#create"

  # Stable per-word page — reload to re-test pronunciation, see all languages.
  resources :terms, only: [:show]

  # Every word + your attempt history (right/wrong) and status.
  get "stats", to: "stats#index"

  # AI-generate a deck from a topic, or remove one.
  resources :decks, only: [:new, :create, :destroy]
end
