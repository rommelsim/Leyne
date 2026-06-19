// Nearest Stop widget — shows the single closest stop the app resolved from
// the user's location. No network, no configuration activity.
//
// Mirrors LeyneNearbyWidget.swift / NearestWidgetView:
//   • "NEAREST STOP" eyebrow + pin glyph
//   • Stop name in bold (2 lines max — Glance has no minimumScaleFactor)
//   • "Stop XXXXX" stop-code line in wDim
//
// The Dart WidgetBridge.pushNearby() writes the nearby key whenever the app
// gets a fresh location fix, then HomeWidget.updateWidget(nearbyReceiver) pokes
// this receiver → Glance redraw. No periodic worker needed.
//
// Tap deep-links to lyne://stop/<code>, or lyne:// root when no stop is set.

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

class LeyneNearbyWidget : GlanceAppWidget() {

    // Single size — provider XML sets resizeMode=none.
    override val sizeMode = SizeMode.Single

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val repo   = WidgetDataRepository(context)
        val nearby = repo.getNearby()

        provideContent {
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .background(wBg)
                        .cornerRadius(16.dp)
                        .padding(12.dp)
                        .clickable(
                            actionStartActivity(
                                deepLinkIntent(
                                    context,
                                    if (nearby != null) "lyne://stop/${nearby.code}" else "lyne://",
                                )
                            )
                        ),
                ) {
                    if (nearby != null) {
                        FilledNearbyContent(nearby)
                    } else {
                        EmptyNearbyContent(context)
                    }
                }
            }
        }
    }
}

// ─── Filled state ─────────────────────────────────────────────────────────────

@Composable
private fun FilledNearbyContent(nearby: NearbyStop) {
    Column(
        modifier          = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.Top,
    ) {
        // Eyebrow: pin glyph + "NEAREST STOP" label
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = "📍", style = TextStyle(fontSize = 10.sp))
            Spacer(GlanceModifier.width(5.dp))
            Text(
                text  = "NEAREST STOP",
                style = TextStyle(
                    color      = wDim,
                    fontSize   = 9.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }

        Spacer(GlanceModifier.height(8.dp))

        // Stop name — bold, 2-line max
        Text(
            text  = nearby.name,
            style = TextStyle(
                color      = wFg,
                fontSize   = 17.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 2,
        )

        Spacer(GlanceModifier.height(6.dp))

        // Stop code — subtle
        Text(
            text  = "Stop ${nearby.code}",
            style = TextStyle(
                color      = wDim,
                fontSize   = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

@Composable
private fun EmptyNearbyContent(context: Context) {
    Column(
        modifier             = GlanceModifier.fillMaxSize(),
        verticalAlignment    = Alignment.CenterVertically,
        horizontalAlignment  = Alignment.CenterHorizontally,
    ) {
        Text(
            text     = context.getString(R.string.widget_no_nearby),
            style    = TextStyle(
                color      = wFg,
                fontSize   = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 3,
        )
    }
}
