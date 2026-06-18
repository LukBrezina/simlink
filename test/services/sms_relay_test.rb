require "test_helper"

class SmsRelayTest < ActiveSupport::TestCase
  setup { SmsRelay.reset! }
  teardown { SmsRelay.reset! }

  test "enqueue then claim moves queued -> sending and won't double-claim" do
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "hi")

    claimed = SmsRelay.claim_outbound([ 1 ])
    assert_equal 1, claimed.size
    assert_equal "sending", claimed.first.status
    assert_equal 7, claimed.first.subscription_id

    # A second poll gets nothing — it was already claimed.
    assert_empty SmsRelay.claim_outbound([ 1 ])
  end

  test "claim is scoped to the requested SIMs" do
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "a")
    SmsRelay.enqueue_outbound(sim_card_id: 2, subscription_id: 8, to: "+420222", body: "b")

    claimed = SmsRelay.claim_outbound([ 1 ])
    assert_equal [ "a" ], claimed.map(&:body)
  end

  test "update_status updates the matching outbound entry" do
    entry = SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "hi")
    SmsRelay.claim_outbound([ 1 ])

    updated = SmsRelay.update_status(entry.id, status: "sent")
    assert_equal "sent", updated.status
    assert_nil SmsRelay.update_status(-999, status: "sent")
  end

  test "inbound_since returns only messages after the cutoff, oldest first" do
    t0 = Time.current
    SmsRelay.add_inbound(sim_card_id: 1, from: "+420999", body: "old", received_at: t0 - 10)
    SmsRelay.add_inbound(sim_card_id: 1, from: "+420999", body: "new", received_at: t0 + 10)

    fresh = SmsRelay.inbound_since(1, t0)
    assert_equal [ "new" ], fresh.map(&:body)

    assert_equal [ "old", "new" ], SmsRelay.inbound_since(1).map(&:body)
  end

  test "inbound is isolated per SIM" do
    SmsRelay.add_inbound(sim_card_id: 1, from: "+420999", body: "for-1")
    SmsRelay.add_inbound(sim_card_id: 2, from: "+420888", body: "for-2")

    assert_equal [ "for-1" ], SmsRelay.inbound_since(1).map(&:body)
  end

  test "recent returns both directions newest first and respects direction filter" do
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "out")
    SmsRelay.add_inbound(sim_card_id: 1, from: "+420999", body: "in")

    all = SmsRelay.recent([ 1 ])
    assert_equal 2, all.size
    assert_equal [ "in" ], SmsRelay.recent([ 1 ], direction: "inbound").map(&:body)
    assert_equal [ "out" ], SmsRelay.recent([ 1 ], direction: "outbound").map(&:body)
  end

  test "entries are pruned after the TTL" do
    SmsRelay.add_inbound(sim_card_id: 1, from: "+420999", body: "ephemeral")
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "ephemeral")

    travel(SmsRelay::TTL_SECONDS + 1) do
      assert_empty SmsRelay.inbound_since(1)
      assert_empty SmsRelay.recent([ 1 ])
    end
  end
end
