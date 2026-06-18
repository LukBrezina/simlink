class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :sim_card, null: false, foreign_key: true
      t.references :mcp_token, null: true, foreign_key: true # set for outbound (which agent sent it)
      t.string :direction, null: false                       # inbound | outbound
      t.string :address, null: false                         # the other party's phone number
      t.text :body, null: false
      t.string :status, null: false                          # outbound: queued|sending|sent|failed ; inbound: received
      t.string :error
      t.string :provider_message_id
      t.datetime :sent_at
      t.datetime :received_at

      t.timestamps
    end
    add_index :messages, [ :sim_card_id, :direction, :status ]
    add_index :messages, [ :sim_card_id, :created_at ]
  end
end
