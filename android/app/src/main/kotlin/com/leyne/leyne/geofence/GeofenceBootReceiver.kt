// GeofenceBootReceiver — re-registers geofences after a device reboot or
// package replacement.
//
// The OS drops all registered geofences when the device powers off (or when
// the APK is replaced / updated).  This receiver listens for BOOT_COMPLETED
// and MY_PACKAGE_REPLACED, reads the persisted stop list from SharedPreferences,
// and calls GeofenceManager.reRegisterFromPrefs() to restore them.
//
// Both actions are declared in AndroidManifest.xml.  The RECEIVE_BOOT_COMPLETED
// permission is already declared (shared with flutter_local_notifications'
// ScheduledNotificationBootReceiver).

package com.leyne.leyne.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class GeofenceBootReceiver : BroadcastReceiver() {

    private val TAG = "GeofenceBootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        Log.d(TAG, "Received $action — re-registering geofences")
        // reRegisterFromPrefs is a lightweight prefs read followed by an async
        // GeofencingClient call — safe to run on the BroadcastReceiver's main
        // thread (the async addGeofences callback does the real work).
        GeofenceManager.reRegisterFromPrefs(context)
    }
}
