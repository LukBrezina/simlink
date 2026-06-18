class AddFcmTokenToDevices < ActiveRecord::Migration[8.1]
  def change
    # The phone's FCM registration token — device identity/config, not message
    # content. Lets the server send a content-free "you have outbound mail" wake.
    add_column :devices, :fcm_token, :string
  end
end
