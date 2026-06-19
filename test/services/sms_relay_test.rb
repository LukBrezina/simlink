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

  test "recent returns outbound messages newest first" do
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "first")
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420222", body: "second")

    assert_equal [ "second", "first" ], SmsRelay.recent([ 1 ]).map(&:body)
  end

  # ---- reads -----------------------------------------------------------------

  test "enqueue_read then claim moves pending -> claimed and won't double-claim" do
    req = SmsRelay.enqueue_read(sim_card_id: 1, subscription_id: 7, limit: 10, box: "inbox")
    assert_equal "pending", req.status

    claimed = SmsRelay.claim_reads([ 1 ])
    assert_equal [ req.id ], claimed.map(&:id)
    assert_equal "claimed", claimed.first.status
    assert_equal "inbox", claimed.first.box

    assert_empty SmsRelay.claim_reads([ 1 ])
  end

  test "claim_reads is scoped to the requested SIMs" do
    SmsRelay.enqueue_read(sim_card_id: 1, subscription_id: 7, limit: 5)
    SmsRelay.enqueue_read(sim_card_id: 2, subscription_id: 8, limit: 5)

    assert_equal 1, SmsRelay.claim_reads([ 1 ]).size
  end

  test "fulfill_read stores the uploaded rows and read_result returns them" do
    req = SmsRelay.enqueue_read(sim_card_id: 1, subscription_id: 7, limit: 5, box: "inbox")
    SmsRelay.claim_reads([ 1 ])

    rows = [ { "from" => "+420999", "body" => "code 123", "date" => Time.current.iso8601, "type" => "inbox" } ]
    SmsRelay.fulfill_read(req.id, messages: rows, sim_card_ids: [ 1 ])

    result = SmsRelay.read_result(req.id, 1)
    assert_equal "fulfilled", result.status
    assert_equal "code 123", result.messages.first["body"]

    # read_result is scoped to the SIM that owns the request.
    assert_nil SmsRelay.read_result(req.id, 2)
  end

  test "fulfill_read won't touch another device's request" do
    req = SmsRelay.enqueue_read(sim_card_id: 1, subscription_id: 7, limit: 5)
    assert_nil SmsRelay.fulfill_read(req.id, messages: [], sim_card_ids: [ 99 ])
  end

  test "entries are pruned after the TTL" do
    SmsRelay.enqueue_outbound(sim_card_id: 1, subscription_id: 7, to: "+420111", body: "ephemeral")
    req = SmsRelay.enqueue_read(sim_card_id: 1, subscription_id: 7, limit: 5)

    travel(SmsRelay::TTL_SECONDS + 1) do
      assert_empty SmsRelay.recent([ 1 ])
      assert_nil SmsRelay.read_result(req.id, 1)
    end
  end
end
