class McpTokensController < ApplicationController
  before_action :set_token, only: :destroy

  def index
    @shared_sims = current_user.sim_cards.shared.includes(:device)
    @tokens = current_user.mcp_tokens.active.includes(:sim_card).order(created_at: :desc)
    @mcp_url = "#{request.base_url}/mcp"
    @new_token = flash[:new_token] # plaintext shown once right after creation
  end

  def create
    sim = current_user.sim_cards.shared.find_by(id: params[:sim_card_id])
    return redirect_to(setup_path, alert: "Pick a shared SIM first.") unless sim

    token = current_user.mcp_tokens.create!(
      sim_card: sim,
      name: params[:name].presence || "Agent token"
    )
    redirect_to setup_path, flash: { new_token: token.token, notice: "Token created. Copy it now — paste it into your agent." }
  end

  def destroy
    @token.revoke!
    redirect_to setup_path, notice: "Token “#{@token.name}” revoked."
  end

  private

  def set_token
    @token = current_user.mcp_tokens.find(params[:id])
  end
end
