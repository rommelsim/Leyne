// FavPickerActivity — widget configuration activity for the Favourite Service widget.
//
// Same standard AppWidget configuration contract as StopPickerActivity:
//   1. Read EXTRA_APPWIDGET_ID, set RESULT_CANCELED immediately.
//   2. List favourited services in an AlertDialog.
//   3. On pick: save "<no>#<stopCode>" as the fav ID, redraw, return RESULT_OK.
//
// Display label format: "<no> · <stopName>" — same as iOS FavChoiceQuery
// displayRepresentation, so the picker reads consistently across platforms.

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

class FavPickerActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val widgetId = intent.extras?.getInt(EXTRA_APPWIDGET_ID, INVALID_APPWIDGET_ID)
            ?: INVALID_APPWIDGET_ID

        setResult(RESULT_CANCELED)

        if (widgetId == INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val repo = WidgetDataRepository(this)
        val favs = repo.getFavs()

        if (favs.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(R.string.widget_pick_fav_title)
                .setMessage(R.string.widget_no_favs)
                .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
                .setOnDismissListener { finish() }
                .show()
            return
        }

        // "<no> · <stopName>" mirrors the iOS picker label.
        val labels = favs.map { "${it.no} · ${it.stopName}" }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle(R.string.widget_pick_fav_title)
            .setItems(labels) { _, which ->
                val chosen = favs[which]

                // Persist the fav ID ("<no>#<stopCode>").
                repo.saveConfiguredFavId(widgetId, chosen.id)

                runBlocking { LeyneFavServiceWidget().updateAll(this@FavPickerActivity) }

                setResult(
                    RESULT_OK,
                    Intent().putExtra(EXTRA_APPWIDGET_ID, widgetId),
                )
                finish()
            }
            .setOnCancelListener { finish() }
            .show()
    }
}
