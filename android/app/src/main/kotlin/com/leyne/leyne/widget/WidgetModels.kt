// Data models for Leyne home-screen widgets.
//
// These are plain Kotlin data classes — no Parcelable, no Room. They exist only
// inside the widget process lifetime (parsed from SharedPreferences JSON on every
// provideGlance call, thrown away when the frame is delivered). Keeping them
// lightweight avoids any deserialization framework dependency.
//
// CONTRACT: field names and semantics mirror widget_bridge.dart and
// WidgetShared.swift. If the Dart bridge changes a JSON key the corresponding
// field here must change too (and vice-versa).

package com.leyne.leyne.widget

// ─── Stop / service identity ──────────────────────────────────────────────────

/** A stop the user has pinned. Mirrors WPinnedStop in WidgetShared.swift. */
data class PinnedStop(
    val code: String,
    val name: String,
)

/** The nearest stop resolved from the user's last known location.
 *  Mirrors WNearbyStop in WidgetShared.swift. */
data class NearbyStop(
    val code: String,
    val name: String,
    val walkMin: Int,
)

/** A favourite {service, stop} the user has starred, with stop name + destination
 *  pre-resolved by the Dart bridge (the widget has no stop/route database).
 *  Mirrors WFavService in WidgetShared.swift. */
data class FavServiceItem(
    val no: String,
    val stopCode: String,
    val stopName: String,
    val dest: String,
) {
    /** "<no>#<stopCode>" — the canonical favour-ID, matching iOS WFavService.id. */
    val id: String get() = "$no#$stopCode"
}

// ─── Arrival data ─────────────────────────────────────────────────────────────

/** One service row inside an ArrivalsSnapshot.
 *
 *  @param no      Service number, e.g. "88".
 *  @param eta1    Minutes to first bus, or null when absent. 0 → "Arr".
 *  @param eta2    Minutes to second bus, or null.
 *  @param eta3    Minutes to third bus, or null (often absent from the API).
 *  @param mon1    True = first arrival is GPS-monitored (live).
 *                 False = scheduled-only → render with a faint "~" prefix per
 *                 the "timely updates, quiet uncertainty" design rule. */
data class ArrivalRow(
    val no: String,
    val eta1: Int?,
    val eta2: Int?,
    val eta3: Int?,
    val mon1: Boolean,
)

/** Cached arrivals for one stop, written by WidgetRefreshWorker and read in
 *  provideGlance. fetchedAt is millis-since-epoch; used to detect stale data
 *  (>90 s → dim ETA, >5 min → show "–"). */
data class ArrivalsSnapshot(
    val fetchedAt: Long,
    val rows: List<ArrivalRow>,
)
