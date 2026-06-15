// MrtGeo — bundled MRT/LRT station geo dataset loader and proximity helpers.
// No UI. Used by SoftMrtScreen (Phase 2), SoftSearchScreen, and the nearest-
// stations widget path.
//
// Direct Flutter port of ios-native/Leyne/MrtGeo.swift. Behaviour is
// identical: haversine distance via geo.dart, walk minutes at ~5 km/h
// (d / 80, min 1), case-insensitive name + code matching, fail-soft to [].

import 'package:flutter/services.dart';
import 'dart:convert';

import 'geo.dart';

// MARK: - Model

/// A single MRT/LRT station entry from the bundled geo dataset.
/// Interchange stations carry multiple codes (e.g. "EW13" + "NS25" for
/// City Hall), so [codes] is a list and [id] joins them for stable identity.
class MrtGeoStation {
  const MrtGeoStation({
    required this.name,
    required this.codes,
    required this.lat,
    required this.lon,
  });

  final String name;
  final List<String> codes;
  final double lat;
  final double lon;

  /// Stable identity — all line codes concatenated plus the station name.
  String get id => '${codes.join('-')}$name';

  factory MrtGeoStation.fromJson(Map<String, dynamic> json) => MrtGeoStation(
    name: json['name'] as String,
    codes: List<String>.from(json['codes'] as List),
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'codes': codes,
    'lat': lat,
    'lon': lon,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MrtGeoStation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MrtGeoStation($name, $codes)';
}

// MARK: - Nearest result record

/// Result tuple returned by [MrtGeo.nearest].
typedef MrtNearestResult = ({
  MrtGeoStation station,
  int distanceM,
  int walkMin,
});

// MARK: - Dataset loader

/// Lazily loads and caches the bundled `assets/mrt_stations_geo.json` once
/// per process lifetime. All lookups and proximity queries go through
/// [MrtGeo.all].
///
/// Call [MrtGeo.load] once at startup (fire-and-forget is fine — the MRT
/// tab is not the launch tab). Fails soft to [] if the asset is absent or
/// malformed; callers should treat an empty list as a degraded-but-not-
/// crashed state.
class MrtGeo {
  MrtGeo._();

  static List<MrtGeoStation> _cache = [];

  /// All decoded stations. Returns [] before [load] completes or if load
  /// failed. Callers that want to await readiness should await [load] first.
  static List<MrtGeoStation> get all => _cache;

  // MARK: - Loader

  /// Reads `assets/mrt_stations_geo.json`, decodes, and caches the result.
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Fails soft (logs in debug, returns silently) if the asset is missing
  /// or malformed; [all] will remain [].
  static Future<void> load() async {
    if (_cache.isNotEmpty) return;
    try {
      final raw = await rootBundle.loadString('assets/mrt_stations_geo.json');
      final list = json.decode(raw) as List<dynamic>;
      _cache = list
          .map((e) => MrtGeoStation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, _) {
      assert(() {
        // ignore: avoid_print
        print('MrtGeo.load failed: $e');
        return true;
      }());
      _cache = [];
    }
  }

  // MARK: - Proximity

  /// Returns the [limit] nearest stations to ([lat], [lon]), sorted
  /// ascending by distance. Each result carries the haversine distance in
  /// metres and a walking-time estimate at ~5 km/h.
  ///
  /// Matches iOS [MrtGeo.nearestStations(to:limit:)] exactly.
  static List<MrtNearestResult> nearest({
    required double lat,
    required double lon,
    int limit = 6,
  }) {
    final results = _cache.map((station) {
      final d = haversine(lat, lon, station.lat, station.lon);
      final distM = d.round();
      final walkM = walkMinutesFor(d);
      return (station: station, distanceM: distM, walkMin: walkM);
    }).toList()..sort((a, b) => a.distanceM.compareTo(b.distanceM));

    return results.take(limit).toList();
  }

  // MARK: - Lookup helpers

  /// Returns the station whose [codes] list contains [code] (exact,
  /// case-sensitive — MRT codes are always uppercase in the dataset).
  ///
  /// Matches iOS [MrtGeo.station(forCode:)].
  static MrtGeoStation? stationForCode(String code) {
    for (final s in _cache) {
      if (s.codes.contains(code)) return s;
    }
    return null;
  }

  /// Case-insensitive substring match on station name OR any line code.
  /// Trims leading/trailing whitespace from [query] before matching.
  /// Returns [] for an empty query after trimming.
  ///
  /// Matches iOS [MrtGeo.stations(matching:)].
  static List<MrtGeoStation> matching(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _cache.where((s) {
      if (s.name.toLowerCase().contains(q)) return true;
      return s.codes.any((c) => c.toLowerCase().contains(q));
    }).toList();
  }
}
