package sk.brezinovi.simlink

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import sk.brezinovi.simlink.data.TokenStore
import sk.brezinovi.simlink.service.OutboxService
import sk.brezinovi.simlink.sms.SimReporter
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets

class MainActivity : HotwireActivity() {

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { onPermissionsSettled() }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.main_nav_host).applyDefaultImeWindowInsets()
        requestNeededPermissions()
    }

    override fun onResume() {
        super.onResume()
        if (TokenStore.hasToken(this)) OutboxService.start(this)
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = BuildConfig.BASE_URL,
            navigatorHostId = R.id.main_nav_host
        )
    )

    private fun requestNeededPermissions() {
        val needed = buildList {
            add(Manifest.permission.SEND_SMS)
            add(Manifest.permission.RECEIVE_SMS)
            add(Manifest.permission.READ_PHONE_STATE)
            add(Manifest.permission.READ_PHONE_NUMBERS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isNotEmpty()) permissionLauncher.launch(needed.toTypedArray())
        else onPermissionsSettled()
    }

    private fun onPermissionsSettled() {
        if (TokenStore.hasToken(this)) {
            Thread { SimReporter.report(this) }.start()
            OutboxService.start(this)
        }
    }
}
