# Idempotent dev seed: one user, one phone, one shared SIM, one MCP token.
# Prints the secrets you need for local testing.

user = User.find_or_create_by!(nickname: "me") do |u|
  u.password = "password123"
end

device = user.devices.first_or_create!(name: "Dev Phone", platform: "android")

sim = device.sim_cards.find_or_create_by!(subscription_id: 1) do |s|
  s.label = "Personal"
  s.phone_number = "+420777123456"
  s.carrier_name = "O2"
  s.slot_index = 0
  s.shared = true
end
sim.update!(shared: true)

token = user.mcp_tokens.active.find_by(sim_card: sim) ||
        user.mcp_tokens.create!(sim_card: sim, name: "Local test agent")

puts "=" * 64
puts "Seed complete."
puts "  Login:        me / password123"
puts "  Device token: #{device.token || '(only shown on first create; reset DB to see)'}"
puts "  MCP token:    #{token.token}"
puts "  MCP URL:      http://localhost:3000/mcp"
puts "=" * 64
