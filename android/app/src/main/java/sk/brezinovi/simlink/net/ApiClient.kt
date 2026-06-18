package sk.brezinovi.simlink.net

import android.content.Context
import sk.brezinovi.simlink.BuildConfig
import sk.brezinovi.simlink.data.TokenStore
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Thin OkHttp client for the device-facing API. Authenticates every request with
 * the stored device token. All calls are blocking — invoke from a background
 * thread / coroutine on Dispatchers.IO.
 */
class ApiClient(context: Context) {
    private val appContext = context.applicationContext
    private val base = BuildConfig.BASE_URL.trimEnd('/')

    private val client = OkHttpClient.Builder()
        // Endpoints are non-blocking now (FCM wakes + a slow fallback poll), so
        // ordinary timeouts are plenty.
        .callTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .connectTimeout(15, TimeUnit.SECONDS)
        .build()

    private val jsonMedia = "application/json".toMediaType()

    private fun token(): String? = TokenStore.deviceToken(appContext)

    /** Pull queued outbound SMS (returns immediately). Empty on none or error. */
    fun pollOutbox(): List<OutboundMessage> {
        val request = authed(Request.Builder().url("$base/api/v1/outbox").get())
        client.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) return emptyList()
            val arr = JSONObject(resp.body?.string().orEmpty().ifBlank { "{}" })
                .optJSONArray("messages") ?: return emptyList()
            return (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                OutboundMessage(
                    id = o.getLong("id"),
                    subscriptionId = o.getInt("subscription_id"),
                    to = o.getString("to"),
                    body = o.getString("body")
                )
            }
        }
    }

    fun reportStatus(id: Long, status: String, error: String? = null, providerMessageId: String? = null) {
        val body = JSONObject().put("status", status)
        error?.let { body.put("error", it) }
        providerMessageId?.let { body.put("provider_message_id", it) }
        post("$base/api/v1/messages/$id/status", body)
    }

    fun reportInbound(subscriptionId: Int, from: String, text: String, receivedAtIso: String?) {
        val body = JSONObject()
            .put("subscription_id", subscriptionId)
            .put("from", from)
            .put("body", text)
        receivedAtIso?.let { body.put("received_at", it) }
        post("$base/api/v1/inbound", body)
    }

    fun reportSims(sims: List<SimInfo>) {
        val arr = JSONArray()
        sims.forEach { sim ->
            arr.put(
                JSONObject()
                    .put("subscription_id", sim.subscriptionId)
                    .put("label", sim.label ?: JSONObject.NULL)
                    .put("phone_number", sim.phoneNumber ?: JSONObject.NULL)
                    .put("carrier_name", sim.carrierName ?: JSONObject.NULL)
                    .put("slot_index", sim.slotIndex)
            )
        }
        post("$base/api/v1/sims", JSONObject().put("sims", arr))
    }

    fun heartbeat() = post("$base/api/v1/heartbeat", JSONObject())

    /** Register/refresh the phone's FCM token so the server can send wake pings. */
    fun registerFcmToken(fcmToken: String) =
        post("$base/api/v1/fcm_token", JSONObject().put("fcm_token", fcmToken))

    private fun post(url: String, body: JSONObject) {
        val request = authed(
            Request.Builder().url(url).post(body.toString().toRequestBody(jsonMedia))
        )
        client.newCall(request).execute().use { /* response body unused */ }
    }

    private fun authed(builder: Request.Builder): Request =
        builder
            .header("Authorization", "Bearer ${token().orEmpty()}")
            .header("X-App-Version", BuildConfig.VERSION_NAME)
            .build()
}
