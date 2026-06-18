class DownloadsController < ApplicationController
  allow_unauthenticated_access only: :show

  # Public "get the app" landing: download link + how to continue on the phone.
  def show
  end
end
