package sk.brezinovi.simlink.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.content.ContextCompat
import sk.brezinovi.simlink.net.ReadRequest
import sk.brezinovi.simlink.net.SmsRecord
import java.time.Instant

/**
 * Reads SMS already stored on the device (the system SMS content provider) on
 * demand, in response to a server read-request. Nothing is cached: each request
 * runs a fresh query, returns the matching rows, and forgets them. Requires the
 * READ_SMS runtime permission.
 *
 * Throws SecurityException when READ_SMS hasn't been granted, so the caller can
 * report that back to the server instead of silently returning an empty result.
 */
object SmsReader {

    private const val HARD_CAP = 100

    fun read(context: Context, request: ReadRequest): List<SmsRecord> {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("READ_SMS not granted")
        }

        val limit = request.limit.coerceIn(1, HARD_CAP)
        val sinceMs = request.since
            ?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }

        val selection = StringBuilder()
        val args = ArrayList<String>()
        when (request.box) {
            "inbox" -> {
                selection.append("${Telephony.Sms.TYPE} = ?")
                args.add(Telephony.Sms.MESSAGE_TYPE_INBOX.toString())
            }
            "sent" -> {
                selection.append("${Telephony.Sms.TYPE} = ?")
                args.add(Telephony.Sms.MESSAGE_TYPE_SENT.toString())
            }
            else -> {
                selection.append("${Telephony.Sms.TYPE} IN (?, ?)")
                args.add(Telephony.Sms.MESSAGE_TYPE_INBOX.toString())
                args.add(Telephony.Sms.MESSAGE_TYPE_SENT.toString())
            }
        }
        sinceMs?.let {
            selection.append(" AND ${Telephony.Sms.DATE} > ?")
            args.add(it.toString())
        }
        request.address?.takeIf { it.isNotBlank() }?.let {
            selection.append(" AND ${Telephony.Sms.ADDRESS} = ?")
            args.add(it)
        }

        val projection = arrayOf(
            Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE,
            Telephony.Sms.TYPE, "sub_id"
        )

        val records = ArrayList<SmsRecord>(limit)
        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            selection.toString(),
            args.toTypedArray(),
            "${Telephony.Sms.DATE} DESC"
        )?.use { c ->
            val iAddr = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iBody = c.getColumnIndex(Telephony.Sms.BODY)
            val iDate = c.getColumnIndex(Telephony.Sms.DATE)
            val iType = c.getColumnIndex(Telephony.Sms.TYPE)
            val iSub = c.getColumnIndex("sub_id")
            while (c.moveToNext() && records.size < limit) {
                // Best-effort SIM scoping: keep rows whose sub_id is unknown (-1)
                // or matches the requested subscription; drop rows that clearly
                // belong to the other SIM. (sub_id is unreliable on some OEMs, so
                // we never exclude rows that don't report one.)
                if (iSub >= 0 && request.subscriptionId >= 0) {
                    val rowSub = c.getInt(iSub)
                    if (rowSub >= 0 && rowSub != request.subscriptionId) continue
                }
                val address = if (iAddr >= 0) c.getString(iAddr) else null
                val body = if (iBody >= 0) c.getString(iBody).orEmpty() else ""
                val dateMs = if (iDate >= 0) c.getLong(iDate) else 0L
                val type = if (iType >= 0) c.getInt(iType) else Telephony.Sms.MESSAGE_TYPE_INBOX
                val sent = type == Telephony.Sms.MESSAGE_TYPE_SENT
                records.add(
                    SmsRecord(
                        from = if (sent) null else address,
                        to = if (sent) address else null,
                        body = body,
                        date = runCatching { Instant.ofEpochMilli(dateMs).toString() }.getOrDefault(""),
                        type = if (sent) "sent" else "inbox"
                    )
                )
            }
        }
        return records
    }
}
