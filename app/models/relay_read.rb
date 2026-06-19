# A `fetch_sms` round-trip: the agent's read-request plus the rows the phone
# uploads. Persisted in SQLite (shared across Puma workers) but ephemeral —
# SmsRelay prunes rows past a short TTL. The address filter and the uploaded
# messages contain phone numbers / message text, so they're encrypted at rest
# (non-deterministic; never queried by value) and filtered from the logs.
class RelayRead < ApplicationRecord
  encrypts :address
  encrypts :messages_json

  # Uploaded rows, decrypted and parsed. Always an array (empty until fulfilled).
  def messages
    raw = messages_json
    raw.present? ? JSON.parse(raw) : []
  end
end
