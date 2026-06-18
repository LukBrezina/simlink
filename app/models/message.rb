class Message < ApplicationRecord
  belongs_to :sim_card
  belongs_to :mcp_token, optional: true

  DIRECTIONS = %w[inbound outbound].freeze
  OUTBOUND_STATUSES = %w[queued sending sent failed].freeze
  INBOUND_STATUSES  = %w[received].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :address, presence: true
  validates :body, presence: true
  validates :status, presence: true

  scope :inbound,  -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :queued,   -> { where(direction: "outbound", status: "queued") }
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent_first,  -> { order(created_at: :desc) }

  after_create_commit :broadcast_inbound, if: :inbound?

  def inbound?
    direction == "inbound"
  end

  def outbound?
    direction == "outbound"
  end

  # Shape returned to MCP agents.
  def as_mcp_json
    {
      id: id,
      direction: direction,
      from: inbound? ? address : sim_card.phone_number,
      to: inbound? ? sim_card.phone_number : address,
      body: body,
      status: status,
      timestamp: (inbound? ? received_at : sent_at)&.iso8601 || created_at.iso8601
    }.compact
  end

  private

  def broadcast_inbound
    InboundSmsChannel.broadcast_to(sim_card, as_mcp_json) if defined?(InboundSmsChannel)
  rescue StandardError
    # Broadcasting is best-effort; never block message persistence.
    nil
  end
end
