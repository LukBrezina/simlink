# Firebase Cloud Messaging "wake" pings.
#
# When an agent queues an outbound SMS we send the phone a CONTENT-FREE, high
# priority data message ("you have outbound mail"). The phone then pulls the
# actual SMS over TLS from the in-memory relay and sends it. The message text
# and phone numbers NEVER travel through FCM / Google — only the wake signal.
#
# Best-effort: if FCM is unconfigured, the device has no token, or the call
# fails, we just return false and the phone's slow fallback poll still delivers.
#
# Configuration (a Google service-account JSON, set as a Kamal/Rails secret):
#   ENV["FCM_SERVICE_ACCOUNT_JSON"]  # the full JSON string, or
#   ENV["FCM_SERVICE_ACCOUNT_PATH"]  # a path to the JSON file
# The project id is read from the JSON itself.
module Fcm
  SCOPE     = "https://www.googleapis.com/auth/firebase.messaging".freeze
  TOKEN_URI = "https://oauth2.googleapis.com/token".freeze

  class << self
    def configured?
      service_account.present?
    end

    # Send a wake ping to one device. Returns true if a request was sent.
    def wake(device)
      return false unless configured?

      token = device&.fcm_token
      return false if token.blank?

      send_wake(token)
      true
    rescue => e
      # Never log message content or the device token — only the failure class.
      Rails.logger.warn("[FCM] wake failed: #{e.class}")
      false
    end

    private

    def send_wake(fcm_token)
      body = {
        message: {
          token: fcm_token,
          data: { type: "outbox" }, # content-free; tells the phone to pull
          android: { priority: "HIGH" }
        }
      }
      uri = URI("https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      http_post(uri, request)
    end

    # --- OAuth2 access token from the service account (cached until expiry) ----

    def access_token
      now = Time.now.to_i
      return @access_token if @access_token && @access_token_exp.to_i > now + 60

      jwt = signed_jwt(now)
      uri = URI(TOKEN_URI)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion"  => jwt
      )
      json = JSON.parse(http_post(uri, request))
      @access_token = json.fetch("access_token")
      @access_token_exp = now + json.fetch("expires_in", 3600).to_i
      @access_token
    end

    def signed_jwt(now)
      header  = base64url({ alg: "RS256", typ: "JWT" }.to_json)
      claims  = base64url({
        iss:   service_account["client_email"],
        scope: SCOPE,
        aud:   TOKEN_URI,
        iat:   now,
        exp:   now + 3600
      }.to_json)
      signing_input = "#{header}.#{claims}"
      key = OpenSSL::PKey::RSA.new(service_account["private_key"])
      signature = base64url(key.sign(OpenSSL::Digest::SHA256.new, signing_input))
      "#{signing_input}.#{signature}"
    end

    def http_post(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    def base64url(bytes)
      Base64.urlsafe_encode64(bytes, padding: false)
    end

    def project_id
      service_account["project_id"]
    end

    def service_account
      return @service_account if defined?(@service_account)
      @service_account = load_service_account
    end

    def load_service_account
      json = ENV["FCM_SERVICE_ACCOUNT_JSON"].presence
      json ||= File.read(ENV["FCM_SERVICE_ACCOUNT_PATH"]) if ENV["FCM_SERVICE_ACCOUNT_PATH"].present?
      return nil if json.blank?

      parsed = JSON.parse(json)
      parsed if parsed["private_key"].present? && parsed["client_email"].present? && parsed["project_id"].present?
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end
  end
end
