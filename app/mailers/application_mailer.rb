class ApplicationMailer < ActionMailer::Base
  default from: ENV["MAIL_FROM"].presence || "no-reply@example.com"
  layout "mailer"
end
