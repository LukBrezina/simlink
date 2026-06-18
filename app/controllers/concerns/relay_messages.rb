# Formats in-flight SmsRelay entries into plain view rows for the web dashboard.
# There is no stored history — only the last few minutes of relayed traffic.
module RelayMessages
  extend ActiveSupport::Concern

  private

  def relay_rows(sims, direction: "all", limit: 100)
    sims = Array(sims)
    by_id = sims.index_by(&:id)

    SmsRelay.recent(sims.map(&:id), direction: direction, limit: limit).map do |entry|
      inbound = entry.is_a?(SmsRelay::Inbound)
      {
        direction: inbound ? "inbound" : "outbound",
        peer: inbound ? entry.from : entry.to,
        body: entry.body,
        status: inbound ? "received" : entry.status,
        sim_name: by_id[entry.sim_card_id]&.display_name,
        at: inbound ? entry.received_at : (entry.updated_at || entry.created_at)
      }
    end
  end
end
