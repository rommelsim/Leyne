// Async LTA DataMall client for the bulk reference datasets.
//
// Port of legacy/ios-native/Lyne/LTAService.swift. Behaviour parity for
// fetching:
//   • Bus Arrival v3 — single request, no URLCache.
//   • Bus Stops / Bus Services / Bus Routes — paginated by $skip=500,
//     fetched in concurrent windows of 4 pages per wave (LTA's
//     spike-arrest limit). Same 80,000-row safety bound.
//
// Disk caching is intentionally NOT implemented in the Flutter port —
// the canonical path_provider plugin transitively pulls in
// path_provider_foundation → objective_c, whose iOS framework binary
// ships an arm64e-only architecture slice. That conflicts with Flutter
// engine's arm64-only Flutter.framework and causes App Store upload
// rejections (ITMS-91080). Re-fetching ~5500 stops + ~600 services on
// each cold start (~200KB JSON, ~3-5s on cellular) is the acceptable
// trade-off vs. the alternative. If a future Flutter / path_provider
// release publishes objective_c with both arm64 and arm64e slices, this
// file can be reverted to disk-caching from this file's git history.
//
// Dart equivalents for the network bits:
//   URLSession  → http.Client with custom timeout
//   TaskGroup   → Future.wait over a window

import 'dart:async';
import 'dart:convert';
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
  LtaService({http.Client? client}) : _client = client ?? http.Client();

  /// Singleton matching the Swift `LTAService.shared`. Tests can construct
  /// their own instance with a mock `http.Client`.
  static final LtaService shared = LtaService();

  final http.Client _client;

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
      queryParameters: {
        'BusStopCode': stopCode,
        'ServiceNo': ?serviceNo,
      },
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

  // ─── Internal helpers ──────────────────────────────────────

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final resp = await _client.get(
      uri,
      headers: {
        'AccountKey': LtaConfig.accountKey,
        'accept': 'application/json',
      },
    ).timeout(_timeout);
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
    final out = <T>[];
    var base = 0;
    while (true) {
      final skips = List.generate(
          _pageWindow, (i) => base + i * LtaConfig.pageSize);
      final pages = await Future.wait(
        skips.map((skip) async {
          final json = await _get(_pageUri(path, skip));
          final value = (json['value'] as List?) ?? const [];
          return value
              .cast<Map<String, dynamic>>()
              .map(fromJson)
              .toList(growable: false);
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

}
