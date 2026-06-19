// Shared Glance helpers for the home-screen widgets.
//
// Extracted from LeyneStopWidget when the Pinned Stop widget was removed —
// these are still used by LeyneFavServiceWidget (arrival freshness shading, ETA
// formatting, the ink-filled service badge), so they live in their own file
// rather than inside any one widget.

package com.leyne.leyne.widget

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.unit.ColorProvider

// ─── Staleness sealed type ────────────────────────────────────────────────────

/**
 * Describes how fresh the cached arrival data is. Used to shade ETAs without
 * passing raw timestamps through Composable call sites.
 */
internal sealed interface ArrivalDisplayState {
    val rows: List<ArrivalRow>
    data class Fresh(override val rows: List<ArrivalRow>)   : ArrivalDisplayState
    data class Stale(override val rows: List<ArrivalRow>)   : ArrivalDisplayState
    data class Expired(override val rows: List<ArrivalRow>) : ArrivalDisplayState
    data object None : ArrivalDisplayState { override val rows = emptyList<ArrivalRow>() }
}

internal fun arrivalsState(snapshot: ArrivalsSnapshot?): ArrivalDisplayState {
    snapshot ?: return ArrivalDisplayState.None
    val ageMs = System.currentTimeMillis() - snapshot.fetchedAt
    return when {
        ageMs > 5 * 60_000L -> ArrivalDisplayState.Expired(snapshot.rows)
        ageMs > 90_000L     -> ArrivalDisplayState.Stale(snapshot.rows)
        else                 -> ArrivalDisplayState.Fresh(snapshot.rows)
    }
}

/**
 * ETA label applying the "timely updates, quiet uncertainty" rule:
 * scheduled-only (mon1=false, eta>0) gets a whisper-quiet "~" prefix — never
 * a prominent warning. Mirrors schedPrefix() + etaLabel() in WidgetShared.swift.
 */
internal fun fmtEta(mon1: Boolean, eta: Int?): String = when {
    eta == null -> "—"
    eta <= 0    -> "Arr"
    !mon1       -> "~$eta"
    else        -> "$eta"
}

/** ETA text colour based on staleness and whether the bus is arriving now. */
internal fun etaTextColor(state: ArrivalDisplayState, arriving: Boolean): ColorProvider =
    if (arriving || state !is ArrivalDisplayState.Stale) wFg else wDim

// ─── Ink-filled service badge (shared with LeyneFavServiceWidget) ─────────────

@Composable
internal fun InkServiceBadge(no: String, compact: Boolean = false) {
    Box(
        modifier = GlanceModifier
            .background(wLive)
            .cornerRadius(7.dp)
            .padding(horizontal = if (compact) 5.dp else 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text  = no,
            style = TextStyle(
                color      = wOnLive,
                fontSize   = if (compact) 13.sp else 15.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}
