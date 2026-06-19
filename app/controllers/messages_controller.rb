class MessagesController < ApplicationController
  include RelayMessages

  def index
    @sim_cards = current_user.sim_cards.shared
    @messages = relay_rows(current_user.sim_cards.to_a, limit: 100)
  end

  # Compose a test SMS from the web (same in-memory relay the agents use).
  def create
    sim = current_user.sim_cards.shared.find_by(id: params[:sim_card_id])
    return redirect_to(messages_path, alert: "Pick a shared SIM first.") unless sim

    to = params[:to].to_s.strip
    body = params[:body].to_s
    if to.blank? || body.strip.blank?
      return redirect_to(messages_path, alert: "Recipient and message are required.")
    end

    SmsRelay.enqueue_outbound(sim_card_id: sim.id, subscription_id: sim.subscription_id, to: to, body: body)
    Fcm.wake_async(sim.device)
    redirect_to messages_path, notice: "Queued — your phone will send it shortly."
  end
end
