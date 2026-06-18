class DownloadsController < ApplicationController
  allow_unauthenticated_access only: %i[show apk]

  # Public "get the app" landing: download link + how to continue on the phone.
  def show
  end

  # Serve the signed APK with the correct MIME so Android installs cleanly.
  def apk
    path = Rails.root.join("downloads/simlink.apk")
    return head(:not_found) unless File.exist?(path)

    send_file path,
              type: "application/vnd.android.package-archive",
              disposition: "attachment",
              filename: "simlink.apk"
  end
end
