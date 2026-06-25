class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "My New Words <notifications@mail.mynewwords.org>")
  layout "mailer"
end
