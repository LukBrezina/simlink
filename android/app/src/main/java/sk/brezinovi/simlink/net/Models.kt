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
