# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_19_130000) do
  create_table "devices", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.string "fcm_token"
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.string "platform", default: "android", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_devices_on_token_digest", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "mcp_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.integer "sim_card_id", null: false
    t.string "token", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["sim_card_id"], name: "index_mcp_tokens_on_sim_card_id"
    t.index ["token_digest"], name: "index_mcp_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_mcp_tokens_on_user_id"
  end

  create_table "relay_outbounds", force: :cascade do |t|
    t.text "body"
    t.string "claim_token"
    t.datetime "created_at", null: false
    t.text "error"
    t.integer "sim_card_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "subscription_id"
    t.text "to"
    t.datetime "updated_at", null: false
    t.index ["claim_token"], name: "index_relay_outbounds_on_claim_token"
    t.index ["sim_card_id", "status"], name: "index_relay_outbounds_on_sim_card_id_and_status"
    t.index ["updated_at"], name: "index_relay_outbounds_on_updated_at"
  end

  create_table "relay_reads", force: :cascade do |t|
    t.text "address"
    t.string "box", default: "all", null: false
    t.string "claim_token"
    t.datetime "created_at", null: false
    t.text "error"
    t.text "messages_json"
    t.integer "read_limit", default: 20, null: false
    t.integer "sim_card_id", null: false
    t.string "since"
    t.string "status", default: "pending", null: false
    t.integer "subscription_id"
    t.datetime "updated_at", null: false
    t.index ["claim_token"], name: "index_relay_reads_on_claim_token"
    t.index ["sim_card_id", "status"], name: "index_relay_reads_on_sim_card_id_and_status"
    t.index ["updated_at"], name: "index_relay_reads_on_updated_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sim_cards", force: :cascade do |t|
    t.string "carrier_name"
    t.datetime "created_at", null: false
    t.integer "device_id", null: false
    t.string "label"
    t.string "phone_number"
    t.boolean "shared", default: false, null: false
    t.integer "slot_index"
    t.integer "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "subscription_id"], name: "index_sim_cards_on_device_id_and_subscription_id", unique: true
    t.index ["device_id"], name: "index_sim_cards_on_device_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "nickname", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["nickname"], name: "index_users_on_nickname", unique: true
  end

  add_foreign_key "devices", "users"
  add_foreign_key "mcp_tokens", "sim_cards"
  add_foreign_key "mcp_tokens", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "sim_cards", "devices"
end
