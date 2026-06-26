# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "speech", to: "speech.js"
pin "listen", to: "listen.js"
pin_all_from "app/javascript/controllers", under: "controllers"
