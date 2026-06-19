// GlanceAppWidgetReceiver for the Pinned Stop widget.
//
// Responsibilities:
//   • Binds the GlanceAppWidget implementation to the AppWidgetProvider lifecycle.
//   • Starts WidgetRefreshWorker when the first instance is placed on the home
//     screen (onEnabled), and cancels it when the last instance is removed
//     (onDisabled) — avoids useless background fetches when no widget is showing.
//
// The Dart WidgetBridge pokes this receiver via HomeWidget.updateWidget() after
// writing new data, which triggers onUpdate → Glance's own update flow without
// going through the worker. The worker is the backstop when the app is closed.

package com.leyne.leyne.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetReceiver

class LeyneStopWidgetReceiver : GlanceAppWidgetReceiver() {

    override val glanceAppWidget = LeyneStopWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // First Stop widget placed — start the 15-min background refresh.
        WidgetRefreshWorker.enqueue(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Last Stop widget removed. Cancel the worker; LeyneFavServiceWidgetReceiver
        // will re-enqueue on its next onEnabled if Fav widgets remain.
        // WorkManager's KEEP policy means a redundant enqueue is safe.
        WidgetRefreshWorker.cancel(context)
    }
}
