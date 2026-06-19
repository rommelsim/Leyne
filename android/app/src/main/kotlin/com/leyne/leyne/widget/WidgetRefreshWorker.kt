// WidgetRefreshWorker — periodic background arrival refresh for Glance widgets.
//
// WorkManager fires this every 15 minutes (the minimum WorkManager allows).
// On each run it:
//   1. Collects all stopCodes that any placed widget instance cares about.
//   2. De-duplicates and fetches arrivals from LTA DataMall via LtaApiClient.
//   3. Writes the result back through WidgetDataRepository (same SharedPreferences
//      store the Dart bridge uses) so provideGlance sees fresh data.
//   4. Triggers Glance to redraw all Stop and Fav widget instances.
//
// The Nearby widget has no arrivals and is not touched here — it updates only
// when the Dart side pushes a new nearby stop via WidgetBridge.pushNearby().
//
// Why WorkManager instead of onUpdate / updatePeriodMillis?
// updatePeriodMillis in the provider XML is clamped to 30 min by the OS and
// does not fire when the app is closed. WorkManager gives us reliable 15-min
// cadence (OS may batch slightly), survives app death, and is the pattern
// recommended by the Glance documentation.

package com.leyne.leyne.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        val repo = WidgetDataRepository(context)
        val glanceManager = GlanceAppWidgetManager(context)

        // ── 1. Collect all stop codes that placed widget instances need ────────

        val stopCodes = mutableSetOf<String>()

        // Fav widget instances: use the configured fav or fall back to the first fav.
        val favs = repo.getFavs()
        val favInstances = glanceManager.getGlanceIds(LeyneFavServiceWidget::class.java)
        for (glanceId in favInstances) {
            val widgetId = glanceManager.getAppWidgetId(glanceId)
            val favId = repo.getConfiguredFavId(widgetId)
            val fav = if (favId != null) {
                favs.firstOrNull { it.id == favId } ?: favs.firstOrNull()
            } else {
                favs.firstOrNull()
            }
            fav?.stopCode?.let { stopCodes += it }
        }

        // ── 2. Fetch arrivals (parallel per stop) ─────────────────────────────

        withContext(Dispatchers.IO) {
            stopCodes.forEach { code ->
                val rows = LtaApiClient.fetch(code)
                if (rows.isNotEmpty()) {
                    repo.writeArrivals(
                        code,
                        ArrivalsSnapshot(
                            fetchedAt = System.currentTimeMillis(),
                            rows      = rows,
                        ),
                    )
                }
                // If the fetch returned empty (network error, no buses), leave the
                // existing cached snapshot in place — the staleness logic in the
                // widget view will dim or blank the ETA. Never overwrite with empty.
            }
        }

        // ── 3. Trigger Glance redraws ─────────────────────────────────────────

        // updateAll is a suspend function that enqueues a RemoteViews update for
        // every placed instance of that widget class. Called here in the worker's
        // coroutine scope — safe, no runBlocking needed.
        LeyneFavServiceWidget().updateAll(context)

        return Result.success()
    }

    // ── Work scheduling ───────────────────────────────────────────────────────

    companion object {
        private const val WORK_NAME = "leyne.widgetRefresh"

        /**
         * Enqueues the periodic worker with KEEP policy (don't re-schedule if
         * one is already queued). Safe to call multiple times (e.g. from
         * onEnabled in both Stop and Fav receivers).
         */
        fun enqueue(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(
                repeatInterval = 15,
                repeatIntervalTimeUnit = TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        /** Cancels the periodic worker (called when the last widget is removed). */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
