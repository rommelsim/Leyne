// GlanceAppWidgetReceiver for the Nearest Stop widget.
//
// This widget has no configuration activity and does not need the arrival
// refresh worker (it shows only the stop identity, not ETAs). The Dart
// WidgetBridge.pushNearby() pokes it directly via HomeWidget.updateWidget().
// No onEnabled/onDisabled overrides needed.

package com.leyne.leyne.widget

import androidx.glance.appwidget.GlanceAppWidgetReceiver

class LeyneNearbyWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = LeyneNearbyWidget()
}
