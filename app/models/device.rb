class Device < ApplicationRecord
  belongs_to :user
  has_many :sim_cards, dependent: :destroy

  validates :name, presence: true
  validates :platform, presence: true

  before_validation :generate_token, on: :create

  # The plaintext device token is only available in-memory right after
  # generation (it lives on the phone; the server keeps only a SHA256 digest).
  attr_reader :token

  def self.find_by_token(raw)
    return nil if raw.blank?
    find_by(token_digest: digest(raw))
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Rotates the device token, returning the new plaintext once.
  def regenerate_token!
    generate_token
    save!
    @token
  end

  def touch_seen!(app_version: nil)
    update_columns(
      last_seen_at: Time.current,
      app_version: app_version.presence || self.app_version,
      updated_at: Time.current
    )
  end

  private

  def generate_token
    @token = "dev_#{SecureRandom.urlsafe_base64(32)}"
    self.token_digest = Device.digest(@token)
  end
end
