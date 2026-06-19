// GlanceAppWidgetReceiver for the Favourite Service widget.
//
// Manages the WidgetRefreshWorker lifecycle in tandem with
// LeyneStopWidgetReceiver: the worker is shared between both widget types
// (it fetches for all configured stop codes). Enqueue on first Fav widget
// placed; cancel when the last one is removed.

package com.leyne.leyne.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetReceiver

class LeyneFavServiceWidgetReceiver : GlanceAppWidgetReceiver() {

    override val glanceAppWidget = LeyneFavServiceWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.enqueue(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetRefreshWorker.cancel(context)
    }
}
