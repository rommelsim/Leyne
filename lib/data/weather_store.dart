// WeatherStore — fetches, resolves, and caches NEA weather for the user's location.
//
// Design mirrors DataStore's TrainAlert refresh pattern:
//   • ChangeNotifier — the Home screen's ListenableBuilder picks up new data.
//   • 15-minute freshness gate — one network hit per 15 min max.
//   • _inflight guard — no concurrent fetches.
//   • Graceful degradation — any failure leaves `snapshot` null; the UI
//     simply omits the weather widget rather than showing an error state.
//   • No location dependency injected — reads LocationService.shared.lastLocation
//     directly, matching how DataStore.updateNearby works.
//
// Called from:
//   • AppModel._onTick() — slow cadence every 60 s (inner gate keeps network quiet).
//   • AppModel.onResume (app lifecycle) — force-refresh on foreground.
//   • SoftHomeScreen.initState() — warm on first render.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'geo.dart';
import 'nea_models.dart';
import 'nea_service.dart';

class WeatherStore extends ChangeNotifier {
  WeatherStore({NeaService? api}) : _api = api ?? NeaService.shared;

  static final WeatherStore shared = WeatherStore();

  final NeaService _api;

  WeatherSnapshot? _snapshot;
  WeatherSnapshot? get snapshot => _snapshot;

  DateTime? _lastFetch;
  bool _inflight = false;

  static const _cacheDuration = Duration(minutes: 15);

  // ─── Public refresh API ───────────────────────────────────────────────────

  /// Called from AppModel._onTick() every 60 s; inner gate keeps actual
  /// network calls at one per 15 min. Also called on app resume (force=true).
  void refreshIfStale({
    bool force = false,
    double? lat,
    double? lon,
  }) {
    if (_inflight) return;
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return;
    }
    // If the existing snapshot is still fresh (can happen when the tick fires
    // but the object was recently populated by a resume fetch), skip.
    if (!force && (_snapshot?.isFresh ?? false)) return;
    _lastFetch = DateTime.now();
    _fetch(lat: lat, lon: lon);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  void _fetch({double? lat, double? lon}) {
    _inflight = true;
    () async {
      try {
        final snap = await _resolve(lat: lat, lon: lon);
        if (snap != null) {
          _snapshot = snap;
          notifyListeners();
        }
      } catch (_) {
        // Any error — network, parse, location absent — is silently swallowed.
        // The widget simply won't show. No user-visible error state.
      } finally {
        _inflight = false;
      }
    }();
  }

  /// Performs the three NEA fetches in parallel and resolves them into a
  /// [WeatherSnapshot] for the given lat/lon. Returns null on any failure
  /// so _fetch can swallow it cleanly.
  Future<WeatherSnapshot?> _resolve({double? lat, double? lon}) async {
    if (lat == null || lon == null) return null;

    final results = await Future.wait([
      _api.twoHourForecast(),
      _api.airTemperature(),
      _api.twentyFourHourForecast(),
    ]);

    final twoHour = results[0] as NeaTwoHourResponse;
    final temperature = results[1] as NeaAirTemperatureResponse;
    final twentyFour = results[2] as Nea24hResponse;

    final nearestArea = _nearestArea(twoHour, lat, lon);
    if (nearestArea == null) return null;

    final forecastText = _forecastForArea(twoHour, nearestArea.name);
    final tempC = _nearestTemperature(temperature, lat, lon);
    if (tempC == null) return null;

    final now = DateTime.now();
    final isNight = now.hour < 6 || now.hour >= 20;
    final condition =
        WeatherCondition.fromForecast(forecastText, isNight: isNight);
    final rainHint = _rainHint(forecastText, twentyFour, now);

    return WeatherSnapshot(
      tempC: tempC,
      forecastText: WeatherCondition.shortLabel(forecastText),
      condition: condition,
      rainHint: rainHint,
      fetchedAt: now,
    );
  }

  // ─── Nearest-area resolution ──────────────────────────────────────────────

  /// Pick the area from area_metadata whose label_location is closest to
  /// the user's position using haversine. Returns null only if the metadata
  /// list is empty (parse failure).
  static NeaAreaMetadata? _nearestArea(
    NeaTwoHourResponse resp,
    double lat,
    double lon,
  ) {
    if (resp.areaMetadata.isEmpty) return null;
    NeaAreaMetadata? best;
    var bestDist = double.infinity;
    for (final area in resp.areaMetadata) {
      final d = haversine(lat, lon, area.lat, area.lon);
      if (d < bestDist) {
        bestDist = d;
        best = area;
      }
    }
    return best;
  }

  /// Look up the forecast string for `areaName` in the items[0].forecasts list.
  static String _forecastForArea(NeaTwoHourResponse resp, String areaName) {
    for (final f in resp.forecasts) {
      if (f.area == areaName) return f.forecast;
    }
    return '';
  }

  // ─── Nearest temperature station ─────────────────────────────────────────

  /// Pick the temperature reading from the station nearest to (lat, lon).
  /// Returns null when either the stations list or readings list is empty.
  static double? _nearestTemperature(
    NeaAirTemperatureResponse resp,
    double lat,
    double lon,
  ) {
    if (resp.stations.isEmpty || resp.readings.isEmpty) return null;

    // Build an id → reading map for O(1) lookup.
    final readingMap = <String, double>{
      for (final r in resp.readings) r.stationId: r.value,
    };

    NeaWeatherStation? best;
    var bestDist = double.infinity;
    for (final st in resp.stations) {
      if (!readingMap.containsKey(st.id)) continue; // no reading for station
      final d = haversine(lat, lon, st.lat, st.lon);
      if (d < bestDist) {
        bestDist = d;
        best = st;
      }
    }
    if (best == null) return null;
    return readingMap[best.id];
  }

  // ─── Rain hint derivation ─────────────────────────────────────────────────

  /// Derive a near-term rain hint string from the 2-hour forecast text and
  /// the 24-hour forecast periods. Logic:
  ///   1. Current 2-hour forecast already contains rain → "rain expected"
  ///   2. 24h forecast has a rain period starting within 8 h → "rain this {period}"
  ///   3. Otherwise → null (no hint shown)
  static String? _rainHint(
    String forecastText,
    Nea24hResponse resp,
    DateTime now,
  ) {
    final nowForecast = forecastText.toLowerCase();
    final currentlyRainy = nowForecast.contains('rain') ||
        nowForecast.contains('thunder') ||
        nowForecast.contains('shower') ||
        nowForecast.contains('drizzle');

    if (currentlyRainy) {
      // Already raining — the condition label covers this; no separate hint.
      return null;
    }

    // Look ahead in the 24h periods for rain within 8 hours.
    final horizon = now.add(const Duration(hours: 8));
    for (final period in resp.periods) {
      final periodStart = _periodStart(period, now);
      if (periodStart == null) continue;
      if (periodStart.isAfter(horizon)) continue; // too far away
      if (periodStart.isBefore(now)) continue; // already past

      final text = period.forecastText.toLowerCase();
      final hasRain = text.contains('rain') ||
          text.contains('thunder') ||
          text.contains('shower') ||
          text.contains('drizzle');
      if (!hasRain) continue;

      // Derive a time-of-day label.
      final label = _periodLabel(period.startHour);
      return 'rain $label';
    }
    return null;
  }

  /// Reconstruct an absolute DateTime for a period's start hour, based on
  /// `now`. NEA's 24h periods use local hour-of-day; we anchor to today
  /// (or tomorrow if the period wraps past midnight).
  static DateTime? _periodStart(Nea24hPeriod period, DateTime now) {
    if (period.startHour < 0 || period.startHour > 23) return null;
    var candidate = DateTime(
        now.year, now.month, now.day, period.startHour);
    // If the candidate is in the past (e.g. now is 14:00, period start is
    // 06:00), advance to next day.
    if (candidate.isBefore(now.subtract(const Duration(minutes: 5)))) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  static String _periodLabel(int startHour) {
    if (startHour < 6) return 'overnight';
    if (startHour < 12) return 'this morning';
    if (startHour < 17) return 'this afternoon';
    if (startHour < 20) return 'this evening';
    return 'tonight';
  }

  // ─── Test bridges (visibleForTesting) ────────────────────────────────────
  // These thin wrappers forward calls to the private static helpers so unit
  // tests can exercise the core logic without going through the full async
  // resolve() path or touching the network.

  @visibleForTesting
  static NeaAreaMetadata? nearestAreaForTest(
          NeaTwoHourResponse resp, double lat, double lon) =>
      _nearestArea(resp, lat, lon);

  @visibleForTesting
  static double? nearestTemperatureForTest(
          NeaAirTemperatureResponse resp, double lat, double lon) =>
      _nearestTemperature(resp, lat, lon);

  @visibleForTesting
  static String? rainHintForTest(
          String forecast, Nea24hResponse resp, DateTime now) =>
      _rainHint(forecast, resp, now);
}
