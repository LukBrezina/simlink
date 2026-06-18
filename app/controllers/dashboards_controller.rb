class DashboardsController < ApplicationController
  def show
    @device = current_user.devices.order(last_seen_at: :desc).first
    @shared_sims = current_user.sim_cards.shared.includes(:device)
    @tokens = current_user.mcp_tokens.active.includes(:sim_card)
    @recent_messages = Message.where(sim_card: current_user.sim_cards)
                              .recent_first.limit(5)
  end
end
