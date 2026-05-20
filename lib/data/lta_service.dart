// Async LTA DataMall client + on-disk cache for the bulk reference datasets.
//
// Port of legacy/ios-native/Lyne/LTAService.swift. Behaviour parity:
//   • Bus Arrival v3 — single request, no URLCache.
//   • Bus Stops / Bus Services / Bus Routes — paginated by $skip=500, fetched
//     in concurrent windows of 6 pages per wave, disk-cached weekly.
//   • Same 80,000-row safety bound on paged datasets.
//
// Dart equivalents:
//   URLSession            → http.Client with custom timeout
//   TaskGroup             → Future.wait over a window
//   FileManager.urls(.caches) → path_provider.getApplicationCacheDirectory()

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

  /// Pages fetched concurrently per wave (matches the Swift connection pool).
  static const int _pageWindow = 6;

  /// Per-request timeout. Mirrors the Swift session's
  /// timeoutIntervalForRequest = 15.
  static const Duration _timeout = Duration(seconds: 15);

  /// On-disk cache directory. Created lazily; both platforms route this to
  /// the system cache location (auto-evictable under storage pressure).
  Directory? _cacheDirCached;
  Future<Directory> _cacheDir() async {
    if (_cacheDirCached != null) return _cacheDirCached!;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/LTA');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDirCached = dir;
    return dir;
  }

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

  Future<List<LtaBusStop>> busStops() => _cachedOrFetch(
        cacheName: 'BusStops',
        path: 'BusStops',
        fromJson: LtaBusStop.fromJson,
        toJson: (e) => e.toJson(),
      );

  Future<List<LtaBusService>> busServices() => _cachedOrFetch(
        cacheName: 'BusServices',
        path: 'BusServices',
        fromJson: LtaBusService.fromJson,
        toJson: (e) => e.toJson(),
      );

  Future<List<LtaBusRoute>> busRoutes() => _cachedOrFetch(
        cacheName: 'BusRoutes',
        path: 'BusRoutes',
        fromJson: LtaBusRoute.fromJson,
        toJson: (e) => e.toJson(),
      );

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

  Future<List<T>> _cachedOrFetch<T>({
    required String cacheName,
    required String path,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    final cached = await _loadCache(cacheName, fromJson);
    if (cached != null) return cached;

    final fresh = await _fetchAllPaged<T>(path, fromJson);
    await _saveCache(cacheName, fresh, toJson);
    return fresh;
  }

  Future<List<T>?> _loadCache<T>(
    String name,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final file = File('${(await _cacheDir()).path}/$name.json');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(j['savedAt'] as String? ?? '');
      if (savedAt == null) return null;
      if (DateTime.now().difference(savedAt) >= LtaConfig.referenceCacheMaxAge) {
        return null;
      }
      final items = (j['items'] as List?) ?? const [];
      return items.cast<Map<String, dynamic>>().map(fromJson).toList();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('LTA cache miss ($name): $e');
      }
      return null;
    }
  }

  Future<void> _saveCache<T>(
    String name,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    try {
      final file = File('${(await _cacheDir()).path}/$name.json');
      final payload = {
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'items': items.map(toJson).toList(),
      };
      // Atomic-ish write: temp file then rename, so a crash mid-write
      // doesn't leave a corrupt cache.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload));
      await tmp.rename(file.path);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('LTA cache save failed ($name): $e');
      }
    }
  }
}
