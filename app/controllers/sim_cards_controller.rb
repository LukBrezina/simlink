class SimCardsController < ApplicationController
  before_action :set_sim_card, only: :share

  def index
    @sim_cards = current_user.sim_cards.includes(:device).order(:slot_index)
  end

  # Toggle whether this SIM is shared with agents.
  def share
    @sim_card.update(shared: ActiveModel::Type::Boolean.new.cast(params[:shared]))
    redirect_back fallback_location: sim_cards_path,
                  notice: "#{@sim_card.display_name} is now #{@sim_card.shared? ? 'shared' : 'private'}."
  end

  private

  def set_sim_card
    @sim_card = current_user.sim_cards.find(params[:id])
  end
end
