// OneMap postal-code geocoding — turns a Singapore 6-digit postal code
// into a lat/lon plus a short address label.
//
// Uses OneMap's public elastic-search endpoint. As of 2026 this endpoint
// still answers without an API token: it adds an "Authentication token
// missing" string to the body but returns the real `results` array
// alongside it, so we parse `results` and ignore that field. If OneMap
// ever fully closes the endpoint, geocoding fails gracefully — the caller
// shows a "couldn't find that postal code" state and no other feature is
// affected (bus data comes from LTA, a separate service).

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A geocoded address — the centre point for a postal-code radius search.
class GeoPlace {
  const GeoPlace({
    required this.lat,
    required this.lon,
    required this.label,
    required this.postalCode,
  });

  final double lat;
  final double lon;

  /// Short human label — building name, or block + road name.
  final String label;
  final String postalCode;
}

class GeocodeService {
  GeocodeService({http.Client? client}) : _client = client ?? http.Client();

  /// Singleton — UI uses this; tests can construct with a mock client.
  static final GeocodeService shared = GeocodeService();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 12);

  /// Resolve a 6-digit Singapore postal code to a [GeoPlace], or null if
  /// the code isn't a real address or the lookup fails. Never throws — any
  /// network / parse trouble collapses to null so callers handle one case.
  Future<GeoPlace?> postalCode(String code) async {
    final q = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(q)) return null;
    final uri = Uri.https('www.onemap.gov.sg', '/api/common/elastic/search', {
      'searchVal': q,
      'returnGeom': 'Y',
      'getAddrDetails': 'Y',
      'pageNum': '1',
    });
    try {
      final resp = await _client.get(uri).timeout(_timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = ((json['results'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      if (results.isEmpty) return null;
      // Prefer an entry whose POSTAL matches exactly; fall back to the first.
      final row = results.firstWhere(
        (r) => (r['POSTAL'] as String?) == q,
        orElse: () => results.first,
      );
      final lat = double.tryParse((row['LATITUDE'] as String?) ?? '');
      final lon = double.tryParse((row['LONGITUDE'] as String?) ?? '');
      if (lat == null || lon == null) return null;
      return GeoPlace(lat: lat, lon: lon, label: _labelFrom(row), postalCode: q);
    } catch (_) {
      return null;
    }
  }

  /// A short, readable label: building name when it's a real one, else
  /// block-number + road name. OneMap uses 'NIL' for "no building name".
  static String _labelFrom(Map<String, dynamic> row) {
    String field(String k) => ((row[k] as String?) ?? '').trim();
    final building = field('BUILDING');
    if (building.isNotEmpty && building.toUpperCase() != 'NIL') {
      return _titleCase(building);
    }
    final blk = field('BLK_NO');
    final road = field('ROAD_NAME');
    final joined =
        [if (blk.isNotEmpty) blk, if (road.isNotEmpty) road].join(' ');
    return joined.isEmpty ? 'Singapore' : _titleCase(joined);
  }

  /// OneMap returns ALL-CAPS strings; soften to Title Case for display.
  static String _titleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
