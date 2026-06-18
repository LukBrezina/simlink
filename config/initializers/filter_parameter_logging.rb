# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # SMS content and endpoints: message text and phone numbers must never reach the
  # logs. `to`/`from`/`text` are anchored regexps (matched against the immediate
  # key) so they don't over-filter unrelated keys like `token` or `total`.
  :body, :address, :phone_number, /\Ato\z/i, /\Afrom\z/i, /\Atext\z/i
]
