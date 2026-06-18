class DashboardsController < ApplicationController
  include RelayMessages

  def show
    @device = current_user.devices.order(last_seen_at: :desc).first
    @shared_sims = current_user.sim_cards.shared.includes(:device)
    @tokens = current_user.mcp_tokens.active.includes(:sim_card)
    @recent_messages = relay_rows(current_user.sim_cards.to_a, limit: 5)
  end
end
