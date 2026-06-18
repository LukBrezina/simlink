package sk.brezinovi.simlink.sms

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import sk.brezinovi.simlink.net.ApiClient
import sk.brezinovi.simlink.net.OutboundMessage
import java.util.concurrent.atomic.AtomicInteger

/**
 * Sends an outbound SMS through the SIM identified by its subscription id, then
 * reports the result (sent/failed) back to the server via a one-shot receiver
 * listening to the send PendingIntent.
 */
class SmsSender(private val context: Context) {
    private val api = ApiClient(context)

    fun send(message: OutboundMessage) {
        val smsManager = smsManagerFor(message.subscriptionId)
        val parts = smsManager.divideMessage(message.body)
        val expected = parts.size.coerceAtLeast(1)
        val sentAction = "$ACTION_SENT.${message.id}"

        // Send-result broadcasts are delivered serially on the main thread, so a
        // plain var captured by the receiver is safe (no concurrent writers).
        val counter = AtomicInteger(0)
        var failed = false
        var lastCode = Activity.RESULT_OK

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK) {
                    failed = true
                    lastCode = resultCode
                }
                if (counter.incrementAndGet() >= expected) {
                    runCatching { context.unregisterReceiver(this) }
                    val msgId = message.id
                    val didFail = failed
                    val code = lastCode
                    // Network must not run on the main thread.
                    Thread {
                        if (didFail) api.reportStatus(msgId, "failed", error = "Send failed (result $code)")
                        else api.reportStatus(msgId, "sent")
                    }.start()
                }
            }
        }
        ContextCompat.registerReceiver(
            context, receiver, IntentFilter(sentAction), ContextCompat.RECEIVER_NOT_EXPORTED
        )

        val sentIntents = ArrayList<PendingIntent>(expected)
        for (i in 0 until expected) {
            sentIntents.add(
                PendingIntent.getBroadcast(
                    context,
                    (message.id.toInt() * 100 + i),
                    Intent(sentAction).setPackage(context.packageName),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }

        try {
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(message.to, null, parts, sentIntents, null)
            } else {
                smsManager.sendTextMessage(message.to, null, message.body, sentIntents.first(), null)
            }
        } catch (e: Exception) {
            runCatching { context.unregisterReceiver(receiver) }
            Thread { api.reportStatus(message.id, "failed", error = e.message ?: "send threw") }.start()
        }
    }

    @Suppress("DEPRECATION")
    private fun smsManagerFor(subscriptionId: Int): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
        } else {
            SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        }
    }

    companion object {
        private const val ACTION_SENT = "sk.brezinovi.simlink.SMS_SENT"
    }
}
