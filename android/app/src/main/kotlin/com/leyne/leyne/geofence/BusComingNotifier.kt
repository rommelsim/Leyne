// BusComingNotifier — posts a "bus is coming" heads-up notification when a
// geofence ENTER fires and a favourited service is within the threshold.
//
// Channel reuse: notifications land on `leyne.arrivals` (Importance.HIGH),
// which is created by flutter_local_notifications at first app launch.  Using
// the same channel means Android's battery / DND rules the user has set for
// arrival alerts apply equally to geofence alerts — no surprising second
// channel to discover in System Settings.
//
// Small icon: @mipmap/ic_launcher, matching AndroidInitializationSettings
// in lib/services/notifications.dart (line 96). The mipmap variant is
// adaptive-icon aware and renders correctly on Android 8+ rounded shapes.
// (Note: for best results on Android < 8, a dedicated monochrome drawable
// in /drawable-* would be ideal, but ic_launcher is what the rest of the
// app's notification stack already uses — keep them consistent.)
//
// Cooldown: 10-minute per-(stop, service) cooldown prevents the OS from
// re-firing the ENTER transition for a dwell and spamming the user.  The
// epoch millis of the last notification is stored in the same
// HomeWidgetPlugin SharedPreferences file under
// `leyne.geofence.cooldown.<stop>.<no>`.

package com.leyne.leyne.geofence

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.leyne.leyne.widget.deepLinkIntent
import es.antonborri.home_widget.HomeWidgetPlugin

object BusComingNotifier {

    private const val TAG = "BusComingNotifier"

    // Reuse the arrival-alert channel created by flutter_local_notifications.
    private const val CHANNEL_ID = "leyne.arrivals"

    // Per-(stop, service) cooldown — 10 minutes in milliseconds.
    private const val COOLDOWN_MS = 10L * 60L * 1_000L

    // SharedPreference key prefix for cooldown timestamps.
    private const val COOLDOWN_KEY_PREFIX = "leyne.geofence.cooldown."

    /**
     * Posts a notification for [busNo] arriving at [stopCode].
     *
     * No-ops silently when:
     * - POST_NOTIFICATIONS permission is not granted (Android 13+).
     * - The cooldown for this (stop, service) pair has not yet elapsed.
     *
     * @param etaMinutes  0 = "Arriving now"; > 0 = minutes until arrival.
     */
    fun notify(
        context: Context,
        stopCode: String,
        stopName: String,
        busNo: String,
        etaMinutes: Int,
    ) {
        // Android 13+ runtime permission guard.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                Log.d(TAG, "POST_NOTIFICATIONS not granted — skipping notification")
                return
            }
        }

        // Cooldown guard.
        val prefs = HomeWidgetPlugin.getData(context)
        val cooldownKey = "$COOLDOWN_KEY_PREFIX$stopCode.$busNo"
        val lastFiredAt = prefs.getLong(cooldownKey, 0L)
        val now = System.currentTimeMillis()
        if (now - lastFiredAt < COOLDOWN_MS) {
            Log.d(TAG, "Cooldown active for bus $busNo at $stopCode — skipping")
            return
        }

        // Build notification.
        val title = if (etaMinutes == 0) "Bus $busNo · Arriving now" else "Bus $busNo · $etaMinutes min"
        val body  = if (etaMinutes == 0) "Arriving now at $stopName" else "Arriving at $stopName"

        // Tap → open the stop screen for this service via the deep-link
        // scheme the rest of the app uses (lyne://stop/<code>/<no>).
        // FLAG_MUTABLE is required on API 31+ (same reason as geofence PI).
        val tapIntent = deepLinkIntent(context, "lyne://stop/$stopCode/$busNo")
        val tapPiFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val tapPi = PendingIntent.getActivity(
            context,
            // Unique request code per (stop, service) so each notification
            // has an independent PendingIntent and tapping one doesn't
            // navigate to the wrong stop.
            "$stopCode.$busNo".hashCode() and 0x7fffffff,
            tapIntent,
            tapPiFlags,
        )

        // Stable notification id — (stopCode+no).hashCode() masked to
        // positive range, matching the pattern in notifications.dart.
        val notifId = "$stopCode.$busNo".hashCode() and 0x7fffffff

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setContentIntent(tapPi)
            .setAutoCancel(true)
            // Ticker text for accessibility services.
            .setTicker(title)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notifId, notification)
            // Record the cooldown timestamp after a successful post.
            prefs.edit().putLong(cooldownKey, now).apply()
            Log.d(TAG, "Posted notification: $title")
        } catch (e: SecurityException) {
            // Race condition: permission revoked between guard check and notify().
            Log.w(TAG, "SecurityException posting notification: $e")
        }
    }
}
