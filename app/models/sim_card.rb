class SimCard < ApplicationRecord
  belongs_to :device
  has_one :user, through: :device
  has_many :mcp_tokens, dependent: :destroy
  has_many :messages, dependent: :destroy

  validates :subscription_id, presence: true,
            uniqueness: { scope: :device_id }

  scope :shared, -> { where(shared: true) }

  def display_name
    [ label.presence, phone_number.presence ].compact.join(" · ").presence ||
      carrier_name.presence || "SIM ##{slot_index || subscription_id}"
  end
end
