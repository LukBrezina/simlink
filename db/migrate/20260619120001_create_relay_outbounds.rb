class CreateRelayOutbounds < ActiveRecord::Migration[8.1]
  def change
    create_table :relay_outbounds do |t|
      t.integer :sim_card_id, null: false
      t.integer :subscription_id
      t.text    :to                                   # encrypted at rest (recipient number)
      t.text    :body                                 # encrypted at rest (message text)
      t.string  :status, null: false, default: "queued"
      t.text    :error
      t.string  :claim_token                          # transient marker for an atomic claim
      t.timestamps
    end

    add_index :relay_outbounds, [ :sim_card_id, :status ]
    add_index :relay_outbounds, :claim_token
    add_index :relay_outbounds, :updated_at           # TTL prune + newest-first ordering
  end
end
