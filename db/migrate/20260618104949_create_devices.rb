class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :platform, null: false, default: "android"
      t.string :token_digest, null: false
      t.datetime :last_seen_at
      t.string :app_version

      t.timestamps
    end
    add_index :devices, :token_digest, unique: true
  end
end
