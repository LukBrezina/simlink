package sk.brezinovi.simlink.bridge

import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.service.OutboxService
import sk.brezinovi.simlink.sms.SimReporter
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Native side of the "device" bridge. When the web pairing page renders a fresh
 * device token, it sends a "connect" event with the token; we persist it, report
 * the phone's SIMs, and start the relay service.
 */
class DeviceComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> handleConnect(message)
        }
    }

    private fun handleConnect(message: Message) {
        val data = message.data<ConnectData>() ?: return
        if (data.token.isBlank()) return

        val context = delegate.destination.fragment.requireContext().applicationContext
        TokenStore.saveDeviceToken(context, data.token)

        Thread { SimReporter.report(context) }.start()
        OutboxService.start(context)

        replyTo("connect")
    }

    @Serializable
    data class ConnectData(
        @SerialName("token") val token: String,
        @SerialName("name") val name: String? = null
    )
}
