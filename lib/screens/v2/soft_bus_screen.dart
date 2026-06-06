// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// Scrollable vertical page layout:
//   1. Top bar  — back (left), share + "…" menu (right).
//   2. Title    — "Bus {svc}" h1 + "Towards {dest}" + LIVE badge.
//   3. Map card — contained 300 dp rounded card with live-position callout.
//   4. Route progress — direction toggle + RouteTimeline in a surface card.
//   5. Alerts   — notify button + ongoing-tracking card.
//
// The bus pin is always plotted in one of three honest tiers:
//   • LIVE      — Service.busLat/busLon present → solid accent pill
//   • RECENT    — last-known fix <150s → dimmed solid pill
//   • ESTIMATED — no fix but route geometry loaded → hollow dashed "≈" pill
//                 derived by walking back from youIndex by ETA (~90s/stop)
//   • ABSENT    — no geometry at all → bus pin omitted, no position fabricated
// The pin glides between positions using AnimationController interpolation
// (fires every ~1.5 s matching the iOS ticker cadence). The glide is scoped
// to an AnimatedBuilder that rebuilds ONLY the MarkerLayer — the map tiles
// and the rest of the Stack are untouched during a glide.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/bus_progress.dart';
import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/route_timeline.dart';
import '../../widgets/v2/soft_components.dart';
import '../notifications_screen.dart';

// ─── Bus position tier ──────────────────────────────────────────────────
// `recent` is a first-class tier (mirrors iOS BusTier.recent):
//   live      → fresh GPS fix this poll
//   recent    → had a fix < 150s ago; keep showing it dimmed
//   estimated → no fix; position derived from route geometry + ETA
enum _BusTier { live, recent, estimated }

class _BusPlot {
  const _BusPlot({
    required this.lat,
    required this.lon,
    required this.tier,
    this.ageSec = 0,
  });
  final double lat;
  final double lon;
  final _BusTier tier;
  // Seconds since last GPS fix — only meaningful for `recent`.
  final int ageSec;
}

// ─── Screen ─────────────────────────────────────────────────────────────
class SoftBusScreen extends StatefulWidget {
  const SoftBusScreen({
    super.key,
    required this.stopCode,
    required this.svc,
    required this.onBack,
    this.fullRoute = false,
  });
  final String stopCode;
  final String svc;
  final VoidCallback onBack;

  /// When opened from a bus search there's no "your stop" context, so the
  /// route timeline shows the WHOLE route (anchored at the service origin)
  /// instead of the narrow approach window used when arriving at a real stop.
  final bool fullRoute;

  @override
  State<SoftBusScreen> createState() => _SoftBusScreenState();
}

class _SoftBusScreenState extends State<SoftBusScreen>
    with TickerProviderStateMixin {
  // ── Route data ──────────────────────────────────────────────────────
  RouteInfo? _route;
  ServiceRoute? _serviceRoute;
  int _dirIndex = 0;

  // ── Alight pick ─────────────────────────────────────────────────────
  String? get _alightId {
    final a = AppModel.shared.activeAlight;
    if (a == null || a.busNo != widget.svc) return null;
    return a.stopCode;
  }

  // ── Map controller ──────────────────────────────────────────────────
  final MapController _mapCtrl = MapController();
  bool _didAutoFrame = false;

  /// True while the full-screen map page (opened via "View on map") is on
  /// screen. The map lives there now, not inline — so `_mapCtrl.move` is only
  /// safe to call while this is true (the controller is attached).
  bool _mapOpen = false;

  // ── Bus pin animation (glide between positions) ──────────────────────
  // Performance: the glide drives _displayCoord (a ValueNotifier) instead
  // of calling setState on the whole State. AnimatedBuilder inside
  // _buildMap listens only to this notifier, so map tiles and the rest of
  // the widget tree do NOT rebuild during a 1.5-second glide.
  _BusPlot? _currentTarget;
  // ValueNotifier carries the animated display position + the current tier
  // so the marker widget can read both without a setState rebuild.
  final ValueNotifier<_BusPlot?> _displayPlot = ValueNotifier(null);
  AnimationController? _glideCtrl;
  Animation<double>? _glideLat;
  Animation<double>? _glideLon;

  // Recency window for the "last known" tier — mirrors iOS 150s limit.
  ({double lat, double lon, DateTime at})? _lastFix;

  // Periodic ticker (1.5 s) — recomputes the bus plot + animates the pin.
  Timer? _ticker;

  // ── Lifecycle ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
      _loadRoute();
      _recomputePlot();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _recomputePlot();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _glideCtrl?.dispose();
    _displayPlot.dispose();
    super.dispose();
  }

  // ── Route loading ────────────────────────────────────────────────────
  Future<void> _loadRoute() async {
    final sr = await DataStore.shared.serviceRoute(
      serviceNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (mounted) {
      setState(() {
        _serviceRoute = sr;
        if (sr != null) {
          _dirIndex = sr.initialIndex;
          _route = _routeFromDir(sr.directions[_dirIndex]);
        }
      });
      _recomputePlot();
    }
  }

  /// Derive a RouteInfo from a RouteDirection so the rest of the screen
  /// (map dots, estimated coord, alight scheduling) keeps using the same
  /// RouteInfo type unchanged.
  RouteInfo _routeFromDir(RouteDirection dir) {
    return RouteInfo(stops: dir.stops, youIndex: dir.youIndex);
  }

  /// Current direction, or null when the service route hasn't loaded yet.
  RouteDirection? get _currentDir {
    final sr = _serviceRoute;
    if (sr == null || _dirIndex >= sr.directions.length) return null;
    return sr.directions[_dirIndex];
  }

  // ── Alight scheduling ────────────────────────────────────────────────
  Future<void> _onAlightChanged(String? code) async {
    final route = _route;
    if (route == null) return;
    if (code == null) {
      await AppModel.shared.clearActiveAlight();
      if (mounted) setState(() {});
      return;
    }
    final alightIdx = route.stops.indexWhere((s) => s.code == code);
    if (alightIdx < 0) return;
    final stop = route.stops[alightIdx];
    final base = route.busIndex ?? route.youIndex;
    final stopsToAlight = (alightIdx - base).clamp(0, 1 << 30);
    final stopsToWait = (stopsToAlight - 2).clamp(0, 1 << 30);
    final fireAt = DateTime.now().add(Duration(seconds: stopsToWait * 90));
    await AppModel.shared.setActiveAlight(
      busNo: widget.svc,
      stopCode: code,
      stopName: stop.name,
      fireAt: fireAt,
    );
    if (mounted) setState(() {});
  }

  // ── Bus position resolution ──────────────────────────────────────────
  /// Three honesty tiers in priority order — mirrors iOS recomputePlot.
  void _recomputePlot() {
    final svc = _liveService();
    final now = DateTime.now();

    // Tier 1: LIVE — LTA shared a GPS fix this poll cycle.
    if (svc != null) {
      final lat = svc.busLat;
      final lon = svc.busLon;
      if (lat != null && lon != null) {
        _lastFix = (lat: lat, lon: lon, at: now);
        _setTarget(_BusPlot(lat: lat, lon: lon, tier: _BusTier.live));
        return;
      }
    }

    // Tier 2: RECENT — had a fix < 150s ago; keep it dimmed.
    // `recent` is now a first-class tier rather than a render-time recheck.
    final fix = _lastFix;
    if (fix != null) {
      final ageSec = now.difference(fix.at).inSeconds;
      if (ageSec < 150) {
        _setTarget(
          _BusPlot(
            lat: fix.lat,
            lon: fix.lon,
            tier: _BusTier.recent,
            ageSec: ageSec,
          ),
        );
        return;
      }
    }

    // Tier 3: ESTIMATED — derive position from route geometry + ETA.
    final est = _estimatedCoord(svc);
    if (est != null) {
      _setTarget(
        _BusPlot(lat: est.lat, lon: est.lon, tier: _BusTier.estimated),
      );
      return;
    }

    // Nothing — clear the bus pin without fabricating a position.
    _setTarget(null);
  }

  /// Walk back from the boarding stop by ETA-worth of travel (~90s/stop),
  /// interpolating between adjacent stop coords. Mirrors iOS estimatedCoord.
  ({double lat, double lon})? _estimatedCoord(Service? svc) {
    final r = _route;
    if (r == null || r.stops.isEmpty || svc == null) return null;
    final you = r.youIndex.clamp(0, r.stops.length - 1);
    if (you == 0) {
      return (lat: r.stops[0].lat, lon: r.stops[0].lon);
    }
    // Age-correct the ETA: subtract seconds elapsed since last refresh.
    final lastRefresh = DataStore.shared.lastRefresh(widget.stopCode);
    final elapsed = lastRefresh != null
        ? DateTime.now().difference(lastRefresh).inSeconds.toDouble()
        : 0.0;
    final eta = (svc.etaSec - elapsed).clamp(0.0, double.infinity);
    const perStop = 90.0;
    final back = (eta / perStop).clamp(0.0, you.toDouble());
    final idxF = you - back; // fractional route index
    final lo = idxF.floor().clamp(0, r.stops.length - 1);
    final hi = (lo + 1).clamp(0, you);
    final frac = idxF - lo;
    final a = r.stops[lo];
    final b = r.stops[hi];
    return (
      lat: a.lat + (b.lat - a.lat) * frac,
      lon: a.lon + (b.lon - a.lon) * frac,
    );
  }

  /// Animate the display pin toward a new target. Mirrors iOS setTarget.
  /// First placement snaps (no animation); subsequent moves glide over 1.5s.
  /// Updates _displayPlot (a ValueNotifier) — does NOT call setState, so
  /// only the AnimatedBuilder scoped to the MarkerLayer rebuilds.
  void _setTarget(_BusPlot? target) {
    if (!mounted) return;

    // Clear: plot was nil or becomes nil.
    if (target == null) {
      if (_currentTarget != null) {
        _currentTarget = null;
        _displayPlot.value = null;
        _glideCtrl?.stop();
      }
      return;
    }

    final prevPlot = _displayPlot.value;
    final prevLat = prevPlot?.lat;
    final prevLon = prevPlot?.lon;
    final moved =
        prevLat == null ||
        prevLon == null ||
        (target.lat - prevLat).abs() > 1e-7 ||
        (target.lon - prevLon).abs() > 1e-7;

    _currentTarget = target;

    if (prevLat == null || prevLon == null) {
      // First placement: snap immediately (no animation).
      _displayPlot.value = target;
      _frameSceneIfNeeded(target.lat, target.lon);
    } else if (moved) {
      // Subsequent moves: glide without touching setState.
      _glideCtrl?.dispose();
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      );
      _glideCtrl = ctrl;
      _glideLat = Tween<double>(
        begin: prevLat,
        end: target.lat,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.linear));
      _glideLon = Tween<double>(
        begin: prevLon,
        end: target.lon,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.linear));
      // Listener updates only the ValueNotifier — NOT setState.
      ctrl.addListener(() {
        final lat = _glideLat?.value;
        final lon = _glideLon?.value;
        if (lat != null && lon != null) {
          // Preserve the tier/ageSec from the current target while gliding.
          _displayPlot.value = _BusPlot(
            lat: lat,
            lon: lon,
            tier: target.tier,
            ageSec: target.ageSec,
          );
        }
      });
      ctrl.forward();
    } else {
      // Position unchanged but tier/ageSec may have changed (e.g. recent age
      // ticking up). Update the notifier so the marker refreshes.
      _displayPlot.value = _BusPlot(
        lat: prevLat,
        lon: prevLon,
        tier: target.tier,
        ageSec: target.ageSec,
      );
    }
  }

  /// On first bus plot, frame the camera to fit the bus + the stop (with
  /// padding) — mirrors iOS frameSceneIfNeeded. The recenter FAB opts out.
  void _frameSceneIfNeeded(double busLat, double busLon) {
    // The map only exists while the full-screen page is open; moving the
    // controller otherwise throws (it isn't attached to a FlutterMap).
    if (!_mapOpen || _didAutoFrame) return;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return;
    _didAutoFrame = true;
    final lats = [stop.latitude, busLat];
    final lons = [stop.longitude, busLon];
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b);
    final maxLon = lons.reduce((a, b) => a > b ? a : b);
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final spanLat = ((maxLat - minLat) * 1.8).clamp(0.005, 0.5);
    final zoom = spanLat < 0.006
        ? 16.0
        : spanLat < 0.012
        ? 15.0
        : spanLat < 0.025
        ? 14.0
        : spanLat < 0.06
        ? 13.0
        : 12.0;
    _mapCtrl.move(LatLng(centerLat, centerLon), zoom);
  }

  // ── Data helpers ─────────────────────────────────────────────────────
  Service? _liveService() {
    final a = DataStore.shared.arrivals[widget.stopCode];
    if (a == null || a.kind != ArrivalStateKind.loaded) return null;
    try {
      return a.services.firstWhere((s) => s.no == widget.svc);
    } on StateError {
      return null;
    }
  }

  List<SoftRouteStop> _timelineStops() {
    final r = _route;
    if (r == null) return const [];
    final dir = _currentDir;
    // Show the full route when:
    //   • widget.fullRoute (opened from bus search — no anchor stop context)
    //   • the currently-shown direction does not contain the anchor stop;
    //     showing only an approach window in that case would be meaningless.
    final youSeq = r.youIndex;
    final busSeq = _estimatedBusIndex();
    final showFull = widget.fullRoute || (dir != null && !dir.anchorPresent);
    // From a couple of stops before the bus all the way to the line's
    // terminus, so the progress visibly leads to the stated destination
    // rather than stopping just past your stop. RouteTimeline folds the
    // leading run behind a "show earlier stops" node to keep it scannable.
    final lead = BusProgress.timelineLead(
      busIndex: busSeq,
      youIndex: youSeq,
      stopsCount: r.stops.length,
    );
    final seg = showFull ? r.stops : r.stops.sublist(lead);
    // Only mark a "THIS STOP" boarding stop when this is the per-stop flow AND
    // the anchor is actually present in this direction. In fullRoute mode (bus
    // search) there's no boarding stop, so mark none — otherwise the anchor's
    // origin can reappear late on the return leg and get badged as the boarding
    // stop, which made the collapse node show a spurious "Show N earlier stops"
    // on one direction but not the other.
    final canMarkBoard =
        !widget.fullRoute && (dir == null || dir.anchorPresent);
    return seg.map((stop) {
      final idx = r.stops.indexWhere((s) => s.code == stop.code);
      final state = BusProgress.stopState(
        idx: idx,
        busIndex: busSeq,
        youIndex: youSeq,
        canMarkBoard: canMarkBoard,
      );
      return SoftRouteStop(id: stop.code, name: stop.name, state: state);
    }).toList();
  }

  // ── Live bus coordinate ───────────────────────────────────────────────
  // The bus's *actual* position when we have a fix — the live GPS coord from
  // the feed, or a recent one (< 150s). Null when we have nothing real and
  // must fall back to the ETA estimate. Mirrors iOS liveBusCoord.
  ({double lat, double lon})? _liveBusCoord() {
    final svc = _liveService();
    final lat = svc?.busLat;
    final lon = svc?.busLon;
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      return (lat: lat, lon: lon);
    }
    final fix = _lastFix;
    if (fix != null && DateTime.now().difference(fix.at).inSeconds < 150) {
      return (lat: fix.lat, lon: fix.lon);
    }
    return null;
  }

  // ── Estimated bus index ───────────────────────────────────────────────
  // Where the bus is along the route, as a stop index. Grounded in the real
  // GPS fix (nearest route stop) whenever we have one, so "stops away", the
  // callout, the journey bar, and the timeline all agree with the map pin.
  // Only without a usable fix do we fall back to the ETA estimate
  // (youIndex − eta/90), which can disagree with reality. Mirrors iOS
  // estimatedBusIndex. Nil when we have no anchor context (fullRoute /
  // no live arrival / route not loaded).
  int? _estimatedBusIndex() {
    if (widget.fullRoute) return null;
    final dir = _currentDir;
    if (dir == null || !dir.anchorPresent || dir.stops.isEmpty) return null;
    final svc = _liveService();
    if (svc == null) return null;
    final you = dir.youIndex.clamp(0, dir.stops.length - 1);

    // Snap a real fix to the nearest route stop; BusProgress clamps it to your
    // stop and falls back to the ETA estimate when there's no fix.
    final c = _liveBusCoord();
    final gpsNearest = c == null
        ? null
        : BusProgress.nearestIndex([
            for (final s in dir.stops) (lat: s.lat, lon: s.lon),
          ], c);
    final lastRefresh = DataStore.shared.lastRefresh(widget.stopCode);
    final elapsed = lastRefresh != null
        ? DateTime.now().difference(lastRefresh).inSeconds.toDouble()
        : 0.0;
    return BusProgress.busIndex(
      youIndex: you,
      gpsNearest: gpsNearest,
      etaSec: svc.etaSec,
      elapsedSec: elapsed,
    );
  }

  /// Straight-line distance from the bus to *your* stop — the intuitive "how
  /// far is it from me" number for the approaching card. Null without a fix.
  /// Mirrors iOS distanceToYouMeters.
  int? _distanceToYouMeters() {
    final dir = _currentDir;
    final c = _liveBusCoord();
    if (dir == null || c == null || dir.stops.isEmpty) return null;
    final you = dir.youIndex.clamp(0, dir.stops.length - 1);
    final s = dir.stops[you];
    return haversine(c.lat, c.lon, s.lat, s.lon).round();
  }

  // ─────────────────────────────────────────────────────────────────────
  // LIVE-POSITION CALLOUT DATA
  // ─────────────────────────────────────────────────────────────────────
  // Returns (prevName, nextName, stopsAway, distMetres) for the map-card
  // callout. prevName = stop the bus is at / just passed; nextName = the
  // immediately following stop (preferring widget.stopCode if it is next).
  // distMetres = haversine from the current display coord to nextStop.
  ({String prevName, String nextName, int stopsAway, int? distMetres})?
  _calloutData() {
    final dir = _currentDir;
    final busIdx = _estimatedBusIndex();
    if (dir == null || busIdx == null || dir.stops.isEmpty) return null;
    final stops = dir.stops;
    final clampedBus = busIdx.clamp(0, stops.length - 1);
    final nextIdx = (clampedBus + 1).clamp(0, stops.length - 1);

    final prevStop = stops[clampedBus];
    final nextStop = stops[nextIdx];

    final youIdx = dir.youIndex.clamp(0, stops.length - 1);
    final stopsAway = (youIdx - clampedBus).clamp(0, stops.length);

    // Distance from current bus display coordinate to nextStop.
    int? distMetres;
    final plot = _displayPlot.value;
    if (plot != null) {
      final d = haversine(plot.lat, plot.lon, nextStop.lat, nextStop.lon);
      distMetres = d.round();
    }

    return (
      prevName: prevStop.name,
      nextName: nextStop.name,
      stopsAway: stopsAway,
      distMetres: distMetres,
    );
  }

  void _recenterOnUser() {
    _didAutoFrame = true; // user took over framing
    final u = LocationService.shared.lastLocation;
    if (u != null) {
      _mapCtrl.move(LatLng(u.lat, u.lon), 16.0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.t.bg,
      body: ListenableBuilder(
        listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
        builder: (context, _) {
          final t = context.t;
          final live = _liveService();
          // Pull-to-refresh — re-fetch this stop's arrivals; the ListenableBuilder
          // rebuilds and repositions the bus. Matches the Stop view.
          return RefreshIndicator(
            onRefresh: () => DataStore.shared.refreshArrivals(widget.stopCode),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 1. Top bar ────────────────────────────────────
                      _buildTopBar(context, t, live),

                      // ── 2. Title block ────────────────────────────────
                      _buildTitleBlock(context, t, live),
                      const SizedBox(height: 16),

                      // ── 3. Approaching card ───────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildApproachingCard(context, t),
                      ),
                      const SizedBox(height: 20),

                      // ── 4. Route progress ─────────────────────────────
                      if (_route != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildRouteProgressSection(context, t),
                        ),

                      // ── View on map ───────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: _buildViewOnMapButton(context, t),
                      ),

                      // ── Live updates ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: _buildLiveUpdatesCard(context, t),
                      ),

                      // ── 5. Alerts (notify + ongoing) ──────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        child: _buildAlertsSection(context, t, live),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 1. Top bar ────────────────────────────────────────────────────────
  // Back (left), share + "…" overflow (right). Reuses _MapControl circles.
  Widget _buildTopBar(BuildContext context, LyneTheme t, Service? live) {
    final allNos = () {
      final st = DataStore.shared.arrivals[widget.stopCode];
      if (st == null || st.kind != ArrivalStateKind.loaded) return <String>[];
      return st.services.map((s) => s.no).toList();
    }();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Back.
            _MapControl(
              onTap: widget.onBack,
              semanticsLabel: 'Back',
              child: Icon(Icons.arrow_back, size: 20, color: t.fg),
            ),
            const Spacer(),
            // Save toggle — fills when this bus is saved. Mirrors iOS SoftBusView.
            _buildStarMenu(context, t),
            const SizedBox(width: 8),
            // "…" overflow menu — notify + ongoing-tracking shortcuts.
            _MapControl(
              onTap: () => _showOverflowMenu(context, t, live, allNos),
              semanticsLabel: 'More options',
              child: Icon(Icons.more_horiz, size: 20, color: t.fg),
            ),
          ],
        ),
      ),
    );
  }

  /// Save toggle — saves/removes this bus. A bus glyph fills (gold circle) when
  /// saved, mirroring the stop view's single-tap pin toggle. Tapping clears
  /// every save of this service, or saves it at this stop when none exists.
  /// Arrival alerts live in the Alerts section below, not here.
  Widget _buildStarMenu(BuildContext context, LyneTheme t) {
    final savedHere = AppModel.shared.isFavService(
      no: widget.svc,
      stop: widget.stopCode,
    );
    final savedAnywhere = AppModel.shared.isFavService(
      no: widget.svc,
      stop: null,
    );
    final saved = savedHere || savedAnywhere;
    final bg = saved ? const Color(0xFFF4B870) : t.surface;

    return Semantics(
      label: saved
          ? 'Bus ${widget.svc} saved. Tap to remove.'
          : 'Save bus ${widget.svc}',
      button: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _toggleServiceSaved(savedHere, savedAnywhere),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: saved ? null : Border.all(color: t.line, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  saved
                      ? Icons.directions_bus_rounded
                      : Icons.directions_bus_outlined,
                  size: 18,
                  color: saved ? Colors.white : t.fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Filled = saved (here or anywhere). Clears every save of this service, or
  /// saves it at this stop when none exists. Mirrors iOS toggleServiceSaved.
  void _toggleServiceSaved(bool savedHere, bool savedAnywhere) {
    if (savedHere || savedAnywhere) {
      if (savedHere) {
        AppModel.shared.toggleFavService(no: widget.svc, stop: widget.stopCode);
      }
      if (savedAnywhere) {
        AppModel.shared.toggleFavService(no: widget.svc, stop: null);
      }
    } else {
      AppModel.shared.toggleFavService(no: widget.svc, stop: widget.stopCode);
    }
  }

  /// "…" overflow menu: notify toggle + ongoing-tracking shortcut.
  void _showOverflowMenu(
    BuildContext context,
    LyneTheme t,
    Service? live,
    List<String> allNos,
  ) {
    final notifyOn = AppModel.shared.isTracked(
      code: widget.stopCode,
      busNo: widget.svc,
    );
    final ongoingOn =
        live != null &&
        AppModel.shared.isOngoingActive(
          busNo: widget.svc,
          stopCode: widget.stopCode,
        );

    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          button.size.topRight(Offset.zero),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<String>(
          value: 'notify',
          child: Row(
            children: [
              Icon(
                notifyOn
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 18,
                color: notifyOn ? t.accent : t.dim,
              ),
              const SizedBox(width: 10),
              Text(
                notifyOn ? 'Cancel alert' : 'Notify before arrival',
                style: t.sans(14, color: t.fg),
              ),
            ],
          ),
        ),
        if (live != null)
          PopupMenuItem<String>(
            value: 'ongoing',
            child: Row(
              children: [
                Icon(
                  ongoingOn
                      ? Icons.stop_rounded
                      : Icons.notifications_active_outlined,
                  size: 18,
                  color: ongoingOn ? t.accent : t.dim,
                ),
                const SizedBox(width: 10),
                Text(
                  ongoingOn
                      ? 'Stop tracking in notifications'
                      : 'Track in notifications',
                  style: t.sans(14, color: t.fg),
                ),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'notify') {
        AppModel.shared.toggleTracked(
          code: widget.stopCode,
          busNo: widget.svc,
          allNos: allNos,
        );
        AppModel.shared.rescheduleIfNeeded();
      } else if (value == 'ongoing' && live != null) {
        AppModel.shared.toggleOngoing(
          busNo: widget.svc,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
        );
      }
    });
  }

  // ── 2. Title block ────────────────────────────────────────────────────
  Widget _buildTitleBlock(BuildContext context, LyneTheme t, Service? live) {
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = live != null
        ? ArrivalConfidence.of(monitored: live.monitored, feed: feed)
        : ArrivalConfidence.none;
    final isLive = conf != ArrivalConfidence.none;
    final dest = live?.dest ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bus ${widget.svc}',
            style: t.sans(28, weight: FontWeight.w700, color: t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  dest.isEmpty ? 'Loading route…' : 'Towards $dest',
                  style: t.sans(15, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLive) ...[
                const SizedBox(width: 8),
                Semantics(
                  label: 'Live tracking',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: t.soon,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: t
                            .mono(10, weight: FontWeight.w700, color: t.soon)
                            .copyWith(letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Approaching card ─────────────────────────────────────────────────
  // Compact "where's the bus" summary that replaces the inline map. Headline =
  // stops away, subline = arriving-in + distance, then a slim journey bar. The
  // full map is one tap away via the "View on map" button. Wrapped in an
  // AnimatedBuilder on _displayPlot so the countdown/distance refresh on each
  // glide tick (~1.5 s) without rebuilding the whole screen.
  Widget _buildApproachingCard(BuildContext context, LyneTheme t) {
    return AnimatedBuilder(
      animation: _displayPlot,
      builder: (context, _) {
        final now = DateTime.now();
        final live = _liveService();
        final etaSec = live == null ? null : _liveEtaSec(live, now);
        final data = _calloutData();
        final stopsAway = data?.stopsAway;
        final dist = _distanceToYouMeters();
        final frac = _journeyFraction();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(LyneRadius.lg),
            border: Border.all(color: t.line, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.soonBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.directions_bus_rounded,
                      size: 20,
                      color: t.soon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _approachHeadline(stopsAway, etaSec),
                          style: t.sans(
                            17,
                            weight: FontWeight.w700,
                            color: t.fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _approachSubline(etaSec, dist),
                          style: t.sans(13, color: t.dim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (frac != null) ...[
                const SizedBox(height: 14),
                _slimBar(t, frac),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Headline: how many stops the bus is from the user's stop.
  String _approachHeadline(int? stopsAway, int? etaSec) {
    if (stopsAway != null) {
      return stopsAway == 0
          ? 'Arriving now'
          : '$stopsAway stop${stopsAway == 1 ? '' : 's'} away';
    }
    if (etaSec != null && fmtEta(etaSec).big == 'Arr') return 'Arriving now';
    return 'On the way';
  }

  /// Subline: "Arriving in {n} min" plus distance to the next stop.
  String _approachSubline(int? etaSec, int? dist) {
    if (etaSec == null) return 'Waiting for the next arrival';
    final eta = fmtEta(etaSec);
    final timePart = eta.big == 'Arr'
        ? 'Arriving now'
        : 'Arriving in ${eta.big} ${eta.small}';
    return dist != null ? '$timePart (${fmtDistance(dist)})' : timePart;
  }

  /// Fraction of the journey the bus has covered toward the user's stop.
  double? _journeyFraction() {
    final dir = _currentDir;
    final busIdx = _estimatedBusIndex();
    if (dir == null || busIdx == null || dir.stops.isEmpty) return null;
    final youIdx = dir.youIndex.clamp(0, dir.stops.length - 1);
    if (youIdx <= 0) return 1.0;
    return (busIdx / youIdx).clamp(0.0, 1.0);
  }

  /// Live ETA seconds, recomputed from arrivalDate for a smooth countdown.
  int _liveEtaSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  Widget _slimBar(LyneTheme t, double frac) {
    return Container(
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.line,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.02, 1.0),
          child: Container(color: t.soon),
        ),
      ),
    );
  }

  // ── Live updates card ───────────────────────────────────────────────────
  // Service-status card. No live bus-disruption feed yet, so — per the
  // timely-over-honest design language — this presents confidently as
  // "running smoothly" rather than advertising the data gap.
  Widget _buildLiveUpdatesCard(BuildContext context, LyneTheme t) {
    return Semantics(
      label:
          'Live updates. Service running smoothly, no major delays reported.',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.lg),
          border: Border.all(color: t.line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: t.soon,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Live updates',
                  style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.soonBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.sensors, size: 16, color: t.soon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service running smoothly',
                        style: t.sans(
                          14,
                          weight: FontWeight.w600,
                          color: t.soon,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'No major delays reported.',
                        style: t.sans(13, color: t.dim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── View-on-map button ──────────────────────────────────────────────────
  Widget _buildViewOnMapButton(BuildContext context, LyneTheme t) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openMap,
        child: Semantics(
          button: true,
          label: 'View bus ${widget.svc} on the map',
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.map_rounded, size: 18, color: t.accent),
                const SizedBox(width: 10),
                Text(
                  'View on map',
                  style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Full-screen map page (presented from "View on map") ──────────────────
  Future<void> _openMap() async {
    if (!mounted) return;
    setState(() {
      _mapOpen = true;
      _didAutoFrame = false; // reframe each time the map opens
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _buildMapPage(ctx),
      ),
    );
    if (mounted) setState(() => _mapOpen = false);
  }

  Widget _buildMapPage(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          // Map fills the page.
          Positioned.fill(child: _buildMap(context)),

          // Floating top bar — title pill (left) + Done pill (right).
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(LyneRadius.full),
                      border: Border.all(color: t.line, width: 1),
                    ),
                    child: Text(
                      'Bus ${widget.svc}',
                      style: t.sans(15, weight: FontWeight.w700, color: t.fg),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(LyneRadius.full),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(LyneRadius.full),
                          border: Border.all(color: t.line, width: 1),
                        ),
                        child: Text(
                          'Done',
                          style: t.sans(
                            15,
                            weight: FontWeight.w600,
                            color: t.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Live-position callout — bottom-left.
          Positioned(
            left: 16,
            bottom: 24,
            right: 76,
            child: _buildPositionCallout(context, t),
          ),

          // Recenter — bottom-right.
          Positioned(
            right: 16,
            bottom: 24,
            child: _MapControl(
              onTap: _recenterOnUser,
              semanticsLabel: 'Center on my location',
              child: Icon(Icons.my_location_rounded, size: 18, color: t.fg),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live-position callout ──────────────────────────────────────────────
  // Dark rounded bubble overlaid on the lower-left of the map card.
  // Shows: "Between X and Y" + "{N} stop(s) away · {dist} m"
  Widget _buildPositionCallout(BuildContext context, LyneTheme t) {
    // Driven by the ValueNotifier so it refreshes on each glide tick
    // without rebuilding the whole screen.
    return AnimatedBuilder(
      animation: _displayPlot,
      builder: (context, _) {
        final data = _calloutData();
        if (data == null || _displayPlot.value == null) {
          return const SizedBox.shrink();
        }

        final stopsLabel = data.stopsAway == 0
            ? 'Arriving'
            : '${data.stopsAway} stop${data.stopsAway == 1 ? '' : 's'} away';
        final distLabel = data.distMetres != null
            ? ' · ${data.distMetres} m'
            : '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Between ${data.prevName} and ${data.nextName}',
                style: t
                    .sans(12, weight: FontWeight.w600)
                    .copyWith(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: stopsLabel,
                      style: t.sans(11).copyWith(color: t.soon),
                    ),
                    TextSpan(
                      text: distLabel,
                      style: t.sans(11).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Map (reused as-is inside the card) ───────────────────────────────
  Widget _buildMap(BuildContext context) {
    final t = context.t;
    final stop = DataStore.shared.stopByCode[widget.stopCode];

    final double centerLat = stop?.latitude ?? 1.3521;
    final double centerLon = stop?.longitude ?? 103.8198;

    // Free CartoDB basemap — modern, no API key, no billing. Dark Matter in
    // dark mode and Positron (light) in light mode, so the map echoes the
    // app's monochrome theme. {r} loads @2x tiles on high-density screens.
    final tileUrl = t.isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    return ListenableBuilder(
      listenable: LocationService.shared,
      builder: (context, _) {
        // Static markers: stop pin + route-segment dots.
        // These only rebuild when LocationService notifies — not on every
        // glide frame.
        final staticMarkers = <Marker>[];

        // Stop pin.
        if (stop != null) {
          staticMarkers.add(
            Marker(
              point: LatLng(stop.latitude, stop.longitude),
              width: 40,
              height: 44,
              alignment: Alignment.topCenter,
              // Shadow is applied to the glyph (Icon.shadows) so it follows the
              // pin's teardrop outline. A wrapping DecoratedBox boxShadow would
              // cast from the icon's rectangular bounds — the faded black box.
              child: Icon(
                Icons.location_on,
                size: 40,
                color: t.accent,
                shadows: const [
                  Shadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          );
        }

        // Journey-segment stops — faint dots (non-queried).
        if (_route != null) {
          for (final rs in journeySegment(_route!)) {
            if (rs.code == widget.stopCode) continue;
            staticMarkers.add(
              Marker(
                point: LatLng(rs.lat, rs.lon),
                width: 10,
                height: 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.dim.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }
        }

        // User dot.
        final userLoc = LocationService.shared.lastLocation;
        if (userLoc != null) {
          staticMarkers.add(
            Marker(
              point: LatLng(userLoc.lat, userLoc.lon),
              width: 20,
              height: 20,
              child: _UserDot(color: LyneSignal.meBlue),
            ),
          );
        }

        return FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLon),
            initialZoom: 15.5,
            // Frame the bus + stop once the full-screen map is laid out.
            onMapReady: () {
              final p = _displayPlot.value;
              if (p != null) _frameSceneIfNeeded(p.lat, p.lon);
            },
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: RetinaMode.isHighDensity(context),
              userAgentPackageName: 'com.leyne.leyne',
              maxNativeZoom: 20,
            ),
            // Static layer — stop pin + route dots + user dot.
            MarkerLayer(markers: staticMarkers),
            // Bus pin layer — scoped AnimatedBuilder so ONLY this layer
            // rebuilds during the 1.5 s glide animation (tiles untouched).
            _buildBusMarkerLayer(context, t),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
                TextSourceAttribution('CARTO'),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Returns a MarkerLayer (wrapped in AnimatedBuilder) driven by
  /// _displayPlot. Only this widget subtree rebuilds on each glide frame.
  Widget _buildBusMarkerLayer(BuildContext context, LyneTheme t) {
    return AnimatedBuilder(
      animation: _displayPlot,
      // `child` is null here because the marker content depends on the
      // animated value — but the builder is very cheap (one Marker alloc).
      builder: (context, _) {
        final plot = _displayPlot.value;
        if (plot == null) return const MarkerLayer(markers: []);

        final tier = plot.tier;
        final estimated = tier == _BusTier.estimated;
        final isRecent = tier == _BusTier.recent;
        final ageSec = plot.ageSec;

        // Accessibility label differentiates tiers — mirrors iOS positionA11y.
        final String a11yLabel = switch (tier) {
          _BusTier.live => 'Bus ${widget.svc}, live position',
          _BusTier.recent =>
            'Bus ${widget.svc}, last known position, seen ${ageSec}s ago',
          _BusTier.estimated =>
            'Bus ${widget.svc}, estimated position, en route',
        };

        return MarkerLayer(
          markers: [
            Marker(
              point: LatLng(plot.lat, plot.lon),
              width: 80,
              height: 32,
              child: Semantics(
                label: a11yLabel,
                child: Opacity(
                  opacity: isRecent ? 0.6 : 1.0,
                  child: _BusPillMarker(
                    busNo: widget.svc,
                    estimated: estimated,
                    color: t.contrast,
                    fgColor: t.contrastFg,
                    surfaceColor: t.surface,
                    borderColor: t.fg,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── 4. Route progress section ─────────────────────────────────────────
  Widget _buildRouteProgressSection(BuildContext context, LyneTheme t) {
    final timelineStops = _timelineStops();

    // Freshness label.
    final lastRefresh = DataStore.shared.lastRefresh(widget.stopCode);
    final String freshnessLabel;
    if (lastRefresh == null) {
      freshnessLabel = 'Waiting for data';
    } else {
      final age = DateTime.now().difference(lastRefresh).inSeconds;
      if (age < 5) {
        freshnessLabel = 'Updated now';
      } else if (age < 60) {
        freshnessLabel = 'Updated ${age}s ago';
      } else {
        freshnessLabel = 'Updated ${age ~/ 60} min ago';
      }
    }
    final feedLive = Freshness.from(lastRefresh) == Freshness.live;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Route progress',
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(LyneRadius.lg),
            border: Border.all(color: t.line, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Direction toggle — only shown when 2+ directions.
              if ((_serviceRoute?.directions.length ?? 0) > 1) ...[
                _buildDirectionToggle(context, t),
                const SizedBox(height: 12),
              ],

              if (timelineStops.isNotEmpty) ...[
                Text(
                  'Tap a stop to set an arrival alert.',
                  style: t.sans(12, color: t.dim),
                ),
                const SizedBox(height: 8),
                RouteTimeline(
                  svc: widget.svc,
                  stops: timelineStops,
                  alightId: _alightId,
                  onAlight: _onAlightChanged,
                ),
                const SizedBox(height: 12),
              ],

              // Freshness line.
              Row(
                children: [
                  Icon(
                    Icons.sensors,
                    size: 11,
                    color: feedLive ? t.soon : t.dim,
                  ),
                  const SizedBox(width: 5),
                  Text(freshnessLabel, style: t.mono(11, color: t.dim)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Direction toggle ─────────────────────────────────────────────────
  /// Pill-row toggle between the service's two directions.  Uses Material 3
  /// SegmentedButton so selection, focus ring, and accessibility come for
  /// free.  Labels are truncated gracefully to 18 chars; the chip intrinsically
  /// shrinks to fit the available width via Flexible children.
  Widget _buildDirectionToggle(BuildContext context, LyneTheme t) {
    final sr = _serviceRoute!;
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: t.liveBg,
        foregroundColor: t.dim,
        selectedForegroundColor: t.contrastFg,
        selectedBackgroundColor: t.contrast,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LyneRadius.full),
        ),
        textStyle: t.sans(13, weight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      segments: [
        for (var i = 0; i < sr.directions.length; i++)
          ButtonSegment<int>(
            value: i,
            label: Text(
              _truncate('To ${sr.directions[i].destinationName}', 22),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
      selected: {_dirIndex},
      onSelectionChanged: (selection) {
        final newIdx = selection.first;
        if (newIdx == _dirIndex) return;
        setState(() {
          _dirIndex = newIdx;
          _route = _routeFromDir(sr.directions[_dirIndex]);
        });
        _recomputePlot();
      },
    );
  }

  /// Truncate [s] to [max] chars, appending "…" only when needed.
  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  // ── 5. Alerts section ────────────────────────────────────────────────
  // Notify button + ongoing-tracking card, placed below route progress.
  Widget _buildAlertsSection(BuildContext context, LyneTheme t, Service? live) {
    final st = DataStore.shared.arrivals[widget.stopCode];
    final allNos = st != null && st.kind == ArrivalStateKind.loaded
        ? st.services.map((s) => s.no).toList()
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Alerts'),
        const SizedBox(height: 8),
        _notifyButton(context, t, allNos),
        if (live != null) ...[
          const SizedBox(height: 12),
          _ongoingCard(context, t, live),
        ],
      ],
    );
  }

  // ── Notify button ────────────────────────────────────────────────────
  Widget _notifyButton(BuildContext context, LyneTheme t, List<String> allNos) {
    final on = AppModel.shared.isTracked(
      code: widget.stopCode,
      busNo: widget.svc,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(LyneRadius.full),
      onTap: () async {
        AppModel.shared.toggleTracked(
          code: widget.stopCode,
          busNo: widget.svc,
          allNos: allNos,
        );
        await AppModel.shared.rescheduleIfNeeded();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? t.accent : t.liveBg,
          borderRadius: BorderRadius.circular(LyneRadius.full),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              on
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 18,
              color: on ? t.onAccent : t.accent,
            ),
            const SizedBox(width: 8),
            Text(
              on ? 'Alert on — tap to cancel' : 'Notify me before it arrives',
              style: t.sans(
                14,
                weight: FontWeight.w600,
                color: on ? t.onAccent : t.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ongoing tracking card ────────────────────────────────────────────
  Widget _ongoingCard(BuildContext context, LyneTheme t, Service live) {
    final m = AppModel.shared;

    if (!m.notificationsEnabled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.liveBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                color: t.dim,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track in your status bar',
                    style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  ),
                  Text(
                    'Enable notifications to track Bus ${widget.svc} in your status bar.',
                    style: t.sans(12, color: t.dim),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              child: Text(
                'Enable',
                style: t.sans(13, weight: FontWeight.w600, color: t.accent),
              ),
            ),
          ],
        ),
      );
    }

    final on = m.isOngoingActive(busNo: widget.svc, stopCode: widget.stopCode);
    return InkWell(
      borderRadius: BorderRadius.circular(LyneRadius.md),
      onTap: () => m.toggleOngoing(
        busNo: widget.svc,
        stopCode: widget.stopCode,
        stopName: DataStore.shared.stopName(widget.stopCode),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.md),
          border: on
              ? Border.all(color: t.accent.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? t.accent : t.liveBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                on ? Icons.stop_rounded : Icons.notifications_active_outlined,
                color: on ? t.onAccent : t.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    on ? 'Tracking in notifications' : 'Track in notifications',
                    style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  ),
                  Text(
                    on
                        ? 'In your status bar · updates while Leyne is open'
                        : 'Follow Bus ${widget.svc} — updates while the app is open',
                    style: t.sans(12, color: t.dim),
                  ),
                ],
              ),
            ),
            Icon(
              on ? Icons.check_circle_rounded : Icons.chevron_right,
              color: on ? t.accent : t.dim,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Map control button ──────────────────────────────────────────────────────
/// A circular control button that floats over the map (or lives in the top bar).
/// Uses Material + InkWell for a proper ripple effect.
/// The tap target is 48×48 dp; the visual circle is 40×40 dp.
class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.child,
    required this.onTap,
    this.semanticsLabel,
  });
  final Widget child;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bg = t.surface;
    // 48dp touch target wraps a 40dp visual circle.
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Map marker widgets ──────────────────────────────────────────────────────

/// Bus pill marker — two visual styles honoring the honesty tiers:
///   live/recent  → solid dark capsule (exact or last-known GPS)
///   estimated    → light capsule with dashed border + "≈" prefix
class _BusPillMarker extends StatelessWidget {
  const _BusPillMarker({
    required this.busNo,
    required this.estimated,
    required this.color,
    required this.fgColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  final String busNo;
  final bool estimated;
  final Color color;
  final Color fgColor;
  final Color surfaceColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final textFg = estimated ? borderColor : fgColor;
    final bgColor = estimated ? surfaceColor : color;

    return CustomPaint(
      painter: estimated
          ? _DashedCapsulePainter(
              color: borderColor.withValues(alpha: 0.55),
              strokeWidth: 1.5,
            )
          : null,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(LyneRadius.full),
          border: estimated
              ? null // dashed border via CustomPaint
              : Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_rounded, size: 11, color: textFg),
            const SizedBox(width: 4),
            Builder(
              builder: (ctx) {
                final tt = ctx.t;
                return Text(
                  estimated ? '≈ $busNo' : busNo,
                  style: tt.mono(11, weight: FontWeight.w700, color: textFg),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rect border, used by the estimated bus marker.
class _DashedCapsulePainter extends CustomPainter {
  _DashedCapsulePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final radius = size.height / 2;
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final path = ui.Path()..addRRect(rrect);
    _drawDashedPath(canvas, path, paint, dash: 3, gap: 3);
  }

  @override
  bool shouldRepaint(_DashedCapsulePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

void _drawDashedPath(
  Canvas canvas,
  ui.Path source,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = (distance + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }
}
