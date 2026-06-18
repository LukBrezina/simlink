package sk.brezinovi.simlink.service

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.net.ApiClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Receives content-free FCM "wake" pings and triggers an immediate outbox pull.
 * The push never carries SMS content — only a signal to fetch over TLS — so
 * message text and phone numbers never pass through Google's servers.
 */
class SimMessagingService : FirebaseMessagingService() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMessageReceived(message: RemoteMessage) {
        // Wake the relay service to pull queued outbound SMS and send them.
        OutboxService.pullNow(applicationContext)
    }

    override fun onNewToken(token: String) {
        if (!TokenStore.hasToken(applicationContext)) return
        scope.launch {
            runCatching { ApiClient(applicationContext).registerFcmToken(token) }
        }
    }
}
