class MessagesController < ApplicationController
  def index
    @sim_cards = current_user.sim_cards.shared
    @messages = Message.where(sim_card: current_user.sim_cards)
                       .includes(:sim_card).recent_first.limit(100)
  end

  # Compose a test SMS from the web (same queue the agents use).
  def create
    sim = current_user.sim_cards.shared.find_by(id: params[:sim_card_id])
    return redirect_to(messages_path, alert: "Pick a shared SIM first.") unless sim

    to = params[:to].to_s.strip
    body = params[:body].to_s
    if to.blank? || body.strip.blank?
      return redirect_to(messages_path, alert: "Recipient and message are required.")
    end

    sim.messages.create!(direction: "outbound", address: to, body: body, status: "queued")
    redirect_to messages_path, notice: "Queued — your phone will send it shortly."
  end
end
