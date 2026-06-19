// GeofenceService — Android "bus-coming" geofence alerts (opt-in).
//
// When the user enables "Bus-coming alerts", we register geofences (~250m)
// around every stop they've favourited a service at. When the phone enters one
// of those regions — even with the app closed — a native BroadcastReceiver
// (com.leyne.leyne.geofence.GeofenceBroadcastReceiver) fetches that stop's live
// arrivals and posts a local notification if a favourited bus is within a few
// minutes. The fetch + notify happen entirely in Kotlin (it reuses the widget
// LtaApiClient + the favourites the WidgetBridge already mirrors), so no Dart
// background isolate is involved.
//
// This file owns only the Dart→Kotlin bridge: gathering the favourited stops
// with their coordinates (Kotlin has the favourites but not the lat/lon) and
// telling the native layer to (re)register or clear geofences.
//
// REQUIRES ACCESS_BACKGROUND_LOCATION (Play-scrutinised). The feature is OFF by
// default and gated behind an explicit prominent-disclosure primer — see the
// Bus-coming alerts toggle in the notifications settings. iOS is a no-op
// (geofencing there would use CLLocationManager region monitoring — not built).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/data_store.dart';
import '../state/app_model.dart';

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  static const _channel = MethodChannel('com.leyne.leyne/geofence');

  /// Geofence radius (metres) around each favourited stop.
  static const double _radiusM = 250;

  /// Alert when a favourited bus is at/under this many minutes away.
  static const int _thresholdMin = 6;

  bool get _enabled => !kIsWeb && Platform.isAndroid;

  /// Re-derive the geofence set from current favourites + the master toggle and
  /// push it to the native layer. Clears all geofences when the feature is off
  /// or there's nothing to watch. Safe to call often (toggle change, favourite
  /// change, reference-data ready, cold start).
  Future<void> sync() async {
    if (!_enabled) return;
    try {
      if (!AppModel.shared.busComingAlertsEnabled) {
        await _channel.invokeMethod('clearGeofences');
        return;
      }
      final ds = DataStore.shared;
      final stops = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final f in AppModel.shared.favServices) {
        final code = f.stop;
        if (code == null || seen.contains(code)) continue;
        final s = ds.stopByCode[code];
        if (s == null) continue; // coords not loaded yet — sync again when ready
        seen.add(code);
        stops.add({
          'code': code,
          'name': s.description,
          'lat': s.latitude,
          'lon': s.longitude,
        });
      }
      if (stops.isEmpty) {
        await _channel.invokeMethod('clearGeofences');
        return;
      }
      await _channel.invokeMethod('registerGeofences', {
        'stops': stops,
        'radius': _radiusM,
        'thresholdMin': _thresholdMin,
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[geofence] sync failed: $e');
      }
    }
  }

  /// Tear down all geofences (called when the user turns the feature off).
  Future<void> clear() async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('clearGeofences');
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[geofence] clear failed: $e');
      }
    }
  }
}
