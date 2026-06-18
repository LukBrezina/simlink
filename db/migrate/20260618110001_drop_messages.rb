class DropMessages < ActiveRecord::Migration[8.1]
  # Messages are no longer stored. They are relayed in memory (SmsRelay) and never
  # written to disk. Drop the table and its stored SMS content for good.
  def up
    drop_table :messages
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "messages are no longer persisted"
  end
end
