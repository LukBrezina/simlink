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
import sk.brezinovi.simlink.MainActivity
import sk.brezinovi.simlink.R
import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.net.ApiClient
import sk.brezinovi.simlink.sms.SimReporter
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
 * Foreground service that keeps a long-poll open against /api/v1/outbox and
 * sends any queued SMS the server hands back. This is the "always on" relay.
 *
 * Note: a foreground service is the Firebase-free way to stay responsive. For a
 * production app you'd likely add FCM push so the phone can sleep; see README.
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
        return START_STICKY
    }

    private fun startLoop() {
        if (looping) return
        looping = true
        scope.launch {
            runCatching { SimReporter.report(this@OutboxService) }
            runCatching { api.heartbeat() }
            while (isActive) {
                try {
                    val messages = api.pollOutbox(timeoutSeconds = 25)
                    messages.forEach { sender.send(it) }
                    if (messages.isEmpty()) delay(1_000)
                } catch (_: Exception) {
                    delay(5_000) // network backoff
                }
            }
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

        fun start(context: Context) {
            if (!TokenStore.hasToken(context)) return
            ContextCompat.startForegroundService(
                context, Intent(context, OutboxService::class.java)
            )
        }
    }
}
