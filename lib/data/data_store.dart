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

import '../theme.dart' show MRTLine;
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
  const ReferenceState.ready() : state = LoadState.ready, errorMessage = null;
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

/// 2D point — provider-neutral so callers can convert to flutter_map /
/// latlong2 LatLng without leaking that dependency into the data layer.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// Crowdedness bucket from the PCDRealTime feed.
/// Mirrors iOS DataStore.swift: enum CrowdLevel.
enum CrowdLevel { low, moderate, high, unknown }

/// One station's live crowdedness on a line.
/// Mirrors iOS DataStore.swift: struct StationCrowd.
class StationCrowd {
  const StationCrowd({
    required this.code,
    required this.name,
    required this.level,
  });

  /// LTA station code, e.g. "EW13".
  final String code;

  /// Display name resolved from station code, e.g. "City Hall".
  final String name;

  final CrowdLevel level;

  String get id => code;

  static CrowdLevel levelFrom(String raw) {
    switch (raw.toLowerCase()) {
      case 'l':
        return CrowdLevel.low;
      case 'm':
        return CrowdLevel.moderate;
      case 'h':
        return CrowdLevel.high;
      default:
        return CrowdLevel.unknown;
    }
  }
}

/// A lift under maintenance at an MRT station (FacilitiesMaintenance v2).
/// Mirrors iOS DataStore.swift: struct LiftMaintenance.
class LiftMaintenance {
  const LiftMaintenance({
    required this.line,
    required this.stationName,
    required this.detail,
  });

  final String line;
  final String stationName;
  final String detail;

  String get id => '$line·$stationName·$detail';
}

/// MRT/LRT line disruption surfaced on the Home screen. Built from LTA's
/// TrainServiceAlerts response — one entry per affected segment so a
/// multi-line incident renders as multiple cards.
class TrainAlert {
  const TrainAlert({
    required this.id,
    required this.lineCode,
    required this.line,
    required this.title,
    required this.detail,
  });

  /// Stable per-line id so ListView builders and dismissal sets key off
  /// "the NEL alert" rather than the message text.
  final String id;
  final String lineCode;
  final MRTLine? line;
  final String title;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is TrainAlert &&
      other.id == id &&
      other.title == title &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(id, title, detail);
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

/// One direction of a service (LTA Direction 1 or 2): the full ordered stop
/// list, where the anchor stop sits in it, and whether the anchor is in this
/// direction at all. A bus service almost always runs two directions
/// (origin→terminus and back), so the Bus view offers a toggle between them.
class RouteDirection {
  RouteDirection({
    required this.direction,
    required this.stops,
    required this.youIndex,
    required this.anchorPresent,
  });

  /// LTA `Direction` value (1 or 2).
  final int direction;
  final List<RouteStopLive> stops;

  /// Index of the anchor stop in [stops] (0 when the anchor isn't in this
  /// direction — see [anchorPresent]).
  final int youIndex;

  /// Whether the anchor stopCode actually appears in this direction. False for
  /// the "other" direction when the view was opened from a specific stop.
  final bool anchorPresent;

  String get originName => stops.isEmpty ? '' : stops.first.name;
  String get destinationName => stops.isEmpty ? '' : stops.last.name;
}

/// A service's complete route across all directions. [initialIndex] is the
/// direction whose stop list contains the anchor stop (so opening from a stop
/// preselects the right way round); falls back to 0.
class ServiceRoute {
  ServiceRoute({
    required this.serviceNo,
    required this.directions,
    required this.initialIndex,
  });
  final String serviceNo;
  final List<RouteDirection> directions;
  final int initialIndex;
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

/// Order service numbers by their leading integer, then lexically — so
/// '7' < '91' < '107M' < '191', not the raw string order.
int _compareServiceNo(String a, String b) {
  int lead(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1 << 30;
  final c = lead(a).compareTo(lead(b));
  return c != 0 ? c : a.compareTo(b);
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
  // stopCode → sorted service numbers serving it, derived from the
  // BusRoutes dataset. Built once when routes load (see _loadRoutes).
  Map<String, List<String>>? _servicesByStop;

  final Map<String, DateTime> _lastFetched = {};
  final Set<String> _inflight = {};
  ({double lat, double lon})? _lastLoc;

  /// MRT/LRT line disruptions refreshed periodically by AppModel's tick.
  /// Empty means no current disruptions; the Home page renders one card
  /// per item.
  List<TrainAlert> _trainAlerts = const [];
  List<TrainAlert> get trainAlerts => _trainAlerts;
  DateTime? _lastTrainAlertFetch;
  bool _trainAlertsInflight = false;

  /// Network-wide lift maintenance items (FacilitiesMaintenance v2).
  /// Empty = no current lift outages. Refreshed lazily when the MRT board opens.
  List<LiftMaintenance> _liftMaintenance = const [];
  List<LiftMaintenance> get liftMaintenance => _liftMaintenance;
  DateTime? _lastLiftFetch;

  /// Live per-line station crowdedness (PCDRealTime), fetched lazily when a
  /// line is expanded on the MRT board. null = not yet fetched / in-flight.
  final Map<MRTLine, List<StationCrowd>?> _crowdByLine = {};
  Map<MRTLine, List<StationCrowd>?> get crowdByLine => _crowdByLine;
  final Set<MRTLine> _crowdInflight = {};
  final Map<MRTLine, DateTime> _lastCrowdFetch = {};

  /// Tick from AppModel calls this once per second; the inner gate
  /// keeps us at one network hit per 60 s.
  void refreshTrainAlertsIfStale({bool force = false}) {
    if (_trainAlertsInflight) return;
    if (!force &&
        _lastTrainAlertFetch != null &&
        DateTime.now().difference(_lastTrainAlertFetch!) <
            const Duration(seconds: 60)) {
      return;
    }
    _trainAlertsInflight = true;
    _lastTrainAlertFetch = DateTime.now();
    () async {
      try {
        final r = await _api.trainServiceAlerts();
        final next = (r.status == 2)
            ? r.affectedSegments
                  .map(
                    (seg) => TrainAlert(
                      id: seg.line,
                      lineCode: seg.line,
                      line: MRTLine.fromLtaCode(seg.line),
                      title:
                          '${MRTLine.shortLabelForLta(seg.line)} · disrupted',
                      detail: _trainAlertSummary(seg, r.messages),
                    ),
                  )
                  .toList(growable: false)
            : const <TrainAlert>[];
        // Skip a rebuild when nothing changed.
        final unchanged =
            next.length == _trainAlerts.length &&
            List.generate(
              next.length,
              (i) => next[i] == _trainAlerts[i],
            ).every((e) => e);
        if (!unchanged) {
          _trainAlerts = next;
          notifyListeners();
        }
      } catch (_) {
        // Network blip — keep the previous snapshot rather than blanking.
      } finally {
        _trainAlertsInflight = false;
      }
    }();
  }

  String _trainAlertSummary(
    LtaAffectedSegment seg,
    List<LtaTrainMessage> messages,
  ) {
    final raw = messages
        .firstWhere(
          (m) => m.content.contains(seg.line),
          orElse: () => messages.isEmpty
              ? const LtaTrainMessage(content: '')
              : messages.first,
        )
        .content
        .replaceAll('\n', ' ')
        .trim();
    if (raw.isEmpty) return 'Service disruption · tap to dismiss';
    final dot = raw.indexOf('.');
    final head = dot > 0 ? raw.substring(0, dot) : raw;
    return '$head · tap to dismiss';
  }

  // ─── Lift maintenance (FacilitiesMaintenance v2) ──────────
  /// Refresh network-wide lift outage list. Gate: 30 min, matching iOS.
  void refreshLiftMaintenanceIfStale({bool force = false}) {
    if (!force &&
        _lastLiftFetch != null &&
        DateTime.now().difference(_lastLiftFetch!) <
            const Duration(minutes: 30)) {
      return;
    }
    _lastLiftFetch = DateTime.now();
    () async {
      try {
        final items = await _api.facilitiesMaintenance();
        final mapped = items
            .map(
              (i) => LiftMaintenance(
                line: i.line,
                stationName: i.stationName,
                detail: (i.liftDesc?.trim().isNotEmpty ?? false)
                    ? i.liftDesc!.trim()
                    : 'Lift under maintenance',
              ),
            )
            .toList(growable: false);
        // Skip rebuild when list is identical.
        final unchanged =
            mapped.length == _liftMaintenance.length &&
            List.generate(
              mapped.length,
              (i) => mapped[i].id == _liftMaintenance[i].id,
            ).every((e) => e);
        if (!unchanged) {
          _liftMaintenance = mapped;
          notifyListeners();
        }
      } catch (_) {
        // Network blip — keep the previous snapshot.
      }
    }();
  }

  // ─── Station crowd density (PCDRealTime) ──────────────────
  /// Fetch live crowdedness for one line (lazy — called when a line is
  /// expanded). Gate: 5 min per line, matching iOS. Deduped via inflightSet.
  void refreshCrowd(MRTLine line, {bool force = false}) {
    if (_crowdInflight.contains(line)) return;
    if (!force &&
        _lastCrowdFetch[line] != null &&
        DateTime.now().difference(_lastCrowdFetch[line]!) <
            const Duration(minutes: 5)) {
      return;
    }
    _crowdInflight.add(line);
    _lastCrowdFetch[line] = DateTime.now();
    () async {
      try {
        final rows = await _api.stationCrowd(_pcdLineCode(line));
        final mapped = rows
            .map(
              (r) => StationCrowd(
                code: r.station,
                name: _mrtStationName(r.station) ?? r.station,
                level: StationCrowd.levelFrom(r.crowdLevel),
              ),
            )
            .toList(growable: false);
        _crowdByLine[line] = mapped;
        notifyListeners();
      } catch (_) {
        // On error: leave the existing entry unchanged (don't blank data).
        // If nothing was there yet, set empty so the UI shows "unavailable".
        _crowdByLine.putIfAbsent(line, () => const []);
        notifyListeners();
      } finally {
        _crowdInflight.remove(line);
      }
    }();
  }

  /// PCDRealTime line code for a given MRT line enum.
  /// Mirrors iOS Theme.swift: MRTLine.pcdLineCode.
  static String _pcdLineCode(MRTLine line) {
    switch (line) {
      case MRTLine.ew:
        return 'EWL';
      case MRTLine.ns:
        return 'NSL';
      case MRTLine.ne:
        return 'NEL';
      case MRTLine.cc:
        return 'CCL';
      case MRTLine.dt:
        return 'DTL';
      case MRTLine.te:
        return 'TEL';
    }
  }

  /// Resolve a station code (e.g. "EW13") to its display name using the
  /// existing `_stationCodes` dataset from mrt_stations.dart (inverse lookup).
  /// Mirrors iOS DataStore.swift: mrtStationName(forCode:).
  static final Map<String, String> _mrtNameByCode = () {
    // Build a reverse index: code → station name.
    // Replicates the logic in ios-native/Leyne/V2/MrtStations.swift.
    const Map<String, List<String>> stationCodes = {
      'Jurong East': ['EW24', 'NS1'],
      'Bukit Batok': ['NS2'],
      'Bukit Gombak': ['NS3'],
      'Choa Chu Kang': ['NS4'],
      'Yew Tee': ['NS5'],
      'Kranji': ['NS7'],
      'Marsiling': ['NS8'],
      'Woodlands': ['NS9', 'TE2'],
      'Admiralty': ['NS10'],
      'Sembawang': ['NS11'],
      'Canberra': ['NS12'],
      'Yishun': ['NS13'],
      'Khatib': ['NS14'],
      'Yio Chu Kang': ['NS15'],
      'Ang Mo Kio': ['NS16'],
      'Bishan': ['NS17', 'CC15'],
      'Braddell': ['NS18'],
      'Toa Payoh': ['NS19'],
      'Novena': ['NS20'],
      'Newton': ['NS21', 'DT11'],
      'Orchard': ['NS22', 'TE14'],
      'Somerset': ['NS23'],
      'Dhoby Ghaut': ['NS24', 'NE6', 'CC1'],
      'City Hall': ['NS25', 'EW13'],
      'Raffles Place': ['NS26', 'EW14'],
      'Marina Bay': ['NS27', 'CE2', 'TE20'],
      'Marina South Pier': ['NS28'],
      'Pasir Ris': ['EW1'],
      'Tampines': ['EW2', 'DT32'],
      'Simei': ['EW3'],
      'Tanah Merah': ['EW4'],
      'Bedok': ['EW5'],
      'Kembangan': ['EW6'],
      'Eunos': ['EW7'],
      'Paya Lebar': ['EW8', 'CC9'],
      'Aljunied': ['EW9'],
      'Kallang': ['EW10'],
      'Lavender': ['EW11'],
      'Bugis': ['EW12', 'DT14'],
      'Tanjong Pagar': ['EW15'],
      'Outram Park': ['EW16', 'NE3', 'TE17'],
      'Tiong Bahru': ['EW17'],
      'Redhill': ['EW18'],
      'Queenstown': ['EW19'],
      'Commonwealth': ['EW20'],
      'Buona Vista': ['EW21', 'CC22'],
      'Dover': ['EW22'],
      'Clementi': ['EW23'],
      'Chinese Garden': ['EW25'],
      'Lakeside': ['EW26'],
      'Boon Lay': ['EW27'],
      'Pioneer': ['EW28'],
      'Joo Koon': ['EW29'],
      'Gul Circle': ['EW30'],
      'Tuas Crescent': ['EW31'],
      'Tuas West Road': ['EW32'],
      'Tuas Link': ['EW33'],
      'Expo': ['CG1', 'DT35'],
      'Changi Airport': ['CG2'],
      'HarbourFront': ['NE1', 'CC29'],
      'Chinatown': ['NE4', 'DT19'],
      'Clarke Quay': ['NE5'],
      'Little India': ['NE7', 'DT12'],
      'Farrer Park': ['NE8'],
      'Boon Keng': ['NE9'],
      'Potong Pasir': ['NE10'],
      'Woodleigh': ['NE11'],
      'Serangoon': ['NE12', 'CC13'],
      'Kovan': ['NE13'],
      'Hougang': ['NE14'],
      'Buangkok': ['NE15'],
      'Sengkang': ['NE16'],
      'Punggol': ['NE17'],
      'Punggol Coast': ['NE18'],
      'Bras Basah': ['CC2'],
      'Esplanade': ['CC3'],
      'Promenade': ['CC4', 'DT15'],
      'Nicoll Highway': ['CC5'],
      'Stadium': ['CC6'],
      'Mountbatten': ['CC7'],
      'Dakota': ['CC8'],
      'MacPherson': ['CC10', 'DT26'],
      'Tai Seng': ['CC11'],
      'Bartley': ['CC12'],
      'Lorong Chuan': ['CC14'],
      'Marymount': ['CC16'],
      'Caldecott': ['CC17', 'TE9'],
      'Botanic Gardens': ['CC19', 'DT9'],
      'Farrer Road': ['CC20'],
      'Holland Village': ['CC21'],
      'one-north': ['CC23'],
      'Kent Ridge': ['CC24'],
      'Haw Par Villa': ['CC25'],
      'Pasir Panjang': ['CC26'],
      'Labrador Park': ['CC27'],
      'Telok Blangah': ['CC28'],
      'Bayfront': ['CE1', 'DT16'],
      'Bukit Panjang': ['DT1'],
      'Cashew': ['DT2'],
      'Hillview': ['DT3'],
      'Hume': ['DT4'],
      'Beauty World': ['DT5'],
      'King Albert Park': ['DT6'],
      'Sixth Avenue': ['DT7'],
      'Tan Kah Kee': ['DT8'],
      'Stevens': ['DT10', 'TE11'],
      'Rochor': ['DT13'],
      'Downtown': ['DT17'],
      'Telok Ayer': ['DT18'],
      'Fort Canning': ['DT20'],
      'Bencoolen': ['DT21'],
      'Jalan Besar': ['DT22'],
      'Bendemeer': ['DT23'],
      'Geylang Bahru': ['DT24'],
      'Mattar': ['DT25'],
      'Ubi': ['DT27'],
      'Kaki Bukit': ['DT28'],
      'Bedok North': ['DT29'],
      'Bedok Reservoir': ['DT30'],
      'Tampines West': ['DT31'],
      'Tampines East': ['DT33'],
      'Upper Changi': ['DT34'],
      'Woodlands North': ['TE1'],
      'Woodlands South': ['TE3'],
      'Springleaf': ['TE4'],
      'Lentor': ['TE5'],
      'Mayflower': ['TE6'],
      'Bright Hill': ['TE7'],
      'Upper Thomson': ['TE8'],
      'Napier': ['TE12'],
      'Orchard Boulevard': ['TE13'],
      'Great World': ['TE15'],
      'Havelock': ['TE16'],
      'Maxwell': ['TE18'],
      'Shenton Way': ['TE19'],
      'Gardens by the Bay': ['TE22'],
      'Tanjong Rhu': ['TE23'],
      'Katong Park': ['TE24'],
      'Tanjong Katong': ['TE25'],
      'Marine Parade': ['TE26'],
      'Marine Terrace': ['TE27'],
      'Siglap': ['TE28'],
      'Bayshore': ['TE29'],
    };
    final idx = <String, String>{};
    for (final entry in stationCodes.entries) {
      for (final code in entry.value) {
        idx[code.toUpperCase()] = entry.key;
      }
    }
    return idx;
  }();

  static String? _mrtStationName(String code) =>
      _mrtNameByCode[code.toUpperCase()];

  // ─── Bootstrap reference data ──────────────────────────────

  Future<void> bootstrap() async {
    if (_referenceState.state == LoadState.ready) return;
    _referenceState = const ReferenceState.loading();
    notifyListeners();
    // LTA DataMall is occasionally flaky — a fresh request sometimes
    // returns 500 for a few seconds. Try up to 3 times with 2s + 4s
    // backoff before surfacing the error to the user. Cheap insurance:
    // worst case adds 6s on a real outage; usual case is instant.
    LtaException? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final results = await Future.wait([
          _api.busStops(),
          _api.busServices(),
        ]);
        final stops = results[0] as List<LtaBusStop>;
        final svcs = results[1] as List<LtaBusService>;
        _stopByCode
          ..clear()
          ..addEntries(stops.map((s) => MapEntry(s.busStopCode, s)));
        _services = svcs;
        _referenceState = const ReferenceState.ready();
        // If a location fix arrived before reference data, the Home prefetch
        // already ran against an empty `_nearby`. Now that stops are loaded,
        // rank nearby and warm their arrivals so the cards populate.
        if (_lastLoc != null) {
          _recomputeNearby();
          prefetchNearbyArrivals();
        }
        notifyListeners();
        return;
      } on LtaException catch (e) {
        lastErr = e;
        // Don't retry auth-shaped errors — those won't fix themselves.
        if (e.statusCode != null &&
            (e.statusCode! < 500 || e.statusCode! >= 600)) {
          break;
        }
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 2 * (1 << attempt)));
        }
      } catch (e) {
        _referenceState = ReferenceState.error(e.toString());
        notifyListeners();
        return;
      }
    }
    _referenceState = ReferenceState.error(
      lastErr?.message ?? 'Couldn’t reach LTA',
    );
    notifyListeners();
  }

  String stopName(String code) => _stopByCode[code]?.description ?? code;
  String roadName(String code) => _stopByCode[code]?.roadName ?? '';

  // ─── Nearby ────────────────────────────────────────────────

  void updateNearby(double lat, double lon) {
    _lastLoc = (lat: lat, lon: lon);
    if (_stopByCode.isEmpty) return;
    _recomputeNearby();
    // Warm the freshly-ranked nearby stops so their cards show buses without
    // the user opening each one. (Before this, the Home prefetch could fire
    // against an empty `_nearby` while bootstrap was still loading, leaving
    // nearby cards perpetually empty until a stop was opened.)
    prefetchNearbyArrivals();
    notifyListeners();
  }

  void _recomputeNearby() {
    final loc = _lastLoc;
    if (loc == null) return;
    final ranked =
        _stopByCode.values
            .map(
              (s) => (
                stop: s,
                d: haversine(loc.lat, loc.lon, s.latitude, s.longitude),
              ),
            )
            .toList()
          ..sort((a, b) => a.d.compareTo(b.d));
    _nearby = ranked
        .take(12)
        .map((r) {
          final s = r.stop;
          return NearbyStop(
            id: s.busStopCode,
            stopName: s.description,
            stopCode: s.busStopCode,
            lat: s.latitude,
            lon: s.longitude,
            distanceM: r.d.round(),
            walkMin: walkMinutesFor(r.d),
            services: servicesFor(s.busStopCode),
          );
        })
        .toList(growable: false);
  }

  /// Refresh only the live-`services` snapshot on the already-ranked nearby
  /// stops, leaving the haversine ranking untouched. O(nearby) — no sort, no
  /// scan of the full stop index — so it's cheap enough to run on every
  /// arrival poll. Use [_recomputeNearby] instead only when the location
  /// (and thus the ranking) actually changes.
  void _refreshNearbyServices() {
    if (_nearby.isEmpty) return;
    _nearby = [
      for (final n in _nearby)
        NearbyStop(
          id: n.id,
          stopName: n.stopName,
          stopCode: n.stopCode,
          lat: n.lat,
          lon: n.lon,
          distanceM: n.distanceM,
          walkMin: n.walkMin,
          services: servicesFor(n.stopCode),
        ),
    ];
  }

  /// Bus stops within [radiusM] metres of (lat, lon), nearest first.
  /// Independent of the device GPS — used by postal-code search, where the
  /// centre is a geocoded address rather than the user's location. Capped
  /// at 50 so a wide radius in a dense area stays manageable.
  List<NearbyStop> stopsWithin(double lat, double lon, int radiusM) {
    final within = <({LtaBusStop stop, double d})>[];
    for (final s in _stopByCode.values) {
      final d = haversine(lat, lon, s.latitude, s.longitude);
      if (d <= radiusM) within.add((stop: s, d: d));
    }
    within.sort((a, b) => a.d.compareTo(b.d));
    return within
        .take(50)
        .map((r) {
          final s = r.stop;
          return NearbyStop(
            id: s.busStopCode,
            stopName: s.description,
            stopCode: s.busStopCode,
            lat: s.latitude,
            lon: s.longitude,
            distanceM: r.d.round(),
            walkMin: walkMinutesFor(r.d),
            services: const [],
          );
        })
        .toList(growable: false);
  }

  // ─── Live arrivals ─────────────────────────────────────────

  List<Service> servicesFor(String code) {
    final a = _arrivals[code];
    if (a != null && a.kind == ArrivalStateKind.loaded) return a.services;
    return const [];
  }

  /// When this stop's arrivals were last successfully pulled from LTA, or
  /// null if never fetched / still erroring. Drives the confidence/freshness
  /// system (see `Freshness.from` in widgets/v2/confidence.dart) so an arrival
  /// can be honestly tagged live / estimated / scheduled.
  DateTime? lastRefresh(String code) => _lastFetched[code];

  /// `silent: true` warms data without publishing a `loading` state (used
  /// by prefetch so entering Nearby doesn't burst-republish the whole list).
  void ensureArrivals(String code, {bool force = false, bool silent = false}) {
    final last = _lastFetched[code];
    final fresh =
        last != null &&
        DateTime.now().difference(last) < LtaConfig.arrivalRefresh;
    if (!force && fresh && _arrivals[code]?.kind == ArrivalStateKind.loaded) {
      return;
    }
    if (_inflight.contains(code)) return;
    _inflight.add(code);
    if (!silent && _arrivals[code] == null) {
      _arrivals[code] = ArrivalState.loading();
      notifyListeners();
    }
    _fetchArrivals(code);
  }

  /// Awaitable force-refresh for pull-to-refresh. Always hits the network
  /// (bypasses the freshness window) and completes when the fetch settles,
  /// so a [RefreshIndicator] can hold its spinner for the real duration.
  /// Mirrors the iOS `DataStore.refreshArrivals(stop:)`.
  Future<void> refreshArrivals(String code) async {
    if (_inflight.contains(code)) return;
    _inflight.add(code);
    await _fetchArrivals(code);
  }

  /// Shared network body for [ensureArrivals] / [refreshArrivals]. The caller
  /// owns the `_inflight` add; this clears it in `finally`. On error an
  /// existing `.loaded` result is preserved (we don’t blank good data).
  Future<void> _fetchArrivals(String code) async {
    // Snapshot the state BEFORE the async gap so the equality guard below
    // can compare "what the UI last saw" against "what just came in".
    final prevState = _arrivals[code];
    try {
      final resp = await _api.busArrival(code);
      final mapped =
          resp.services
              .where((s) => s.nextBus.hasData)
              .map(
                (s) => s.toService(
                  destName: stopName(s.nextBus.destinationCode ?? ''),
                ),
              )
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
      // Nearby rows hold their own service lists; refresh those snapshots so
      // newly-loaded arrivals propagate — but WITHOUT re-ranking. A full
      // _recomputeNearby() here re-sorts the entire ~5000-stop dataset on
      // every arrival poll (12 nearby prefetches + the 1 s pin ticker), a
      // needless main-thread hit that dropped frames while scrolling. The
      // ranking only changes when the user moves — see updateNearby().
      if (_lastLoc != null) _refreshNearbyServices();

      // ── Value-equality guard (mirrors the trainAlerts diff pattern) ─────
      // With 12 nearby prefetches + the 1 s pin ticker, _fetchArrivals fires
      // very frequently. Calling notifyListeners() on every completion —
      // even when the stored ArrivalState is identical to what was there
      // before — triggers whole-tree rebuilds for zero visual delta, a
      // significant perf cost flagged in code review.
      //
      // Rule: notify if and only if something the UI cares about changed:
      //   • kind changed (loading→loaded, error→loaded, etc.)
      //   • services list changed in any meaningful way (count, service no,
      //     ETA seconds, or load level on any bus)
      //
      // When in doubt we notify (e.g. prevState was null). We NEVER suppress
      // a transition that the UI needs. The awaitable refreshArrivals path is
      // unaffected: it relies on the Future completing, not on a notify.
      final nextState = _arrivals[code];
      final changed = _arrivalStateChanged(prevState, nextState);
      if (changed) notifyListeners();
    }
  }

  /// Returns true when [next] represents a meaningful change over [prev] that
  /// warrants a UI rebuild. Conservative: unknown / null prev → always true.
  static bool _arrivalStateChanged(ArrivalState? prev, ArrivalState? next) {
    if (prev == null || next == null) return true;
    if (prev.kind != next.kind) return true;
    // Both same kind — only loaded states carry service lists worth diffing.
    if (next.kind != ArrivalStateKind.loaded) return false;
    final ps = prev.services;
    final ns = next.services;
    if (ps.length != ns.length) return true;
    for (var i = 0; i < ns.length; i++) {
      final p = ps[i];
      final n = ns[i];
      if (p.no != n.no || p.etaSec != n.etaSec || p.load != n.load) {
        return true;
      }
    }
    return false;
  }

  /// Warm arrivals for the visible nearby stops so their cards show live
  /// buses without the user having to open each one. Covers the whole visible
  /// list (`_nearby` is already capped at 12); `ensureArrivals` de-dupes
  /// in-flight/fresh requests so repeat calls are cheap. Fired whenever
  /// `_nearby` is (re)populated — see `updateNearby` and `bootstrap`.
  void prefetchNearbyArrivals() {
    for (final s in _nearby) {
      ensureArrivals(s.stopCode, silent: true);
    }
  }

  // ─── Search (Buses + Stops, both live) ─────────────────────

  List<LtaBusService> searchServices(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final seen = <String>{};
    return _services
        .where(
          (b) => b.serviceNo.toLowerCase().contains(s) && seen.add(b.serviceNo),
        )
        .toList();
  }

  List<LtaBusStop> searchStops(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    // Token match: every query word must appear in the stop's text (any order),
    // after normalising synonyms — so "yio chu kang mrt" finds "Yio Chu Kang
    // Stn", and "clementi interchange" finds "Clementi Int".
    final queryTokens = _searchTokens(s);
    return _stopByCode.values.where((b) {
      if (b.busStopCode.contains(s)) return true;
      final hay = _searchTokens('${b.description} ${b.roadName}');
      return queryTokens.every((qt) => hay.any((h) => h.contains(qt)));
    }).toList()..sort((a, b) => a.description.compareTo(b.description));
  }

  /// Synonym-normalised search tokens. Maps the words LTA never uses in stop
  /// names (mrt / station / interchange / lrt) onto the ones it does (stn /
  /// int), and splits on any non-alphanumeric separator.
  static const _searchSynonyms = {
    'mrt': 'stn',
    'station': 'stn',
    'stn': 'stn',
    'lrt': 'stn',
    'interchange': 'int',
    'int': 'int',
    'intg': 'int',
  };
  List<String> _searchTokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => _searchSynonyms[w] ?? w)
      .toList();

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
      _buildServicesByStop(r);
      _routesLoaded = true;
      notifyListeners();
      return r;
    } catch (_) {
      return null;
    }
  }

  /// Kick off the routes-dataset load (idempotent, fire-and-forget).
  /// Callers that only need `servicesAtStop` use this instead of awaiting
  /// `route()`.
  void ensureRoutes() => _loadRoutes();

  void _buildServicesByStop(List<LtaBusRoute> routes) {
    final map = <String, Set<String>>{};
    for (final r in routes) {
      (map[r.busStopCode] ??= <String>{}).add(r.serviceNo);
    }
    _servicesByStop = {
      for (final e in map.entries)
        e.key: e.value.toList()..sort(_compareServiceNo),
    };
  }

  /// All service numbers serving `stopCode`, from the static BusRoutes
  /// dataset — available regardless of whether live arrivals have loaded.
  /// Empty until `ensureRoutes()` (or any route lookup) has resolved.
  List<String> servicesAtStop(String stopCode) =>
      _servicesByStop?[stopCode] ?? const [];

  /// When `code`'s live arrivals were last successfully fetched — drives the
  /// "updated Ns ago" freshness caption. Null until the first fetch lands.
  DateTime? lastFetchedAt(String code) => _lastFetched[code];

  /// First/last scheduled bus for `serviceNo` at `stopCode`, picked for the
  /// day-type of `now` (weekday / Saturday / Sunday-or-PH). Times are `HHMM`
  /// strings. Null until the BusRoutes dataset has loaded (`ensureRoutes()`),
  /// or when the service simply doesn't run on that day.
  ({String first, String last})? busTimings({
    required String serviceNo,
    required String stopCode,
    DateTime? now,
  }) {
    final routes = _routesAll;
    if (routes == null) return null;
    for (final r in routes) {
      if (r.serviceNo != serviceNo || r.busStopCode != stopCode) continue;
      final (first, last) = switch ((now ?? DateTime.now()).weekday) {
        DateTime.saturday => (r.satFirstBus, r.satLastBus),
        DateTime.sunday => (r.sunFirstBus, r.sunLastBus),
        _ => (r.wdFirstBus, r.wdLastBus),
      };
      if (first == null || last == null) return null;
      return (first: first, last: last);
    }
    return null;
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
      stops.add(
        RouteStopLive(
          code: s.busStopCode,
          name: s.description,
          lat: s.latitude,
          lon: s.longitude,
          seq: r.stopSequence,
        ),
      );
    }
    final youIdx = stops.indexWhere((s) => s.code == stopCode);
    return RouteInfo(stops: stops, youIndex: youIdx < 0 ? 0 : youIdx);
  }

  /// All directions of `serviceNo` (typically two — there and back), each with
  /// its ordered stops. When `stopCode` is given, the matching direction is
  /// flagged `anchorPresent` and chosen as `initialIndex`. Drives the Bus
  /// view's direction toggle. Null when routes can't load or the service is
  /// unknown.
  Future<ServiceRoute?> serviceRoute({
    required String serviceNo,
    String? stopCode,
  }) async {
    final all = await _loadRoutes();
    if (all == null) return null;
    final forSvc = all.where((r) => r.serviceNo == serviceNo).toList();
    if (forSvc.isEmpty) return null;
    final dirs = forSvc.map((r) => r.direction).toSet().toList()..sort();
    final directions = <RouteDirection>[];
    for (final d in dirs) {
      final seq = forSvc.where((r) => r.direction == d).toList()
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
      final stops = <RouteStopLive>[];
      for (final r in seq) {
        final s = _stopByCode[r.busStopCode];
        if (s == null) continue;
        stops.add(
          RouteStopLive(
            code: s.busStopCode,
            name: s.description,
            lat: s.latitude,
            lon: s.longitude,
            seq: r.stopSequence,
          ),
        );
      }
      if (stops.isEmpty) continue;
      final youIdx = stopCode == null
          ? -1
          : stops.indexWhere((s) => s.code == stopCode);
      directions.add(
        RouteDirection(
          direction: d,
          stops: stops,
          youIndex: youIdx < 0 ? 0 : youIdx,
          anchorPresent: youIdx >= 0,
        ),
      );
    }
    if (directions.isEmpty) return null;
    var initial = directions.indexWhere((dir) => dir.anchorPresent);
    if (initial < 0) initial = 0;
    return ServiceRoute(
      serviceNo: serviceNo,
      directions: directions,
      initialIndex: initial,
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
    LtaArrivalResponse resp,
    String serviceNo,
  ) {
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
