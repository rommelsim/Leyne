// GeofenceManager — registers and clears location geofences for the opt-in
// "Bus-coming alerts" feature.
//
// Why Kotlin instead of Dart: geofence transitions arrive as a PendingIntent
// broadcast that fires even when the app is fully terminated. The
// BroadcastReceiver that handles the transition (GeofenceBroadcastReceiver)
// cannot wake a Dart isolate without a complex foreground-service arrangement,
// so the entire fetch + notify pipeline lives in Kotlin and reuses the widget
// LtaApiClient + WidgetDataRepository.
//
// Persistence: stop list, thresholdMin, and an enabled flag are stored in the
// SAME SharedPreferences file as the home-screen widgets
// (HomeWidgetPlugin.getData(context)) so there is a single key namespace and
// GeofenceBootReceiver can re-register after reboot without involving Dart.

package com.leyne.leyne.geofence

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

/** A single stop that should be watched with a geofence. */
data class GeoStop(
    val code: String,
    val name: String,
    val lat: Double,
    val lon: Double,
)

object GeofenceManager {

    private const val TAG = "GeofenceManager"

    // SharedPreference keys — prefixed "leyne.geofence.*" so they're
    // namespaced away from the widget keys in the same store.
    private const val KEY_STOPS        = "leyne.geofence.stops"
    private const val KEY_THRESHOLD    = "leyne.geofence.thresholdMin"
    private const val KEY_ENABLED      = "leyne.geofence.enabled"

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * Registers a circular geofence for each stop in [stops] and persists the
     * configuration so GeofenceBootReceiver can re-register after reboot.
     *
     * Must NOT be called on the main thread when the list is large (the
     * GeofencingClient call is async/callbacks, but the prefs write is
     * synchronous — keep it on a background thread from MainActivity).
     *
     * @param radius  Geofence radius in metres (typically 250 f).
     * @param thresholdMin  Notify when a favourited bus is ≤ this many minutes
     *                      from the stop. Stored in prefs for use by the
     *                      BroadcastReceiver which has no Dart context.
     */
    @SuppressLint("MissingPermission")          // guarded by hasFineLocation()
    fun register(context: Context, stops: List<GeoStop>, radius: Float, thresholdMin: Int) {
        if (!hasFineLocation(context)) {
            Log.w(TAG, "ACCESS_FINE_LOCATION not granted — skipping geofence registration")
            return
        }

        val client = LocationServices.getGeofencingClient(context)
        val pi = buildPendingIntent(context)

        // Always clear stale geofences before adding new ones so we never
        // hold more than the current favourite set in the OS's geofence list.
        client.removeGeofences(pi).addOnCompleteListener {
            val geofences = stops.map { stop ->
                Geofence.Builder()
                    .setRequestId(stop.code)
                    .setCircularRegion(stop.lat, stop.lon, radius)
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                    // Never expire — the user's home stop doesn't move.
                    // GeofenceBootReceiver re-arms after reboot anyway.
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .build()
            }

            if (geofences.isEmpty()) {
                Log.d(TAG, "No stops to register — cleared existing geofences")
                persistState(context, emptyList(), thresholdMin, enabled = false)
                return@addOnCompleteListener
            }

            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(geofences)
                .build()

            try {
                client.addGeofences(request, pi)
                    .addOnSuccessListener {
                        Log.d(TAG, "Registered ${geofences.size} geofence(s)")
                        persistState(context, stops, thresholdMin, enabled = true)
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "addGeofences failed: $e")
                        // Still persist so a retry after reboot is attempted.
                        persistState(context, stops, thresholdMin, enabled = true)
                    }
            } catch (e: SecurityException) {
                // Background location was revoked between the guard check and
                // the addGeofences call — nothing we can do, log and bail.
                Log.e(TAG, "SecurityException adding geofences: $e")
            }
        }
    }

    /**
     * Removes all geofences owned by this app and marks the feature disabled
     * in SharedPreferences.
     */
    fun clear(context: Context) {
        val pi = buildPendingIntent(context)
        LocationServices.getGeofencingClient(context)
            .removeGeofences(pi)
            .addOnCompleteListener {
                Log.d(TAG, "Geofences cleared")
            }
        persistState(context, emptyList(), thresholdMin = 0, enabled = false)
    }

    /**
     * Reads the persisted stop list + threshold. If the feature was enabled,
     * re-registers the geofences. Called by GeofenceBootReceiver after reboot
     * because the OS drops all geofences when the device powers off.
     */
    fun reRegisterFromPrefs(context: Context) {
        val prefs = HomeWidgetPlugin.getData(context)
        val enabled = prefs.getBoolean(KEY_ENABLED, false)
        if (!enabled) return

        val stops = readPersistedStops(prefs)
        if (stops.isEmpty()) return

        val thresholdMin = prefs.getInt(KEY_THRESHOLD, 6)
        Log.d(TAG, "reRegisterFromPrefs: re-registering ${stops.size} stop(s)")
        // Default radius matches GeofenceService._radiusM = 250.
        register(context, stops, radius = 250f, thresholdMin = thresholdMin)
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /**
     * Reads the threshold stored at boot time so BroadcastReceiver code can
     * retrieve it without calling back into GeofenceManager.
     */
    fun getThresholdMin(context: Context): Int =
        HomeWidgetPlugin.getData(context).getInt(KEY_THRESHOLD, 6)

    /**
     * Builds the PendingIntent that GeofencingClient uses to broadcast
     * transitions. Must be FLAG_MUTABLE on API 31+ because the Geofencing API
     * fills in the triggering geofence extras at dispatch time — an immutable
     * PendingIntent cannot be updated with those extras and the transition
     * would be silently dropped.
     *
     * The same PendingIntent instance is used for add AND remove so the OS
     * can match and cancel the right set.
     */
    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    private fun hasFineLocation(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

    // ─── Persistence ──────────────────────────────────────────────────────────

    private fun persistState(
        context: Context,
        stops: List<GeoStop>,
        thresholdMin: Int,
        enabled: Boolean,
    ) {
        val arr = JSONArray()
        stops.forEach { stop ->
            val o = JSONObject()
            o.put("code", stop.code)
            o.put("name", stop.name)
            o.put("lat", stop.lat)
            o.put("lon", stop.lon)
            arr.put(o)
        }
        HomeWidgetPlugin.getData(context).edit()
            .putString(KEY_STOPS, arr.toString())
            .putInt(KEY_THRESHOLD, thresholdMin)
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    private fun readPersistedStops(
        prefs: android.content.SharedPreferences,
    ): List<GeoStop> = runCatching {
        val json = prefs.getString(KEY_STOPS, null) ?: return emptyList()
        val arr = JSONArray(json)
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(
                    GeoStop(
                        code = o.getString("code"),
                        name = o.getString("name"),
                        lat  = o.getDouble("lat"),
                        lon  = o.getDouble("lon"),
                    )
                )
            }
        }
    }.getOrElse { emptyList() }
}
