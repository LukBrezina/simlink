class McpToken < ApplicationRecord
  belongs_to :user
  belongs_to :sim_card
  has_many :messages, dependent: :nullify

  encrypts :token # retained (encrypted at rest) so the user can re-copy it from the UI

  validates :name, presence: true
  validates :token, presence: true
  validates :token_digest, presence: true, uniqueness: true

  before_validation :ensure_token, on: :create

  scope :active, -> { where(revoked_at: nil) }

  def self.authenticate(raw)
    return nil if raw.blank?
    active.find_by(token_digest: digest(raw))
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_used!
    update_column(:last_used_at, Time.current)
  end

  private

  def ensure_token
    return if token.present?
    raw = "mcp_#{SecureRandom.urlsafe_base64(40)}"
    self.token = raw
    self.token_digest = McpToken.digest(raw)
  end
end
