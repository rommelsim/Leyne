// GeofenceBroadcastReceiver — handles OS geofence transition broadcasts.
//
// When the device enters a geofenced stop region, this receiver:
//   1. Identifies the triggering stop code(s) from the GeofencingEvent.
//   2. Reads the user's favourited services from WidgetDataRepository.
//   3. Fetches live arrivals for the stop via LtaApiClient (same client as
//      the home-screen widget — reuses the widget auth key + HTTP logic).
//   4. For each favourited service arriving within thresholdMin minutes,
//      posts a notification via BusComingNotifier (with per-service cooldown
//      to suppress repeat alerts for the same bus at the same stop).
//
// Why goAsync(): BroadcastReceiver.onReceive() has a ~10 s hard deadline on
// the main thread before the system considers the receiver ANR'd. The network
// fetch from LtaApiClient can take up to 12 s (TIMEOUT_MS). goAsync() returns
// a PendingResult to the system immediately, extending the deadline while the
// coroutine does its work. We call pendingResult.finish() from every exit path.

package com.leyne.leyne.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.Geofence
import com.leyne.leyne.widget.LtaApiClient
import com.leyne.leyne.widget.WidgetDataRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    private val TAG = "GeoFenceReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        // goAsync() extends the receiver's deadline past the default ~10 s so
        // we can safely await the LTA network fetch (up to 12 s timeout).
        val pendingResult = goAsync()

        val event = GeofencingEvent.fromIntent(intent)
        if (event == null) {
            Log.w(TAG, "GeofencingEvent.fromIntent returned null — ignoring")
            pendingResult.finish()
            return
        }
        if (event.hasError()) {
            Log.e(TAG, "GeofencingEvent error code: ${event.errorCode}")
            pendingResult.finish()
            return
        }
        if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) {
            // We only registered GEOFENCE_TRANSITION_ENTER, but guard
            // defensively in case the OS sends DWELL or EXIT.
            pendingResult.finish()
            return
        }

        val triggeringGeofences = event.triggeringGeofences
        if (triggeringGeofences.isNullOrEmpty()) {
            pendingResult.finish()
            return
        }

        val thresholdMin = GeofenceManager.getThresholdMin(context)
        val repo = WidgetDataRepository(context)

        // SupervisorJob so a failure on one stop doesn't cancel sibling coroutines.
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

        scope.launch {
            try {
                // Pre-load the full favs list once (avoids N reads for N stops).
                val allFavs = repo.getFavs()

                for (geofence in triggeringGeofences) {
                    val stopCode = geofence.requestId
                    handleStop(context, stopCode, allFavs, thresholdMin)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error handling geofence transition: $e")
            } finally {
                // Always release the PendingResult — the system will ANR the
                // receiver if we forget this.
                pendingResult.finish()
            }
        }
    }

    // ─── Per-stop logic ───────────────────────────────────────────────────────

    private suspend fun handleStop(
        context: Context,
        stopCode: String,
        allFavs: List<com.leyne.leyne.widget.FavServiceItem>,
        thresholdMin: Int,
    ) {
        // Filter favourites that belong to this stop.
        val favsAtStop = allFavs.filter { it.stopCode == stopCode }
        if (favsAtStop.isEmpty()) {
            Log.d(TAG, "No favourites at stop $stopCode — skipping fetch")
            return
        }

        // Fetch live arrivals from LTA DataMall.
        val rows = LtaApiClient.fetch(stopCode)
        if (rows.isEmpty()) {
            Log.d(TAG, "Empty arrivals response for stop $stopCode")
            return
        }

        // Build a lookup map: serviceNo → ArrivalRow for fast access.
        val rowByNo = rows.associateBy { it.no }

        for (fav in favsAtStop) {
            val row = rowByNo[fav.no] ?: continue        // bus not in arrivals
            val eta = row.eta1 ?: continue               // no imminent arrival

            if (eta > thresholdMin) {
                Log.d(TAG, "Bus ${fav.no} at $stopCode: eta=$eta min > threshold=$thresholdMin — skipping")
                continue
            }

            // Post notification (BusComingNotifier enforces the per-service
            // cooldown so repeat triggers from the same dwell don't spam).
            BusComingNotifier.notify(
                context    = context,
                stopCode   = stopCode,
                stopName   = fav.stopName,
                busNo      = fav.no,
                etaMinutes = eta,
            )
        }
    }
}
