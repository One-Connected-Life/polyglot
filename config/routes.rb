Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "drills#home"

  # The drill runner: ?deck=<slug|all|misses>&from=<lang>&to=<lang>
  get "play", to: "drills#play", as: :play

  # Records one graded answer (fire-and-forget from the drill).
  post "attempts", to: "attempts#create"
end
