class CreateRelayReads < ActiveRecord::Migration[8.1]
  def change
    create_table :relay_reads do |t|
      t.integer :sim_card_id, null: false
      t.integer :subscription_id
      t.integer :read_limit, null: false, default: 20  # `limit` is a SQL keyword; avoid it
      t.string  :box, null: false, default: "all"
      t.string  :since                                 # ISO8601 lower bound (string), not PII
      t.text    :address                               # encrypted at rest (number filter)
      t.text    :messages_json                         # encrypted at rest (uploaded rows, JSON)
      t.string  :status, null: false, default: "pending"
      t.text    :error
      t.string  :claim_token                           # transient marker for an atomic claim
      t.timestamps
    end

    add_index :relay_reads, [ :sim_card_id, :status ]
    add_index :relay_reads, :claim_token
    add_index :relay_reads, :updated_at                # TTL prune + ordering
  end
end
