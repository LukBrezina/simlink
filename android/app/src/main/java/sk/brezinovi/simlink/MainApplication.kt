package sk.brezinovi.simlink

import android.app.Application
import sk.brezinovi.simlink.bridge.DeviceComponent
import dev.hotwire.core.bridge.BridgeComponentFactory
import dev.hotwire.core.bridge.KotlinXJsonConverter
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerBridgeComponents
import dev.hotwire.navigation.config.registerFragmentDestinations

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        Hotwire.defaultFragmentDestination = WebFragment::class
        Hotwire.registerFragmentDestinations(WebFragment::class)

        // The component name "device" must match the web Stimulus component
        // (app/javascript/controllers/bridge/device_controller.js).
        Hotwire.registerBridgeComponents(
            BridgeComponentFactory("device", ::DeviceComponent)
        )

        Hotwire.config.jsonConverter = KotlinXJsonConverter()
        Hotwire.config.applicationUserAgentPrefix = "SimLink;"
        Hotwire.config.debugLoggingEnabled = BuildConfig.DEBUG
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG

        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(assetFilePath = "json/configuration.json")
        )
    }
}
