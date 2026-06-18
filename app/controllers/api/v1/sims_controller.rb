module Api
  module V1
    # The phone reports the SIM cards currently present. We upsert them so the
    # user can choose which one to share from the web UI. We never flip `shared`
    # here — that's the user's decision.
    class SimsController < Api::BaseController
      def update
        sims = Array(params[:sims]).map do |raw|
          attrs = raw.permit(:subscription_id, :label, :phone_number, :carrier_name, :slot_index)
          next if attrs[:subscription_id].blank?

          sim = current_device.sim_cards.find_or_initialize_by(subscription_id: attrs[:subscription_id])
          sim.assign_attributes(attrs.except(:subscription_id).to_h.compact)
          sim.save!
          sim
        end.compact

        render json: { sims: sims.map { |s| sim_json(s) } }
      end

      private

      def sim_json(sim)
        {
          subscription_id: sim.subscription_id,
          label: sim.label,
          phone_number: sim.phone_number,
          carrier_name: sim.carrier_name,
          slot_index: sim.slot_index,
          shared: sim.shared
        }
      end
    end
  end
end
