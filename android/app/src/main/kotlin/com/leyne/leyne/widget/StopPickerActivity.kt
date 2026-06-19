// StopPickerActivity — widget configuration activity for the Pinned Stop widget.
//
// Standard AppWidget configuration contract:
//   1. Read EXTRA_APPWIDGET_ID from the launching intent.
//   2. Immediately set RESULT_CANCELED so that backing out (without picking)
//      tells the launcher to remove the placeholder widget slot.
//   3. Present the list of pinned stops in an AlertDialog.
//   4. On pick: persist the choice, trigger a widget redraw, return RESULT_OK
//      with the widget ID so the launcher confirms placement.
//
// No custom layout XML is used — AlertDialog.Builder.setItems() is sufficient
// and avoids an additional res/layout dependency.
//
// Thread note: updateAll() is a suspend function. We use runBlocking here
// because this is an Activity (not already in a coroutine scope) and the
// operation must complete before finish() to ensure the widget shows correct
// data immediately after placement. The call is fast (writes RemoteViews to
// the AppWidgetManager in-process) and does no network work.

package com.leyne.leyne.widget

import android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID
import android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID
import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.glance.appwidget.updateAll
import com.leyne.leyne.R
import kotlinx.coroutines.runBlocking

class StopPickerActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Read the widget ID from the launching intent.
        val widgetId = intent.extras?.getInt(EXTRA_APPWIDGET_ID, INVALID_APPWIDGET_ID)
            ?: INVALID_APPWIDGET_ID

        // Satisfy the contract: back-out cancels placement.
        setResult(RESULT_CANCELED)

        if (widgetId == INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val repo  = WidgetDataRepository(this)
        val pins  = repo.getPins()

        if (pins.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(R.string.widget_pick_stop_title)
                .setMessage(R.string.widget_no_pins)
                .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
                .setOnDismissListener { finish() }
                .show()
            return
        }

        val labels = pins.map { it.name }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle(R.string.widget_pick_stop_title)
            .setItems(labels) { _, which ->
                val chosen = pins[which]

                // Persist the choice into the shared preferences store.
                repo.saveConfiguredStopCode(widgetId, chosen.code)

                // Trigger an immediate redraw so the widget shows the chosen
                // stop the moment it lands on the home screen.
                runBlocking { LeyneStopWidget().updateAll(this@StopPickerActivity) }

                // Return RESULT_OK with the widget ID — launcher confirms placement.
                setResult(
                    RESULT_OK,
                    Intent().putExtra(EXTRA_APPWIDGET_ID, widgetId),
                )
                finish()
            }
            .setOnCancelListener {
                // User dismissed without picking — cancel placement.
                finish()
            }
            .show()
    }
}
