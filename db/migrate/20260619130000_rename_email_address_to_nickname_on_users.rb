class RenameEmailAddressToNicknameOnUsers < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :email_address, :nickname
    rename_index :users, "index_users_on_email_address", "index_users_on_nickname"
  end
end
