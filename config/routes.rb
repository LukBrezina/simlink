Rails.application.routes.draw do
  # --- Authentication (Rails 8 generated) ---
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

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
  get   "/mcp",        to: "mcp#stream"
  match "/mcp",        to: "mcp#terminate", via: :delete
  match "/mcp/:token", to: "mcp#handle",    via: :post
  get   "/mcp/:token", to: "mcp#stream"
  match "/mcp/:token", to: "mcp#terminate", via: :delete

  # --- Device pairing (web, session-auth): hands a device token to the native app ---
  resource :pairing, only: %i[show create]

  # --- Device API (phone ↔ server), device-token Bearer auth ---
  namespace :api do
    namespace :v1 do
      post "sims",      to: "sims#update"          # report available SIM cards
      get  "outbox",    to: "outbox#index"         # long-poll for queued outbound SMS
      post "heartbeat", to: "devices#heartbeat"
      post "inbound",   to: "messages#inbound"     # report a received SMS
      post "messages/:id/status", to: "messages#status" # report send result
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
