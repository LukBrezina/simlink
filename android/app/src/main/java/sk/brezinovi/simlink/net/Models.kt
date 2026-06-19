package sk.brezinovi.simlink.net

/** A queued outbound SMS handed to the phone by the server's outbox endpoint. */
data class OutboundMessage(
    val id: Long,
    val subscriptionId: Int,
    val to: String,
    val body: String
)

/** A SIM card present on the device, reported to the server. */
data class SimInfo(
    val subscriptionId: Int,
    val label: String?,
    val phoneNumber: String?,
    val carrierName: String?,
    val slotIndex: Int
)

/**
 * A request from the server to read SMS already stored on the device. The phone
 * reads its own SMS provider on demand and uploads the matching rows — nothing is
 * pushed automatically or cached.
 */
data class ReadRequest(
    val id: Long,
    val subscriptionId: Int,
    val limit: Int,
    val since: String?,   // ISO8601 lower bound (exclusive), or null for no bound
    val address: String?, // restrict to this phone number, or null for any
    val box: String       // "inbox" | "sent" | "all"
)

/** One SMS read from the device's SMS provider, uploaded as a read result. */
data class SmsRecord(
    val from: String?,    // sender (inbox) — null for sent
    val to: String?,      // recipient (sent) — null for inbox
    val body: String,
    val date: String,     // ISO8601
    val type: String      // "inbox" | "sent"
)
