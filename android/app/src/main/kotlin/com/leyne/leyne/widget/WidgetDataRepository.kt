// WidgetDataRepository — single source of truth for widget data.
//
// All reads and writes go through the SharedPreferences file managed by the
// home_widget Flutter plugin (es.antonborri.home_widget.HomeWidgetPlugin). The
// Dart app writes the "leyne.widget.*" keys; this repository reads them plus
// the per-instance config keys that the picker activities write.
//
// JSON is parsed with org.json (bundled in Android). No new dependencies.
//
// Thread safety: SharedPreferences is safe to read from any thread. Writes use
// the synchronous commit() because they come from the picker activities
// (already off the main thread in a coroutine/runBlocking scope) and must be
// durable before the activity finishes.

package com.leyne.leyne.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

// ─── Deep-link helper ─────────────────────────────────────────────────────────

/**
 * Builds an ACTION_VIEW Intent for a lyne:// deep link that MainActivity
 * can handle. FLAG_ACTIVITY_NEW_TASK is required because the launch context
 * originates from a RemoteViews / Glance action (no Activity back stack).
 */
fun deepLinkIntent(context: Context, uri: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        .setClassName(context, "com.leyne.leyne.MainActivity")
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

// ─── Repository ───────────────────────────────────────────────────────────────

class WidgetDataRepository(private val context: Context) {

    // The SharedPreferences instance the home_widget plugin writes to.
    // Accessing it is fast / synchronous — safe inside provideGlance.
    private val prefs get() = HomeWidgetPlugin.getData(context)

    // ── Dart-written keys (READ-ONLY from Kotlin) ────────────────────────────

    private fun getString(key: String): String? =
        prefs.getString(key, null).takeIf { !it.isNullOrEmpty() }

    /**
     * Returns the list of stops the user has pinned, or an empty list when the
     * key is absent or unparseable. Mirrors leyne.widget.pins.
     */
    fun getPins(): List<PinnedStop> = runCatching {
        val json = getString("leyne.widget.pins") ?: return emptyList()
        val arr = JSONArray(json)
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(PinnedStop(code = o.getString("code"), name = o.getString("name")))
            }
        }
    }.getOrElse { emptyList() }

    /**
     * Returns the nearest stop, or null when absent / location not yet resolved.
     * Mirrors leyne.widget.nearby.
     */
    fun getNearby(): NearbyStop? = runCatching {
        val json = getString("leyne.widget.nearby") ?: return null
        val o = JSONObject(json)
        NearbyStop(
            code    = o.getString("code"),
            name    = o.getString("name"),
            walkMin = o.optInt("walkMin", 0),
        )
    }.getOrElse { null }

    /**
     * Returns the user's favourited services, or an empty list.
     * Mirrors leyne.widget.favs.
     */
    fun getFavs(): List<FavServiceItem> = runCatching {
        val json = getString("leyne.widget.favs") ?: return emptyList()
        val arr = JSONArray(json)
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(FavServiceItem(
                    no       = o.getString("no"),
                    stopCode = o.getString("stopCode"),
                    stopName = o.getString("stopName"),
                    dest     = o.optString("dest", ""),
                ))
            }
        }
    }.getOrElse { emptyList() }

    /**
     * Returns the cached arrivals for [stopCode], or null when the key is
     * absent / not yet fetched. Mirrors leyne.widget.arrivals.<stopCode>.
     */
    fun getArrivals(stopCode: String): ArrivalsSnapshot? = runCatching {
        val json = getString("leyne.widget.arrivals.$stopCode") ?: return null
        val o = JSONObject(json)
        val rowArr = o.getJSONArray("rows")
        val rows = buildList {
            for (i in 0 until rowArr.length()) {
                val r = rowArr.getJSONObject(i)
                add(ArrivalRow(
                    no   = r.getString("no"),
                    eta1 = r.optNullableInt("eta1"),
                    eta2 = r.optNullableInt("eta2"),
                    eta3 = r.optNullableInt("eta3"),
                    mon1 = r.optBoolean("mon1", true),
                ))
            }
        }
        ArrivalsSnapshot(
            fetchedAt = o.getLong("fetchedAt"),
            rows      = rows,
        )
    }.getOrElse { null }

    // ── Per-instance config keys (READ + WRITE from picker activities) ────────

    /**
     * Returns the stop code configured for [appWidgetId], or null when the
     * user hasn't picked one yet (caller falls back to the first pin).
     */
    fun getConfiguredStopCode(appWidgetId: Int): String? =
        getString("leyne.widget.stop.$appWidgetId")

    /** Persists the user's stop choice for [appWidgetId]. */
    fun saveConfiguredStopCode(appWidgetId: Int, code: String) {
        prefs.edit().putString("leyne.widget.stop.$appWidgetId", code).commit()
    }

    /**
     * Returns the fav ID ("<no>#<stopCode>") configured for [appWidgetId], or
     * null (caller falls back to the first fav).
     */
    fun getConfiguredFavId(appWidgetId: Int): String? =
        getString("leyne.widget.fav.$appWidgetId")

    /** Persists the user's fav choice for [appWidgetId]. */
    fun saveConfiguredFavId(appWidgetId: Int, favId: String) {
        prefs.edit().putString("leyne.widget.fav.$appWidgetId", favId).commit()
    }

    // ── Worker-written arrivals ───────────────────────────────────────────────

    /**
     * Writes a fresh [ArrivalsSnapshot] for [stopCode] back into the SAME
     * SharedPreferences store. The Dart bridge and the worker both write to
     * this store so there is one consistent read-path in provideGlance.
     */
    fun writeArrivals(stopCode: String, snapshot: ArrivalsSnapshot) {
        val rowArr = JSONArray()
        snapshot.rows.forEach { r ->
            val o = JSONObject()
            o.put("no", r.no)
            r.eta1?.let { o.put("eta1", it) }
            r.eta2?.let { o.put("eta2", it) }
            r.eta3?.let { o.put("eta3", it) }
            o.put("mon1", r.mon1)
            rowArr.put(o)
        }
        val root = JSONObject()
        root.put("fetchedAt", snapshot.fetchedAt)
        root.put("rows", rowArr)
        prefs.edit().putString("leyne.widget.arrivals.$stopCode", root.toString()).commit()
    }
}

// ─── JSONObject extension ─────────────────────────────────────────────────────

/**
 * Returns the int at [key] as a nullable Int, or null when the key is missing
 * or JSON null. JSONObject.optInt() returns 0 for missing keys, which is
 * ambiguous here (0 = "Arr"), so we check has() first.
 */
private fun JSONObject.optNullableInt(key: String): Int? =
    if (has(key) && !isNull(key)) getInt(key) else null
