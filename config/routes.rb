Rails.application.routes.draw do
  # --- Authentication (Rails 8 generated) ---
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # --- Public "get the app" page + signed APK download ---
  get "get", to: "downloads#show", as: :get_app
  get "download/simlink.apk", to: "downloads#apk", as: :apk_download

  # --- Web UI (rendered in the Hotwire Native app) ---
  resource :dashboard, only: :show
  resources :sim_cards, only: %i[index] do
    member { patch :share }
  end
  resources :mcp_tokens, only: %i[index create destroy]
  resources :messages, only: %i[index create]
  get "setup", to: "mcp_tokens#index" # alias: "MCP setup" screen

  # --- MCP server (agent ↔ server), Streamable HTTP transport ---
  match "/mcp",        to: "mcp#handle",    via: :post
  match "/mcp",        to: "mcp#terminate", via: :delete
  match "/mcp/:token", to: "mcp#handle",    via: :post
  match "/mcp/:token", to: "mcp#terminate", via: :delete

  # --- Device pairing (web, session-auth): hands a device token to the native app ---
  resource :pairing, only: %i[show create]

  # --- Device API (phone ↔ server), device-token Bearer auth ---
  namespace :api do
    namespace :v1 do
      post "sims",      to: "sims#update"          # report available SIM cards
      get  "outbox",    to: "outbox#index"         # non-blocking: pull queued outbound SMS
      post "heartbeat", to: "devices#heartbeat"
      post "fcm_token", to: "devices#fcm_token"    # register/refresh the FCM push token
      get  "read_requests", to: "read_requests#index"  # claim pending fetch_sms requests
      post "read_requests/:id/results", to: "read_requests#results" # upload read rows
      post "messages/:id/status", to: "messages#status" # report send result
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # --- PWA web-app manifest (proper name/icon/theme when "added to home screen") ---
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Public marketing + agent-discovery pages
  get "for/:slug",   to: "pages#agent", as: :agent_guide
  get "llms.txt",    to: "pages#llms", format: false
  get "robots.txt",  to: "pages#robots", format: false
  get "sitemap.xml", to: "pages#sitemap", format: false

  root "pages#home"
end
