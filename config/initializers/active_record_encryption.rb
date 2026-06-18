# ActiveRecord encryption keys for the encrypted `mcp_tokens.token` column.
#
# In production set real, secret values via environment variables (generate with
# `bin/rails db:encryption:init`). The development fallbacks below let the app run
# out of the box but MUST NOT be used to protect real data.
Rails.application.configure do
  config.active_record.encryption.primary_key =
    ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY", "dev_only_primary_key_replace_in_production_0001")
  config.active_record.encryption.deterministic_key =
    ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY", "dev_only_deterministic_key_replace_in_prod_0002")
  config.active_record.encryption.key_derivation_salt =
    ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT", "dev_only_key_derivation_salt_replace_in_prod_03")
end
