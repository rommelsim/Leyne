// Live data repository — mirrors legacy/ios-native/Lyne/DataStore.swift.
//
// Same responsibilities as the Swift store:
//   • Bootstrap: load Bus Stops + Bus Services up front (parallel).
//   • Nearby: rank stops by haversine, cap at 12, derive walk minutes.
//   • Arrivals: per-stop live ETA with 25s freshness, in-flight dedupe.
//   • Search: live across the in-memory stop + service indexes.
//   • Routes: lazy, big dataset, disk-cached (delegated to LtaService).
//   • Live bus position + per-service ETA snapshot.
//
// State management note: I'm using ChangeNotifier (Flutter's lightweight
// observable) rather than streams or a 3rd-party state library, because
// the iOS UI binds with @Published and ChangeNotifier is the closest
// idiomatic Dart equivalent. UI screens in Task #7 bind via
// ListenableBuilder / AnimatedBuilder.

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'geo.dart';
import 'lta_config.dart';
import 'lta_models.dart';
import 'lta_service.dart';
import 'models.dart';

enum LoadState { loading, ready, error }

/// Bootstrap status — loading / ready / error(message).
class ReferenceState {
  const ReferenceState.loading()
      : state = LoadState.loading,
        errorMessage = null;
  const ReferenceState.ready()
      : state = LoadState.ready,
        errorMessage = null;
  const ReferenceState.error(String this.errorMessage)
      : state = LoadState.error;

  final LoadState state;
  final String? errorMessage;
}

enum ArrivalStateKind { loading, loaded, empty, error }

/// Per-stop arrival status.
class ArrivalState {
  const ArrivalState._(this.kind, this.services, this.errorMessage);

  factory ArrivalState.loading() =>
      const ArrivalState._(ArrivalStateKind.loading, [], null);
  factory ArrivalState.loaded(List<Service> services) =>
      ArrivalState._(ArrivalStateKind.loaded, services, null);
  factory ArrivalState.empty() =>
      const ArrivalState._(ArrivalStateKind.empty, [], null);
  factory ArrivalState.error(String message) =>
      ArrivalState._(ArrivalStateKind.error, const [], message);

  final ArrivalStateKind kind;
  final List<Service> services;
  final String? errorMessage;
}

/// One stop on a service's route, augmented for the Detail map.
class RouteStopLive {
  RouteStopLive({
    required this.code,
    required this.name,
    required this.lat,
    required this.lon,
    required this.seq,
  });
  final String code;
  final String name;
  final double lat;
  final double lon;
  final int seq;
}

/// 2D point — provider-neutral so callers can convert to apple_maps_flutter
/// LatLng on iOS or google_maps_flutter LatLng on Android without leaking
/// either dependency into the data layer.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

class RouteInfo {
  RouteInfo({
    required this.stops,
    required this.youIndex,
    this.busIndex,
    this.busCoord,
  });
  final List<RouteStopLive> stops;
  final int youIndex;
  final int? busIndex;
  final GeoPoint? busCoord;
}

/// The relevant slice of the route to draw on the map: from the bus's
/// current position (or an approach window if it's passed/unknown) to just
/// past your stop. Drawing the whole route would connect 40–60 stops with
/// straight lines (LTA has no road geometry).
List<RouteStopLive> journeySegment(RouteInfo r) {
  if (r.stops.isEmpty) return const [];
  final you = r.youIndex.clamp(0, r.stops.length - 1);
  int start;
  final b = r.busIndex;
  if (b != null && b >= 0 && b <= you) {
    start = b;
  } else {
    start = (you - 6).clamp(0, r.stops.length - 1);
  }
  final end = (you + 1).clamp(0, r.stops.length - 1);
  if (start > end) return [r.stops[you]];
  return r.stops.sublist(start, end + 1);
}

class DataStore extends ChangeNotifier {
  DataStore({LtaService? api}) : _api = api ?? LtaService.shared;

  /// Singleton matching the Swift `DataStore.shared`. UI uses this.
  static final DataStore shared = DataStore();

  final LtaService _api;

  ReferenceState _referenceState = const ReferenceState.loading();
  ReferenceState get referenceState => _referenceState;

  List<NearbyStop> _nearby = const [];
  List<NearbyStop> get nearby => _nearby;

  final Map<String, ArrivalState> _arrivals = {};
  Map<String, ArrivalState> get arrivals => _arrivals;

  bool _routesLoaded = false;
  bool get routesLoaded => _routesLoaded;

  /// stopCode → LTA bus stop record. Populated by bootstrap().
  final Map<String, LtaBusStop> _stopByCode = {};
  Map<String, LtaBusStop> get stopByCode => _stopByCode;

  List<LtaBusService> _services = const [];
  List<LtaBusRoute>? _routesAll;

  final Map<String, DateTime> _lastFetched = {};
  final Set<String> _inflight = {};
  ({double lat, double lon})? _lastLoc;

  // ─── Bootstrap reference data ──────────────────────────────

  Future<void> bootstrap() async {
    if (_referenceState.state == LoadState.ready) return;
    _referenceState = const ReferenceState.loading();
    notifyListeners();
    try {
      final results = await Future.wait([_api.busStops(), _api.busServices()]);
      final stops = results[0] as List<LtaBusStop>;
      final svcs = results[1] as List<LtaBusService>;
      _stopByCode
        ..clear()
        ..addEntries(stops.map((s) => MapEntry(s.busStopCode, s)));
      _services = svcs;
      _referenceState = const ReferenceState.ready();
      if (_lastLoc != null) {
        _recomputeNearby();
      }
    } on LtaException catch (e) {
      _referenceState = ReferenceState.error(e.message);
    } catch (e) {
      _referenceState = ReferenceState.error(e.toString());
    }
    notifyListeners();
  }

  String stopName(String code) =>
      _stopByCode[code]?.description ?? code;
  String roadName(String code) => _stopByCode[code]?.roadName ?? '';

  // ─── Nearby ────────────────────────────────────────────────

  void updateNearby(double lat, double lon) {
    _lastLoc = (lat: lat, lon: lon);
    if (_stopByCode.isEmpty) return;
    _recomputeNearby();
    notifyListeners();
  }

  void _recomputeNearby() {
    final loc = _lastLoc;
    if (loc == null) return;
    final ranked = _stopByCode.values
        .map((s) =>
            (stop: s, d: haversine(loc.lat, loc.lon, s.latitude, s.longitude)))
        .toList()
      ..sort((a, b) => a.d.compareTo(b.d));
    _nearby = ranked.take(12).map((r) {
      final s = r.stop;
      return NearbyStop(
        id: s.busStopCode,
        stopName: s.description,
        stopCode: s.busStopCode,
        distanceM: r.d.round(),
        walkMin: walkMinutesFor(r.d),
        services: servicesFor(s.busStopCode),
      );
    }).toList(growable: false);
  }

  // ─── Live arrivals ─────────────────────────────────────────

  List<Service> servicesFor(String code) {
    final a = _arrivals[code];
    if (a != null && a.kind == ArrivalStateKind.loaded) return a.services;
    return const [];
  }

  /// `silent: true` warms data without publishing a `loading` state (used
  /// by prefetch so entering Nearby doesn't burst-republish the whole list).
  void ensureArrivals(
    String code, {
    bool force = false,
    bool silent = false,
  }) {
    final last = _lastFetched[code];
    final fresh = last != null &&
        DateTime.now().difference(last) < LtaConfig.arrivalRefresh;
    if (!force &&
        fresh &&
        _arrivals[code]?.kind == ArrivalStateKind.loaded) {
      return;
    }
    if (_inflight.contains(code)) return;
    _inflight.add(code);
    if (!silent && _arrivals[code] == null) {
      _arrivals[code] = ArrivalState.loading();
      notifyListeners();
    }

    () async {
      try {
        final resp = await _api.busArrival(code);
        final mapped = resp.services
            .where((s) => s.nextBus.hasData)
            .map((s) => s.toService(
                destName: stopName(s.nextBus.destinationCode ?? '')))
            .toList()
          ..sort((a, b) => a.etaSec.compareTo(b.etaSec));
        _arrivals[code] = mapped.isEmpty
            ? ArrivalState.empty()
            : ArrivalState.loaded(mapped);
        _lastFetched[code] = DateTime.now();
      } on LtaException catch (e) {
        final prev = _arrivals[code];
        if (prev == null || prev.kind == ArrivalStateKind.loading) {
          _arrivals[code] = ArrivalState.error(e.message);
        }
      } catch (_) {
        final prev = _arrivals[code];
        if (prev == null || prev.kind == ArrivalStateKind.loading) {
          _arrivals[code] = ArrivalState.error('Couldn’t reach LTA');
        }
      } finally {
        _inflight.remove(code);
        // Nearby rows hold their own service lists; refresh them so any
        // newly-loaded arrivals propagate.
        if (_lastLoc != null) _recomputeNearby();
        notifyListeners();
      }
    }();
  }

  /// Warm arrivals for the visible nearby stops so expanding is instant.
  /// Only the closest five so a user-tapped expand isn't queued behind a
  /// 12-request prefetch wave.
  void prefetchNearbyArrivals() {
    for (final s in _nearby.take(5)) {
      ensureArrivals(s.stopCode, silent: true);
    }
  }

  // ─── Search (Buses + Stops, both live) ─────────────────────

  List<LtaBusService> searchServices(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final seen = <String>{};
    return _services
        .where((b) => b.serviceNo.toLowerCase().contains(s) && seen.add(b.serviceNo))
        .toList();
  }

  List<LtaBusStop> searchStops(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    return _stopByCode.values
        .where((b) =>
            b.description.toLowerCase().contains(s) ||
            b.roadName.toLowerCase().contains(s) ||
            b.busStopCode.contains(s))
        .toList()
      ..sort((a, b) => a.description.compareTo(b.description));
  }

  /// First stop served by a service (its route origin), for bus-result taps.
  Future<LtaBusStop?> originStop(String serviceNo) async {
    final routes = await _loadRoutes();
    if (routes == null) return null;
    final forSvc = routes.where((r) => r.serviceNo == serviceNo).toList()
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    final first = forSvc.isEmpty ? null : forSvc.first;
    return first == null ? null : _stopByCode[first.busStopCode];
  }

  // ─── Routes (lazy, big dataset, disk-cached) ───────────────

  Future<List<LtaBusRoute>?> _loadRoutes() async {
    if (_routesAll != null) return _routesAll;
    try {
      final r = await _api.busRoutes();
      _routesAll = r;
      _routesLoaded = true;
      notifyListeners();
      return r;
    } catch (_) {
      return null;
    }
  }

  Future<RouteInfo?> route({
    required String serviceNo,
    required String stopCode,
  }) async {
    final all = await _loadRoutes();
    if (all == null) return null;
    final forSvc = all.where((r) => r.serviceNo == serviceNo).toList();
    final dirs = forSvc.map((r) => r.direction).toSet().toList()..sort();
    List<LtaBusRoute> chosen = const [];
    for (final d in dirs) {
      final seq = forSvc.where((r) => r.direction == d).toList()
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
      if (seq.any((r) => r.busStopCode == stopCode)) {
        chosen = seq;
        break;
      }
      if (chosen.isEmpty) chosen = seq;
    }
    if (chosen.isEmpty) return null;
    final stops = <RouteStopLive>[];
    for (final r in chosen) {
      final s = _stopByCode[r.busStopCode];
      if (s == null) continue;
      stops.add(RouteStopLive(
        code: s.busStopCode,
        name: s.description,
        lat: s.latitude,
        lon: s.longitude,
        seq: r.stopSequence,
      ));
    }
    final youIdx = stops.indexWhere((s) => s.code == stopCode);
    return RouteInfo(
      stops: stops,
      youIndex: youIdx < 0 ? 0 : youIdx,
    );
  }

  /// Live position of the next bus of `serviceNo` approaching `stopCode`.
  Future<GeoPoint?> liveBus({
    required String serviceNo,
    required String stopCode,
  }) async {
    try {
      final resp = await _api.busArrival(stopCode, serviceNo: serviceNo);
      final svc = _matchService(resp, serviceNo);
      if (svc == null) return null;
      return _coordOf(svc);
    } catch (_) {
      return null;
    }
  }

  /// Live snapshot for one service at a stop — used to drive the lock-screen
  /// countdown without an in-app simulation.
  Future<({int etaSec, GeoPoint? coord})?> liveServiceSnapshot({
    required String serviceNo,
    required String stopCode,
  }) async {
    try {
      final resp = await _api.busArrival(stopCode, serviceNo: serviceNo);
      final match = _matchService(resp, serviceNo);
      final arr = match?.nextBus.arrivalDate;
      if (arr == null) return null;
      final eta = arr.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
      return (etaSec: eta, coord: _coordOf(match!));
    } catch (_) {
      return null;
    }
  }

  static LtaArrivalService? _matchService(
      LtaArrivalResponse resp, String serviceNo) {
    for (final s in resp.services) {
      if (s.serviceNo == serviceNo) return s;
    }
    return null;
  }

  static GeoPoint? _coordOf(LtaArrivalService svc) {
    final lat = svc.nextBus.lat;
    final lon = svc.nextBus.lon;
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;
    return GeoPoint(lat, lon);
  }
}
