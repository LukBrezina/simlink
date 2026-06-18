package sk.brezinovi.simlink.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.net.ApiClient
import java.time.Instant

/**
 * Receives incoming SMS and forwards them to the server. Multipart messages
 * arrive as several PDUs in one broadcast; we concatenate them.
 */
class IncomingSmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!TokenStore.hasToken(context)) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return

        val from = parts.first().displayOriginatingAddress
            ?: parts.first().originatingAddress
            ?: return
        val body = parts.joinToString(separator = "") {
            it.displayMessageBody ?: it.messageBody ?: ""
        }
        val receivedAt = runCatching { Instant.ofEpochMilli(parts.first().timestampMillis).toString() }
            .getOrNull()
        val subId = resolveSubscriptionId(context, intent)

        val appContext = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                ApiClient(appContext).reportInbound(subId, from, body, receivedAt)
            } catch (_: Exception) {
                // best effort; the server's wait_for_sms/list_messages will simply not see it
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun resolveSubscriptionId(context: Context, intent: Intent): Int {
        val fromExtra = intent.getIntExtra(
            SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX,
            intent.getIntExtra("subscription", -1)
        )
        if (fromExtra >= 0) return fromExtra
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching { SmsManager.getDefaultSmsSubscriptionId() }.getOrDefault(-1)
        } else {
            -1
        }
    }
}
