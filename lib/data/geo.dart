// Geo helpers — currently just haversine distance.
//
// Direct port of haversine() in legacy/ios-native/Lyne/DataStore.swift.
// Same R (Earth's mean radius in metres), same formula. Returns metres.

import 'dart:math' as math;

/// Great-circle distance between two (lat, lon) pairs in metres.
/// Inputs are degrees.
double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // mean Earth radius, metres
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Walking-time estimate at ~5 km/h (matches legacy's `d / 80` per-metre).
/// Min 1 minute so a stop that's 30m away still rounds up sensibly.
int walkMinutesFor(double distanceMetres) =>
    math.max(1, (distanceMetres / 80).round());
