class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :devices, dependent: :destroy
  has_many :sim_cards, through: :devices
  has_many :mcp_tokens, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
