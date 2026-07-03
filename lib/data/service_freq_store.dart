// Bus service frequency loader — Service Info screen support.
//
// Port of ios-native/Leyne/WhereSia/WSServiceFreq.swift. DataStore's
// BusServices fetch (LtaBusService.fromJson, see lta_models.dart) drops the
// operating Category + AM/PM frequency-band columns, so this store pages the
// same BusServices endpoint itself (with those fields kept), disk-caches the
// parsed index for a week, and indexes by service number. Self-contained: it
// reuses only LtaConfig, never LtaService, so lta_service.dart / lta_models.dart
// stay untouched — matching the iOS file's own "never invent data" framing.
//
// Note: lta_service.dart intentionally skips disk caching (its own reference
// datasets refetch every cold start — see that file's header, an iOS
// arm64e/path_provider App Store constraint). That constraint doesn't apply
// to plain key-value writes, so this store persists via `shared_preferences`
// (already a dependency, already used the same way by
// lib/services/full_screen_ad_gate.dart and lib/services/alerts_background.dart)
// rather than pulling in path_provider.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'lta_config.dart';

/// One service's operating category + frequency bands, as raw LTA strings
/// ("8-12", "-", or blank) — not yet formatted for display.
@immutable
class ServiceFreq {
  const ServiceFreq({
    required this.serviceNo,
    this.category,
    this.amPeak,
    this.amOffpeak,
    this.pmPeak,
    this.pmOffpeak,
  });

  final String serviceNo;
  final String? category;
  final String? amPeak;
  final String? amOffpeak;
  final String? pmPeak;
  final String? pmOffpeak;

  factory ServiceFreq.fromJson(Map<String, dynamic> j) => ServiceFreq(
    serviceNo: j['ServiceNo'] as String? ?? '',
    category: j['Category'] as String?,
    amPeak: j['AM_Peak_Freq'] as String?,
    amOffpeak: j['AM_Offpeak_Freq'] as String?,
    pmPeak: j['PM_Peak_Freq'] as String?,
    pmOffpeak: j['PM_Offpeak_Freq'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'ServiceNo': serviceNo,
    'Category': category,
    'AM_Peak_Freq': amPeak,
    'AM_Offpeak_Freq': amOffpeak,
    'PM_Peak_Freq': pmPeak,
    'PM_Offpeak_Freq': pmOffpeak,
  };

  @override
  bool operator ==(Object other) =>
      other is ServiceFreq &&
      other.serviceNo == serviceNo &&
      other.category == category &&
      other.amPeak == amPeak &&
      other.amOffpeak == amOffpeak &&
      other.pmPeak == pmPeak &&
      other.pmOffpeak == pmOffpeak;

  @override
  int get hashCode =>
      Object.hash(serviceNo, category, amPeak, amOffpeak, pmPeak, pmOffpeak);

  /// "8-12" → "8–12 min"; blank / "-" → "—". Mirrors WSServiceFreq.band.
  static String band(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == '-') return '—';
    return '${s.replaceAll('-', '–')} min';
  }
}

class ServiceFreqStore {
  ServiceFreqStore({http.Client? client}) : _client = client ?? http.Client();

  /// Singleton — mirrors the Swift `WSServiceFreqStore.shared`. Tests can
  /// construct their own instance with a fake `http.Client`.
  static final ServiceFreqStore shared = ServiceFreqStore();

  final http.Client _client;

  static const String _cacheKey = 'lyne.serviceFreq.cache.v1';

  /// Per-service-number index. Null until the first [freq] call resolves it
  /// (from disk cache or network).
  Map<String, ServiceFreq>? _index;

  /// Dedupes concurrent [freq] callers onto a single in-flight index load.
  Future<void>? _inflight;

  /// Per-request timeout — matches LtaService's timeoutIntervalForRequest.
  static const Duration _timeout = Duration(seconds: 15);

  /// Frequency for a service (first direction encountered wins), or null
  /// when the index has no row for it.
  Future<ServiceFreq?> freq(String serviceNo) async {
    await _ensureIndex();
    return _index?[serviceNo];
  }

  Future<void> _ensureIndex() {
    if (_index != null) return Future.value();
    return _inflight ??= _loadIndex().whenComplete(() => _inflight = null);
  }

  Future<void> _loadIndex() async {
    final cached = await _loadCache();
    if (cached != null) {
      _index = _indexFrom(cached);
      return;
    }
    List<ServiceFreq> items;
    try {
      items = await _fetchAll();
    } catch (_) {
      items = const [];
    }
    _index = _indexFrom(items);
    if (items.isNotEmpty) await _saveCache(items);
  }

  /// One row per service — a service typically has 2 BusServices rows
  /// (direction 1/2, same freq bands); the first one encountered wins,
  /// matching WSServiceFreqStore.loadIndex.
  static Map<String, ServiceFreq> _indexFrom(List<ServiceFreq> items) {
    final index = <String, ServiceFreq>{};
    for (final f in items) {
      index.putIfAbsent(f.serviceNo, () => f);
    }
    return index;
  }

  // ─── Network — pages BusServices directly (LtaService's BusServices
  // mapper drops these columns, and lta_service.dart isn't touched here) ───

  Future<List<ServiceFreq>> _fetchAll() async {
    final out = <ServiceFreq>[];
    var skip = 0;
    while (true) {
      final uri = LtaConfig.baseUrl.replace(
        pathSegments: [...LtaConfig.baseUrl.pathSegments, 'BusServices'],
        queryParameters: skip > 0 ? {'\$skip': '$skip'} : null,
      );
      final resp = await _client
          .get(
            uri,
            headers: {
              'AccountKey': LtaConfig.accountKey,
              'accept': 'application/json',
            },
          )
          .timeout(_timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) break;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final value = (json['value'] as List?) ?? const [];
      final page = value
          .cast<Map<String, dynamic>>()
          .map(ServiceFreq.fromJson)
          .toList(growable: false);
      out.addAll(page);
      if (page.length < LtaConfig.pageSize) break;
      skip += LtaConfig.pageSize;
      // Safety bound — matches WSServiceFreqStore.swift's fetchAll.
      if (skip > 20000) break;
    }
    return out;
  }

  // ─── Disk cache (SharedPreferences — see file header) ───────────────────

  Future<List<ServiceFreq>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAtMs = decoded['savedAt'] as int?;
      if (savedAtMs == null) return null;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
      if (DateTime.now().difference(savedAt) >=
          LtaConfig.referenceCacheMaxAge) {
        return null; // stale — refetch
      }
      final items = (decoded['items'] as List?) ?? const [];
      return items
          .cast<Map<String, dynamic>>()
          .map(ServiceFreq.fromJson)
          .toList(growable: false);
    } catch (_) {
      return null; // corrupt / missing cache — treat as absent
    }
  }

  Future<void> _saveCache(List<ServiceFreq> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((f) => f.toJson()).toList(),
      });
      await prefs.setString(_cacheKey, payload);
    } catch (_) {
      // Best-effort — a failed write just means the next cold start refetches.
    }
  }

  // ─── Test bridges ─────────────────────────────────────────────────────

  @visibleForTesting
  static Map<String, ServiceFreq> indexFromForTest(List<ServiceFreq> items) =>
      _indexFrom(items);

  /// Resets the in-memory index so a test-owned instance re-resolves from
  /// its (mocked) cache/network on the next [freq] call.
  @visibleForTesting
  void resetForTest() {
    _index = null;
    _inflight = null;
  }
}
