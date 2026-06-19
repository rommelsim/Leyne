package com.leyne.leyne

import android.util.Log
import com.leyne.leyne.geofence.GeoStop
import com.leyne.leyne.geofence.GeofenceManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.leyne.leyne/geofence",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerGeofences" -> {
                    // Dart sends:
                    //   stops:        List<Map<String, Any?>>
                    //                 each map: { code:String, name:String,
                    //                             lat:Double, lon:Double }
                    //   radius:       Double (metres, e.g. 250.0)
                    //   thresholdMin: Int    (e.g. 6)
                    //
                    // Flutter's platform channel encodes Dart double as Java
                    // Double and Dart int as Java Int (or Long for large values).
                    // We cast defensively with Number so both survive.
                    runCatching {
                        @Suppress("UNCHECKED_CAST")
                        val rawStops = call.argument<List<Map<String, Any?>>>("stops")
                            ?: emptyList()

                        val stops = rawStops.map { m ->
                            GeoStop(
                                code = m["code"] as String,
                                name = m["name"] as String,
                                // Dart doubles arrive as Java Double; Dart ints
                                // arrive as Java Int/Long.  Cast via Number so
                                // integer lat/lon values (e.g. exactly 1.0) don't
                                // throw ClassCastException.
                                lat  = (m["lat"]  as Number).toDouble(),
                                lon  = (m["lon"]  as Number).toDouble(),
                            )
                        }

                        val radius       = (call.argument<Any>("radius") as Number).toFloat()
                        val thresholdMin = call.argument<Int>("thresholdMin") ?: 6

                        GeofenceManager.register(this, stops, radius, thresholdMin)
                        result.success(null)
                    }.onFailure { e ->
                        Log.e(TAG, "registerGeofences failed: $e")
                        result.error("GEOFENCE_ERROR", e.message, null)
                    }
                }

                "clearGeofences" -> {
                    GeofenceManager.clear(this)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
