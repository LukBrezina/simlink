package sk.brezinovi.simlink.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import sk.brezinovi.simlink.data.TokenStore

/** Restarts the relay service after the phone reboots, if already paired. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && TokenStore.hasToken(context)) {
            OutboxService.start(context)
        }
    }
}
