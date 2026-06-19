// LTA DataMall v3 BusArrival client — plain HttpURLConnection, no OkHttp.
//
// Mirrors the WLTA enum in WidgetShared.swift: same endpoint, same ISO-8601
// arrival time parsing, same monitored-flag extraction. This client is ONLY
// called from WidgetRefreshWorker.doWork(); it is never called inside
// provideGlance (which must not do I/O — it is called on the main thread by
// the Glance framework and must return a UI tree synchronously from cached data).
//
// API reference: https://datamall.lta.gov.sg/content/dam/datamall/datasets/
//   LTA_DataMall_API_User_Guide.pdf  (BusArrivalv3, p. 14)
//
// Response shape (only the fields we consume):
// {
//   "Services": [
//     {
//       "ServiceNo": "88",
//       "NextBus":  { "EstimatedArrival": "2026-06-19T08:31:02+08:00", "Monitored": 1 },
//       "NextBus2": { "EstimatedArrival": "2026-06-19T08:40:17+08:00", "Monitored": 0 },
//       "NextBus3": { "EstimatedArrival": "" }
//     }
//   ]
// }

package com.leyne.leyne.widget

import com.leyne.leyne.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import javax.net.ssl.HttpsURLConnection
import kotlin.math.max

object LtaApiClient {

    private const val BASE_URL =
        "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival"
    private const val TIMEOUT_MS = 12_000

    /**
     * Fetches live arrivals for [stopCode] from LTA DataMall v3.
     *
     * Returns a list of [ArrivalRow] sorted by eta1 (ascending), mirroring the
     * iOS WLTA.arrivals sort. Returns an empty list on any network/parse error
     * (the widget degrades gracefully to stale cached data).
     *
     * Runs on [Dispatchers.IO]; suspend-safe to call from a CoroutineWorker.
     */
    suspend fun fetch(stopCode: String): List<ArrivalRow> = withContext(Dispatchers.IO) {
        runCatching {
            val url = URL("$BASE_URL?BusStopCode=$stopCode")
            val conn = url.openConnection() as HttpsURLConnection
            try {
                conn.apply {
                    requestMethod = "GET"
                    setRequestProperty("AccountKey", BuildConfig.LTA_API_KEY)
                    setRequestProperty("accept", "application/json")
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                }
                check(conn.responseCode in 200..299) {
                    "LTA HTTP ${conn.responseCode} for stop $stopCode"
                }
                val body = conn.inputStream.bufferedReader().readText()
                parse(body)
            } finally {
                conn.disconnect()
            }
        }.getOrElse { emptyList() }
    }

    // ─── Parsing ──────────────────────────────────────────────────────────────

    private fun parse(json: String): List<ArrivalRow> {
        val root = JSONObject(json)
        val services = root.optJSONArray("Services") ?: return emptyList()
        return buildList {
            for (i in 0 until services.length()) {
                val svc = services.getJSONObject(i)
                val no = svc.optString("ServiceNo").takeIf { it.isNotEmpty() } ?: continue
                val b1 = svc.optJSONObject("NextBus")
                val b2 = svc.optJSONObject("NextBus2")
                val b3 = svc.optJSONObject("NextBus3")
                add(
                    ArrivalRow(
                        no   = no,
                        eta1 = etaMinutes(b1?.optString("EstimatedArrival")),
                        eta2 = etaMinutes(b2?.optString("EstimatedArrival")),
                        eta3 = etaMinutes(b3?.optString("EstimatedArrival")),
                        // Monitored is only meaningful on NextBus (the imminent
                        // arrival). 1 = GPS-live, 0 = scheduled. Absent → assume live
                        // (mirrors iOS: `($0.NextBus.Monitored ?? 1) == 1`).
                        mon1 = (b1?.optInt("Monitored", 1) ?: 1) == 1,
                    )
                )
            }
        }
            .filter { it.eta1 != null }         // drop services with no imminent bus
            .sortedBy { it.eta1 ?: Int.MAX_VALUE }
    }

    // ─── ETA helpers ──────────────────────────────────────────────────────────

    /**
     * Parses an ISO-8601 datetime with offset (e.g. "2026-06-19T08:31:02+08:00")
     * and returns the number of whole minutes until that time.
     * Returns null when [raw] is null, blank, or unparseable (API sends "" for
     * buses with no third arrival).
     * Returns max(0, floor) — 0 means "Arr", matching the Dart bridge's _minutes().
     */
    private fun etaMinutes(raw: String?): Int? {
        if (raw.isNullOrEmpty()) return null
        return runCatching {
            val arrival = OffsetDateTime.parse(raw, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            val nowMs   = System.currentTimeMillis()
            val diffMs  = arrival.toInstant().toEpochMilli() - nowMs
            max(0, (diffMs / 60_000).toInt())
        }.getOrElse { null }
    }
}
