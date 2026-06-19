class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :devices, dependent: :destroy
  has_many :sim_cards, through: :devices
  has_many :mcp_tokens, dependent: :destroy

  normalizes :nickname, with: ->(n) { n.strip.downcase }

  validates :nickname, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
end
