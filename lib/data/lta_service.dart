// Async LTA DataMall client for the bulk reference datasets.
//
// Port of legacy/ios-native/Lyne/LTAService.swift. Behaviour parity for
// fetching:
//   • Bus Arrival v3 — single request, no URLCache.
//   • Bus Stops / Bus Services / Bus Routes — paginated by $skip=500,
//     fetched in concurrent windows of 4 pages per wave (LTA's
//     spike-arrest limit). Same 80,000-row safety bound.
//
// Disk caching for the bulk datasets uses `dart:io` Directory.systemTemp
// directly — on Android that resolves to the app's private cache dir
// (/data/user/0/<pkg>/cache), on iOS the app's tmp dir. Deliberately NOT
// path_provider: that plugin transitively pulls in
// path_provider_foundation → objective_c, whose iOS framework binary
// ships an arm64e-only architecture slice. That conflicts with Flutter
// engine's arm64-only Flutter.framework and causes App Store upload
// rejections (ITMS-91080). Cached rows are served for 7 days (reference
// data changes rarely — LTA republishes on service changes, not daily),
// then refreshed from the network; a failed refresh falls back to the
// stale cache rather than erroring. Only the `shared` singleton caches —
// test instances built around a mock http.Client stay purely in-memory.
//
// Dart equivalents for the network bits:
//   URLSession  → http.Client with custom timeout
//   TaskGroup   → Future.wait over a window

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'lta_config.dart';
import 'lta_models.dart';

class LtaException implements Exception {
  LtaException.badResponse(this.statusCode)
    : message = 'LTA returned HTTP $statusCode',
      decodingDetail = null;
  LtaException.decoding(this.decodingDetail)
    : message = 'Couldn’t read LTA data ($decodingDetail)',
      statusCode = null;

  final String message;
  final int? statusCode;
  final String? decodingDetail;

  @override
  String toString() => message;
}

class LtaService {
  LtaService({http.Client? client, this.diskCache = false})
    : _client = client ?? http.Client();

  /// Singleton matching the Swift `LTAService.shared`. Tests can construct
  /// their own instance with a mock `http.Client` (disk cache stays off so
  /// runs can't bleed into each other through systemTemp).
  static final LtaService shared = LtaService(diskCache: true);

  final http.Client _client;

  /// Whether the bulk reference datasets are cached on disk (see header).
  final bool diskCache;

  /// Bulk-dataset cache freshness window.
  static const Duration _cacheTtl = Duration(days: 7);

  /// Pages fetched concurrently per wave. LTA DataMall enforces a "Spike
  /// arrest" policy of maxBurstMessageCount=4 — any 5th+ request in the
  /// burst window comes back as HTTP 500 with body
  /// `{"fault":{"faultstring":"Spike arrest violation..."}}`. So we cap
  /// the parallel wave at 4 to stay under the burst limit. The legacy
  /// Swift code happened to run with maxConnectionsPerHost=8 but didn't
  /// trip this — likely because URLSession serialised within HTTP/2
  /// streams differently than Dart's http package.
  static const int _pageWindow = 4;

  /// Per-request timeout. Mirrors the Swift session's
  /// timeoutIntervalForRequest = 15.
  static const Duration _timeout = Duration(seconds: 15);

  // ─── Live: Bus Arrival v3 ──────────────────────────────────

  Future<LtaArrivalResponse> busArrival(
    String stopCode, {
    String? serviceNo,
  }) async {
    final uri = LtaConfig.baseUrl.replace(
      pathSegments: [...LtaConfig.baseUrl.pathSegments, 'v3', 'BusArrival'],
      queryParameters: {'BusStopCode': stopCode, 'ServiceNo': ?serviceNo},
    );
    final json = await _get(uri);
    return LtaArrivalResponse.fromJson(json);
  }

  // ─── Bulk reference datasets ───────────────────────────────
  // No disk cache (see file-header note). Each cold start hits the
  // network; the DataStore bootstrap pre-fetches once and holds the
  // result in memory for the rest of the session.

  Future<List<LtaBusStop>> busStops() =>
      _fetchAllPaged('BusStops', LtaBusStop.fromJson);

  Future<List<LtaBusService>> busServices() =>
      _fetchAllPaged('BusServices', LtaBusService.fromJson);

  Future<List<LtaBusRoute>> busRoutes() =>
      _fetchAllPaged('BusRoutes', LtaBusRoute.fromJson);

  // ─── Live: Station Crowd Density (PCDRealTime) ───────────
  /// Per-station crowdedness on a line. `trainLine` is the PCD code,
  /// e.g. "EWL" (not the 2-letter prefix). Returns `{ "value": [...] }`.
  Future<List<LtaStationCrowd>> stationCrowd(String trainLine) async {
    final uri = LtaConfig.baseUrl.replace(
      pathSegments: [...LtaConfig.baseUrl.pathSegments, 'PCDRealTime'],
      queryParameters: {'TrainLine': trainLine},
    );
    final json = await _get(uri);
    final value = (json['value'] as List?) ?? const [];
    return value
        .cast<Map<String, dynamic>>()
        .map(LtaStationCrowd.fromJson)
        .toList(growable: false);
  }

  // ─── Live: Station Crowd Forecast (PCDForecast) ──────────
  /// Crowd forecast for the next ~2 hours on a line. `trainLine` is the PCD
  /// code, e.g. "EWL". Returns the raw parsed forecast list; shape-handling
  /// lives in [LtaStationForecast.parseValueList].
  Future<List<LtaStationForecast>> stationForecast(String trainLine) async {
    final uri = LtaConfig.baseUrl.replace(
      pathSegments: [...LtaConfig.baseUrl.pathSegments, 'PCDForecast'],
      queryParameters: {'TrainLine': trainLine},
    );
    final json = await _get(uri);
    final value = (json['value'] as List?) ?? const [];
    return LtaStationForecast.parseValueList(value);
  }

  // ─── Live: Facilities Maintenance v2 (lift maintenance) ──
  /// Network-wide list of lifts currently under maintenance.
  Future<List<LtaFacilityMaintenance>> facilitiesMaintenance() async {
    final uri = LtaConfig.baseUrl.replace(
      pathSegments: [
        ...LtaConfig.baseUrl.pathSegments,
        'v2',
        'FacilitiesMaintenance',
      ],
    );
    final json = await _get(uri);
    final value = (json['value'] as List?) ?? const [];
    return value
        .cast<Map<String, dynamic>>()
        .map(LtaFacilityMaintenance.fromJson)
        .toList(growable: false);
  }

  // ─── Live: Train Service Alerts (MRT/LRT) ────────────────
  /// Always-on endpoint reporting MRT/LRT line disruptions. `Status` is
  /// 1 (normal) or 2 (disrupted); when normal the affected/messages
  /// lists come back empty.
  Future<LtaTrainAlerts> trainServiceAlerts() async {
    final uri = LtaConfig.baseUrl.replace(
      pathSegments: [...LtaConfig.baseUrl.pathSegments, 'TrainServiceAlerts'],
    );
    final json = await _get(uri);
    final value = json['value'];
    if (value is! Map<String, dynamic>) {
      return const LtaTrainAlerts(
        status: 1,
        affectedSegments: [],
        messages: [],
      );
    }
    return LtaTrainAlerts.fromJson(value);
  }

  // ─── Internal helpers ──────────────────────────────────────

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final resp = await _client
        .get(
          uri,
          headers: {
            'AccountKey': LtaConfig.accountKey,
            'accept': 'application/json',
          },
        )
        .timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LtaException.badResponse(resp.statusCode);
    }
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw LtaException.decoding(e.toString());
    }
  }

  Uri _pageUri(String path, int skip) {
    return LtaConfig.baseUrl.replace(
      pathSegments: [...LtaConfig.baseUrl.pathSegments, path],
      queryParameters: skip > 0 ? {'\$skip': '$skip'} : null,
    );
  }

  Future<List<T>> _fetchAllPaged<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    // Fresh cache → skip the network entirely.
    final cached = await _readCache(path, maxAge: _cacheTtl);
    if (cached != null) {
      return cached.map(fromJson).toList(growable: false);
    }
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchAllPagedRaw(path);
    } catch (e) {
      // Network failed — a stale cache beats an error screen.
      final stale = await _readCache(path, maxAge: null);
      if (stale != null) return stale.map(fromJson).toList(growable: false);
      rethrow;
    }
    await _writeCache(path, rows);
    return rows.map(fromJson).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchAllPagedRaw(String path) async {
    final out = <Map<String, dynamic>>[];
    var base = 0;
    while (true) {
      final skips = List.generate(
        _pageWindow,
        (i) => base + i * LtaConfig.pageSize,
      );
      final pages = await Future.wait(
        skips.map((skip) async {
          final json = await _get(_pageUri(path, skip));
          final value = (json['value'] as List?) ?? const [];
          return value.cast<Map<String, dynamic>>();
        }),
      );

      var reachedEnd = false;
      for (final p in pages) {
        out.addAll(p);
        if (p.length < LtaConfig.pageSize) reachedEnd = true;
      }
      if (reachedEnd) break;
      base += _pageWindow * LtaConfig.pageSize;
      if (base > 80000) break; // safety bound, matches legacy
    }
    return out;
  }

  // ─── Bulk-dataset disk cache ───────────────────────────────

  File _cacheFile(String path) =>
      File('${Directory.systemTemp.path}/lta_${path.toLowerCase()}.json');

  /// Rows from the on-disk cache, or null when missing/expired/unreadable.
  /// `maxAge: null` accepts any age (stale-fallback path).
  Future<List<Map<String, dynamic>>?> _readCache(
    String path, {
    required Duration? maxAge,
  }) async {
    if (!diskCache) return null;
    try {
      final f = _cacheFile(path);
      if (!await f.exists()) return null;
      final json = jsonDecode(await f.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final at = DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt());
      if (maxAge != null && DateTime.now().difference(at) > maxAge) return null;
      final rows = json['rows'];
      if (rows is! List) return null;
      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      return null; // corrupt/unreadable cache reads as absent
    }
  }

  Future<void> _writeCache(String path, List<Map<String, dynamic>> rows) async {
    if (!diskCache) return;
    try {
      final f = _cacheFile(path);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'rows': rows}),
      );
      await tmp.rename(f.path); // atomic-ish: never a half-written cache
    } catch (_) {/* cache write is best-effort */}
  }
}
