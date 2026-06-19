# A single outbound SMS in transit: agent -> server -> phone. Persisted in SQLite
# so it's shared across Puma workers, but treated as ephemeral — SmsRelay prunes
# rows past a short TTL. The recipient number and message text are encrypted at
# rest (non-deterministic; never queried by value) and filtered from the logs.
class RelayOutbound < ApplicationRecord
  encrypts :to
  encrypts :body
end
