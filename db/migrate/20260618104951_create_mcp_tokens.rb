class CreateMcpTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :sim_card, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token, null: false        # encrypted at rest, retained so the user can re-copy it
      t.string :token_digest, null: false  # SHA256 lookup key for auth
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :mcp_tokens, :token_digest, unique: true
  end
end
