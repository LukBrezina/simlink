package sk.brezinovi.simlink.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import sk.brezinovi.simlink.MainActivity
import sk.brezinovi.simlink.R
import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.net.ApiClient
import sk.brezinovi.simlink.sms.SimReporter
import sk.brezinovi.simlink.sms.SmsReader
import sk.brezinovi.simlink.sms.SmsSender
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import android.app.PendingIntent

/**
 * Foreground service that sends queued outbound SMS. Delivery is push-driven:
 * the server sends a content-free FCM "wake" ping (handled by SimMessagingService)
 * which triggers an immediate, non-blocking outbox pull. A slow fallback poll
 * catches anything a dropped/delayed push missed. No long-lived connections.
 */
class OutboxService : Service() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val sender by lazy { SmsSender(this) }
    private val api by lazy { ApiClient(this) }
    private var looping = false

    override fun onCreate() {
        super.onCreate()
        startForegroundCompat()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!TokenStore.hasToken(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        startLoop()
        // An FCM wake (or any caller) can request an immediate pull.
        if (intent?.action == ACTION_PULL_NOW) {
            scope.launch { pullAndSend() }
        }
        return START_STICKY
    }

    private fun startLoop() {
        if (looping) return
        looping = true
        scope.launch {
            runCatching { SimReporter.report(this@OutboxService) }
            runCatching { api.heartbeat() }
            registerFcmToken()
            // Slow fallback poll — push is the primary delivery path.
            while (isActive) {
                pullAndSend()
                delay(FALLBACK_INTERVAL_MS)
            }
        }
    }

    private fun pullAndSend() {
        try {
            api.pollOutbox().forEach { sender.send(it) }
        } catch (_: Exception) {
            // Best-effort; the next FCM wake or fallback tick retries.
        }
        pullAndAnswerReads()
    }

    // Answer any pending read-requests by reading the device's SMS provider and
    // uploading the rows. A failed read (e.g. READ_SMS not granted) is reported
    // back so the agent gets a clear error instead of polling forever.
    private fun pullAndAnswerReads() {
        val requests = try {
            api.pollReadRequests()
        } catch (_: Exception) {
            return
        }
        requests.forEach { req ->
            try {
                api.reportReadResults(req.id, SmsReader.read(this, req))
            } catch (_: SecurityException) {
                api.reportReadResults(
                    req.id, emptyList(),
                    error = "READ_SMS permission not granted on the phone. Open SimLink and allow SMS access."
                )
            } catch (e: Exception) {
                api.reportReadResults(req.id, emptyList(), error = e.message ?: "read failed")
            }
        }
    }

    private fun registerFcmToken() {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            scope.launch { runCatching { api.registerFcmToken(token) } }
        }
    }

    override fun onDestroy() {
        looping = false
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat() {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.relay_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.relay_notification_title))
            .setContentText(getString(R.string.relay_notification_text))
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setOngoing(true)
            .setContentIntent(openApp)
            .build()
    }

    companion object {
        const val NOTIF_ID = 1
        const val CHANNEL_ID = "sms_relay"
        const val ACTION_PULL_NOW = "sk.brezinovi.simlink.PULL_NOW"
        private const val FALLBACK_INTERVAL_MS = 90_000L

        fun start(context: Context) {
            if (!TokenStore.hasToken(context)) return
            ContextCompat.startForegroundService(
                context, Intent(context, OutboxService::class.java)
            )
        }

        // Called from the FCM wake to pull queued outbound SMS immediately.
        fun pullNow(context: Context) {
            if (!TokenStore.hasToken(context)) return
            ContextCompat.startForegroundService(
                context,
                Intent(context, OutboxService::class.java).setAction(ACTION_PULL_NOW)
            )
        }
    }
}
