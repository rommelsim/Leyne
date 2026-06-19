// Pinned Stop widget — live arrivals for one pinned stop.
//
// Layout mirrors LeyneStopWidget.swift (SmallStopView / MediumStopView):
//   Small  (< 200dp wide): stop name header → big hero bus number → hero ETA
//                           → "then Xm" + "+N" chip.
//   Medium (≥ 200dp wide): pin glyph + name → hairline divider → up to 3
//                           service rows (badge + bus no, ETA columns);
//                           arriving row highlighted with wLiveBg fill.
//
// provideGlance contract: ONLY reads cached SharedPreferences; never does
// network. The network path is WidgetRefreshWorker → LtaApiClient (background)
// and the Dart WidgetBridge (pushArrivals). This keeps the Glance frame fast
// and avoids StrictMode / Glance threading violations that would arise from
// network inside provideContent.
//
// Staleness rules (mirroring iOS convention):
//   fetchedAt > 5 min ago  → rows suppressed, hero shows "—"
//   fetchedAt 90 s – 5 min → ETA in wDim (slightly stale, still indicative)
//   fetchedAt < 90 s       → ETA in wFg  (fresh)

package com.leyne.leyne.widget

import com.leyne.leyne.R

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.unit.ColorProvider

// ─── Staleness sealed type ────────────────────────────────────────────────────
// Defined here and used by LeyneFavServiceWidget (same package, internal access).

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

// ─── Widget ───────────────────────────────────────────────────────────────────

class LeyneStopWidget : GlanceAppWidget() {

    // Two responsive breakpoints matching the provider XML sizes.
    // Glance selects the largest that fits the cell allocation.
    override val sizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),   // small  (2×2)
            DpSize(250.dp, 110.dp),   // medium (4×2)
        )
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val repo       = WidgetDataRepository(context)
        val widgetId   = GlanceAppWidgetManager(context).getAppWidgetId(id)
        val pins       = repo.getPins()
        val configCode = repo.getConfiguredStopCode(widgetId)
        val stop       = pins.firstOrNull { it.code == configCode } ?: pins.firstOrNull()
        val snapshot   = stop?.let { repo.getArrivals(it.code) }
        val state      = arrivalsState(snapshot)

        provideContent {
            val size    = LocalSize.current
            val isSmall = size.width < 200.dp

            GlanceTheme {
                val rootMod = GlanceModifier
                    .fillMaxSize()
                    .background(wBg)
                    .cornerRadius(16.dp)
                    .padding(12.dp)
                    .run {
                        if (stop != null) {
                            clickable(
                                actionStartActivity(
                                    deepLinkIntent(context, "lyne://stop/${stop.code}")
                                )
                            )
                        } else this
                    }

                Box(modifier = rootMod) {
                    when {
                        stop == null -> StopEmptyContent(context)
                        isSmall      -> SmallStopContent(stop, state)
                        else         -> MediumStopContent(stop, state)
                    }
                }
            }
        }
    }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

@Composable
private fun StopEmptyContent(context: Context) {
    Column(
        modifier             = GlanceModifier.fillMaxSize(),
        verticalAlignment    = Alignment.CenterVertically,
        horizontalAlignment  = Alignment.CenterHorizontally,
    ) {
        Text(
            text  = context.getString(R.string.widget_no_pins),
            style = TextStyle(
                color      = wFg,
                fontSize   = 13.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 2,
        )
    }
}

// ─── Small layout ─────────────────────────────────────────────────────────────

@Composable
private fun SmallStopContent(stop: PinnedStop, state: ArrivalDisplayState) {
    // Expired data: show no buses — user sees the "—" hero and knows to refresh.
    val rows     = if (state is ArrivalDisplayState.Expired) emptyList() else state.rows
    val next     = rows.firstOrNull()
    val arriving = next != null && next.mon1 && (next.eta1 ?: 99) <= 1

    Column(
        modifier          = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text  = stop.name,
            style = TextStyle(
                color      = wFg,
                fontSize   = 13.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )

        Spacer(GlanceModifier.height(4.dp))

        if (next == null) {
            // No arrivals / expired — placeholder dash.
            Text(
                text  = "—",
                style = TextStyle(color = wDim, fontSize = 40.sp),
            )
        } else {
            // Hero bus number
            Text(
                text  = next.no,
                style = TextStyle(color = wFg, fontSize = 24.sp, fontWeight = FontWeight.Bold),
            )

            // Hero ETA
            val heroLabel = fmtEta(next.mon1, next.eta1)
            val etaColor  = etaTextColor(state, arriving)
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text  = heroLabel,
                    style = TextStyle(
                        color      = etaColor,
                        fontSize   = if (heroLabel == "Arr") 30.sp else 40.sp,
                        fontWeight = if (arriving) FontWeight.Bold else FontWeight.Medium,
                    ),
                )
                if (heroLabel != "Arr" && next.eta1 != null) {
                    Spacer(GlanceModifier.width(3.dp))
                    Text(
                        text  = "min",
                        style = TextStyle(color = wDim, fontSize = 13.sp),
                    )
                }
            }

            Spacer(GlanceModifier.defaultWeight())

            // Footer: "then Xm" + "+N" chip
            Row(
                modifier          = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (next.eta2 != null) {
                    val thenLabel = if (next.eta2 <= 0) "then Arr" else "then ${next.eta2}m"
                    Text(
                        text  = thenLabel,
                        style = TextStyle(color = wDim, fontSize = 10.sp),
                    )
                }
                Spacer(GlanceModifier.defaultWeight())
                if (rows.size > 1) {
                    Text(
                        text  = "+${rows.size - 1}",
                        style = TextStyle(
                            color      = wFaint,
                            fontSize   = 10.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
            }
        }
    }
}

// ─── Medium layout ────────────────────────────────────────────────────────────

@Composable
private fun MediumStopContent(stop: PinnedStop, state: ArrivalDisplayState) {
    val rows = (if (state is ArrivalDisplayState.Expired) emptyList() else state.rows).take(3)

    Column(
        modifier          = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.Top,
    ) {
        // Header: pin glyph + stop name
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = "📍", style = TextStyle(fontSize = 12.sp))
            Spacer(GlanceModifier.width(5.dp))
            Text(
                text  = stop.name,
                style = TextStyle(color = wFg, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
        }

        // Hairline divider
        Spacer(GlanceModifier.height(6.dp))
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(1.dp)
                .background(wLine),
        ) {}
        Spacer(GlanceModifier.height(4.dp))

        if (rows.isEmpty()) {
            Spacer(GlanceModifier.defaultWeight())
            Text(
                text     = "No live arrivals",
                modifier = GlanceModifier.fillMaxWidth(),
                style    = TextStyle(color = wDim, fontSize = 12.sp),
            )
            Spacer(GlanceModifier.defaultWeight())
        } else {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                rows.forEach { row ->
                    StopServiceRow(row = row, state = state)
                    Spacer(GlanceModifier.height(2.dp))
                }
            }
        }
    }
}

// ─── Service row (medium layout) ──────────────────────────────────────────────

@Composable
private fun StopServiceRow(row: ArrivalRow, state: ArrivalDisplayState) {
    val arriving = row.mon1 && (row.eta1 ?: 99) <= 1

    // background() does not accept a nullable ColorProvider, so branch on
    // two fully-formed modifier chains instead of a conditional .background().
    val rowMod = if (arriving) {
        GlanceModifier
            .fillMaxWidth()
            .background(wLiveBg)
            .cornerRadius(8.dp)
            .padding(vertical = 4.dp, horizontal = 6.dp)
    } else {
        GlanceModifier
            .fillMaxWidth()
            .cornerRadius(8.dp)
            .padding(vertical = 4.dp, horizontal = 6.dp)
    }

    Row(
        modifier          = rowMod,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        InkServiceBadge(no = row.no, compact = true)
        Spacer(GlanceModifier.defaultWeight())
        StopEtaColumns(row = row, state = state, heroFontSize = 22.sp)
    }
}

// ─── Ink-filled service badge (internal — shared with LeyneFavServiceWidget) ──

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

// ─── ETA columns (hero + two follow-ups) ─────────────────────────────────────

@Composable
internal fun StopEtaColumns(
    row: ArrivalRow,
    state: ArrivalDisplayState,
    heroFontSize: androidx.compose.ui.unit.TextUnit = 22.sp,
) {
    val arriving  = row.mon1 && (row.eta1 ?: 99) <= 1
    val heroLabel = if (state is ArrivalDisplayState.Expired) "—" else fmtEta(row.mon1, row.eta1)
    val etaColor  = etaTextColor(state, arriving)

    Row(verticalAlignment = Alignment.Bottom) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text  = heroLabel,
                style = TextStyle(
                    color      = etaColor,
                    // "Arr" renders a touch smaller than a numeric ETA. Compute
                    // via .value/.sp rather than TextUnit.times(Float), which the
                    // Glance text DSL doesn't reliably expose.
                    fontSize   = if (heroLabel == "Arr") (heroFontSize.value * 0.78f).sp else heroFontSize,
                    fontWeight = if (arriving) FontWeight.Bold else FontWeight.Medium,
                ),
            )
            if (heroLabel != "Arr" && heroLabel != "—") {
                Spacer(GlanceModifier.width(2.dp))
                Text(text = "min", style = TextStyle(color = wDim, fontSize = 9.sp))
            }
        }

        if (state !is ArrivalDisplayState.Expired) {
            listOfNotNull(row.eta2, row.eta3).take(2).forEach { m ->
                Spacer(GlanceModifier.width(6.dp))
                Text(
                    text  = if (m <= 0) "Arr" else "$m",
                    style = TextStyle(color = wFaint, fontSize = 13.sp),
                )
            }
        }
    }
}
