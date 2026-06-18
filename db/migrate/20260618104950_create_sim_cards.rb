class CreateSimCards < ActiveRecord::Migration[8.1]
  def change
    create_table :sim_cards do |t|
      t.references :device, null: false, foreign_key: true
      t.string :label
      t.string :phone_number
      t.integer :subscription_id, null: false
      t.integer :slot_index
      t.string :carrier_name
      t.boolean :shared, null: false, default: false

      t.timestamps
    end
    add_index :sim_cards, [ :device_id, :subscription_id ], unique: true
  end
end
