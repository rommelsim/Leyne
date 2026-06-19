// Favourite Service widget — one favourited {bus, stop} pinned to the home screen.
//
// Mirrors LeyneFavServiceWidget.swift / FavWidgetView:
//   Header:  ink-filled service badge  +  "Towards / <dest>"  +  star glyph
//   Divider: 1dp wLine hairline
//   Section: "NEAREST ARRIVAL" eyebrow
//            pin glyph + stop name  |  hero ETA ("Arr" or "Xmin")
//   Follow:  "then X min" / "then Arr" for eta2 + eta3
//
// ETA data comes from the shared arrivals cache (leyne.widget.arrivals.<stopCode>)
// written by both the Dart WidgetBridge and WidgetRefreshWorker. The matching
// row is found by service number — exactly one entry per service number per stop.
//
// Tap deep-links to lyne://stop/<stopCode>/<no> (resolves to that service's
// detail view via the app's DeepLinkService pipeline).
//
// provideGlance reads only SharedPreferences (repo) — never network.

package com.leyne.leyne.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.clickable
import com.leyne.leyne.R
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.layout.*
import androidx.glance.text.*

class LeyneFavServiceWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Single

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val repo        = WidgetDataRepository(context)
        val widgetId    = GlanceAppWidgetManager(context).getAppWidgetId(id)
        val favs        = repo.getFavs()

        val configFavId = repo.getConfiguredFavId(widgetId)
        val fav = if (configFavId != null) {
            favs.firstOrNull { it.id == configFavId } ?: favs.firstOrNull()
        } else {
            favs.firstOrNull()
        }

        val snapshot = fav?.let { repo.getArrivals(it.stopCode) }
        val state    = arrivalsState(snapshot)
        // Expired data: render the hero as "—" (null row) so the widget doesn't
        // mislead the user with a stale countdown. Non-expired: find matching service.
        val row = when (state) {
            is ArrivalDisplayState.Expired -> null
            else -> snapshot?.rows?.firstOrNull { it.no == fav?.no }
        }

        provideContent {
            GlanceTheme {
                val rootMod = GlanceModifier
                    .fillMaxSize()
                    .background(wBg)
                    .cornerRadius(16.dp)
                    .padding(12.dp)
                    .run {
                        if (fav != null) {
                            clickable(
                                actionStartActivity(
                                    deepLinkIntent(
                                        context,
                                        "lyne://stop/${fav.stopCode}/${fav.no}",
                                    )
                                )
                            )
                        } else this
                    }

                Box(modifier = rootMod) {
                    if (fav == null) {
                        FavEmptyContent(context)
                    } else {
                        FavFilledContent(fav = fav, row = row, state = state)
                    }
                }
            }
        }
    }
}

// ─── Filled state ─────────────────────────────────────────────────────────────

@Composable
private fun FavFilledContent(
    fav: FavServiceItem,
    row: ArrivalRow?,
    state: ArrivalDisplayState,
) {
    val arriving = row != null && row.mon1 && (row.eta1 ?: 99) <= 1

    Column(
        modifier          = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.Top,
    ) {
        // ── Header: badge + dest + star ───────────────────────────────────────
        Row(
            modifier          = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Use InkServiceBadge from LeyneStopWidget (same package, internal).
            InkServiceBadge(no = fav.no, compact = false)
            Spacer(GlanceModifier.width(9.dp))

            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text  = "Towards",
                    style = TextStyle(color = wDim, fontSize = 10.sp),
                )
                val destLabel = if (fav.dest.isNotEmpty()) fav.dest else fav.stopName
                Text(
                    text  = destLabel,
                    style = TextStyle(
                        color      = wFg,
                        fontSize   = 14.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )
            }

            Spacer(GlanceModifier.width(4.dp))
            // Star glyph — wDim mirrors iOS star.fill foregroundStyle(wFaint).
            Text(text = "★", style = TextStyle(color = wDim, fontSize = 12.sp))
        }

        // ── Hairline divider ──────────────────────────────────────────────────
        Spacer(GlanceModifier.height(10.dp))
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(1.dp)
                .background(wLine),
        ) {}
        Spacer(GlanceModifier.height(10.dp))

        // ── "NEAREST ARRIVAL" eyebrow ─────────────────────────────────────────
        Text(
            text  = "NEAREST ARRIVAL",
            style = TextStyle(
                color      = wDim,
                fontSize   = 10.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
        Spacer(GlanceModifier.height(4.dp))

        // ── Stop name + hero ETA ───────────────────────────────────────────────
        Row(
            modifier          = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
        ) {
            // Pin glyph + stop name
            Row(
                modifier          = GlanceModifier.defaultWeight(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text = "📍", style = TextStyle(fontSize = 13.sp))
                Spacer(GlanceModifier.width(5.dp))
                Text(
                    text  = fav.stopName,
                    style = TextStyle(
                        color      = wFg,
                        fontSize   = 14.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )
            }

            Spacer(GlanceModifier.width(8.dp))

            // Hero ETA or "—" placeholder
            if (row != null) {
                val heroLabel = fmtEta(row.mon1, row.eta1)
                val etaColor  = etaTextColor(state, arriving)
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text  = heroLabel,
                        style = TextStyle(
                            color      = etaColor,
                            fontSize   = if (heroLabel == "Arr") 26.sp else 34.sp,
                            fontWeight = if (arriving) FontWeight.Bold else FontWeight.Medium,
                        ),
                    )
                    if (heroLabel != "Arr") {
                        Spacer(GlanceModifier.width(2.dp))
                        Text(
                            text  = "min",
                            style = TextStyle(color = wDim, fontSize = 11.sp),
                        )
                    }
                }
            } else {
                // No data / expired
                Text(
                    text  = "—",
                    style = TextStyle(color = wFaint, fontSize = 26.sp),
                )
            }
        }

        // ── Follow-up ETAs ("then X min") ─────────────────────────────────────
        if (row != null) {
            val followUps = listOfNotNull(row.eta2, row.eta3).take(2)
            if (followUps.isNotEmpty()) {
                Spacer(GlanceModifier.height(2.dp))
                Row(
                    modifier            = GlanceModifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.End,
                ) {
                    followUps.forEachIndexed { idx, m ->
                        if (idx > 0) Spacer(GlanceModifier.width(10.dp))
                        Text(
                            text  = if (m <= 0) "then Arr" else "then $m min",
                            style = TextStyle(color = wFaint, fontSize = 11.sp),
                        )
                    }
                }
            }
        }

        Spacer(GlanceModifier.defaultWeight())
    }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

@Composable
private fun FavEmptyContent(context: Context) {
    Column(
        modifier             = GlanceModifier.fillMaxSize(),
        verticalAlignment    = Alignment.CenterVertically,
        horizontalAlignment  = Alignment.CenterHorizontally,
    ) {
        Text(
            text  = context.getString(R.string.widget_no_favs),
            style = TextStyle(
                color      = wFg,
                fontSize   = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 2,
        )
    }
}
