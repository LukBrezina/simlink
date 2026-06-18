package sk.brezinovi.simlink.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import sk.brezinovi.simlink.net.ApiClient
import sk.brezinovi.simlink.net.SimInfo

/** Enumerates the active SIM cards and reports them to the server. */
object SimReporter {

    fun collect(context: Context): List<SimInfo> {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return emptyList()
        }

        val sm = context.getSystemService(SubscriptionManager::class.java) ?: return emptyList()
        val active = try {
            @Suppress("MissingPermission")
            sm.activeSubscriptionInfoList
        } catch (_: SecurityException) {
            null
        } ?: return emptyList()

        return active.map { info ->
            SimInfo(
                subscriptionId = info.subscriptionId,
                label = info.displayName?.toString(),
                phoneNumber = info.number?.takeIf { it.isNotBlank() },
                carrierName = info.carrierName?.toString(),
                slotIndex = info.simSlotIndex
            )
        }
    }

    /** Collect + POST. Safe to call from a background thread. */
    fun report(context: Context) {
        val sims = collect(context)
        if (sims.isNotEmpty()) {
            runCatching { ApiClient(context).reportSims(sims) }
        }
    }
}
