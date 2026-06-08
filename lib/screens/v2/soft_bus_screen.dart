// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// No-scroll glanceable dashboard (ports iOS SoftBusView 2.5.0). Everything a
// commuter decides on is on one screen, no scrolling:
//   1. Top bar — back · bell (boarding alert) · save · ⋯ (manage alerts/share)
//   2. Title   — "Bus {svc}" + "Towards {dest}" + LIVE
//   3. Hero    — ETA + stops-away + crowd meter, then deck/wheelchair + next two
//   4. Live    — compact route strip (origin→bus→you→terminus) beside a live
//                map preview; the strip taps up the full-route card, the map
//                taps up the map sheet. Fills the screen so nothing scrolls.
//   5. Footer  — first / last bus today
//
// The bus pin is plotted in three honest tiers (live / recent <150s /
// estimated from route geometry + ETA) and glides between positions. The map
// preview and the map sheet share the marker set; the bus layer is a scoped
// AnimatedBuilder so only it rebuilds during a glide.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/alert_timing.dart';
import '../../data/bus_progress.dart';
import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/route_timeline.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'manage_alerts_screen.dart';

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
    this.onTab,
    this.tabSelection,
  });
  final String stopCode;
  final String svc;
  final VoidCallback onBack;

  /// When opened from a bus search there's no "your stop" context, so the
  /// route timeline shows the WHOLE route (anchored at the service origin)
  /// instead of the narrow approach window used when arriving at a real stop.
  final bool fullRoute;

  /// When provided, the tab bar (with its ad banner) stays visible on this
  /// pushed detail page. [tabSelection] is the tab it was opened from. Null for
  /// deep-link contexts.
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftBusScreen> createState() => _SoftBusScreenState();
}

class _SoftBusScreenState extends State<SoftBusScreen>
    with TickerProviderStateMixin {
  // ── Route data ──────────────────────────────────────────────────────
  RouteInfo? _route;
  ServiceRoute? _serviceRoute;
  int _dirIndex = 0;

  // ── Map controllers ─────────────────────────────────────────────────
  // The interactive card map and the always-on inline preview each need their
  // own controller (a MapController binds to a single FlutterMap).
  final MapController _mapCtrl = MapController();
  final MapController _previewCtrl = MapController();
  bool _didAutoFrame = false;

  /// True while the map sheet (tapped up from the preview) is on screen — the
  /// only time `_mapCtrl.move` is safe (the controller is attached then).
  bool _mapOpen = false;

  // Inline preview framing — frame once the stop + bus are both known.
  bool _previewReady = false;
  bool _previewFramedWithBus = false;

  // ── Bus pin animation (glide between positions) ──────────────────────
  // The glide drives _displayPlot (a ValueNotifier) instead of setState, so
  // only the AnimatedBuilder scoped to the bus MarkerLayer rebuilds — map
  // tiles and the rest of the tree are untouched during a 1.5 s glide.
  _BusPlot? _currentTarget;
  final ValueNotifier<_BusPlot?> _displayPlot = ValueNotifier(null);
  AnimationController? _glideCtrl;
  Animation<double>? _glideLat;
  Animation<double>? _glideLon;

  // Recency window for the "last known" tier — mirrors iOS 150s limit.
  ({double lat, double lon, DateTime at})? _lastFix;

  // Periodic ticker (1.5 s) — recomputes the bus plot + animates the pin.
  Timer? _ticker;

  // ── Transient confirmation toast ─────────────────────────────────────
  // Says what a tapped top-bar button just did, then clears itself.
  ({IconData icon, String text})? _toast;
  Timer? _toastTimer;

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
      if (!mounted) return;
      // Keep this stop's arrivals fresh while open (self-throttled), then
      // reposition the bus.
      DataStore.shared.ensureArrivals(widget.stopCode);
      _recomputePlot();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _toastTimer?.cancel();
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

  /// Derive a RouteInfo from a RouteDirection so the rest of the screen keeps
  /// using the same RouteInfo type unchanged.
  RouteInfo _routeFromDir(RouteDirection dir) {
    return RouteInfo(stops: dir.stops, youIndex: dir.youIndex);
  }

  /// Current direction, or null when the service route hasn't loaded yet.
  RouteDirection? get _currentDir {
    final sr = _serviceRoute;
    if (sr == null || _dirIndex >= sr.directions.length) return null;
    return sr.directions[_dirIndex];
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

  /// Animate the display pin toward a new target. First placement snaps;
  /// subsequent moves glide over 1.5s. Updates _displayPlot (a ValueNotifier)
  /// — does NOT call setState.
  void _setTarget(_BusPlot? target) {
    if (!mounted) return;

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
    final moved = prevLat == null ||
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
      _glideLat = Tween<double>(begin: prevLat, end: target.lat)
          .animate(CurvedAnimation(parent: ctrl, curve: Curves.linear));
      _glideLon = Tween<double>(begin: prevLon, end: target.lon)
          .animate(CurvedAnimation(parent: ctrl, curve: Curves.linear));
      ctrl.addListener(() {
        final lat = _glideLat?.value;
        final lon = _glideLon?.value;
        if (lat != null && lon != null) {
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
      // Position unchanged but tier/ageSec may have changed (recent age
      // ticking up). Refresh the notifier so the marker updates.
      _displayPlot.value = _BusPlot(
        lat: prevLat,
        lon: prevLon,
        tier: target.tier,
        ageSec: target.ageSec,
      );
    }

    // Frame the inline preview once a real bus position is known.
    if (_previewReady && !_previewFramedWithBus) _framePreview();
  }

  /// On first bus plot, frame the card map to fit the bus + the stop. Mirrors
  /// iOS frameSceneIfNeeded. The recenter buttons opt out via _didAutoFrame.
  void _frameSceneIfNeeded(double busLat, double busLon) {
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
    try {
      _mapCtrl.move(LatLng(centerLat, centerLon), zoom);
    } catch (_) {}
  }

  /// Frame the inline preview to fit the stop + bus + journey dots. Runs once
  /// the preview map is ready and a bus plot exists, so the preview opens on
  /// the relevant neighbourhood rather than the whole island. The bus marker
  /// then glides within this frame.
  void _framePreview() {
    if (!_previewReady) return;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return;
    final pts = <LatLng>[LatLng(stop.latitude, stop.longitude)];
    final plot = _displayPlot.value;
    if (plot != null) pts.add(LatLng(plot.lat, plot.lon));
    final r = _route;
    if (r != null) {
      for (final rs in journeySegment(r)) {
        pts.add(LatLng(rs.lat, rs.lon));
      }
    }
    try {
      if (pts.length == 1) {
        _previewCtrl.move(pts.first, 15.0);
      } else {
        _previewCtrl.fitCamera(
          CameraFit.coordinates(
            coordinates: pts,
            padding: const EdgeInsets.all(28),
            maxZoom: 16.0,
          ),
        );
      }
    } catch (_) {}
    if (plot != null) _previewFramedWithBus = true;
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
    final youSeq = r.youIndex;
    final busSeq = _estimatedBusIndex();
    final showFull = widget.fullRoute || (dir != null && !dir.anchorPresent);
    final lead = BusProgress.timelineLead(
      busIndex: busSeq,
      youIndex: youSeq,
      stopsCount: r.stops.length,
    );
    final seg = showFull ? r.stops : r.stops.sublist(lead);
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

  /// The bus's *actual* position when we have a fix — live GPS, or recent
  /// (<150s). Null when we have nothing real. Mirrors iOS liveBusCoord.
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

  /// Where the bus is along the route, as a stop index — grounded in the real
  /// GPS fix (nearest route stop) when we have one, falling back to the ETA
  /// estimate. Null without anchor context. Mirrors iOS estimatedBusIndex.
  int? _estimatedBusIndex() {
    if (widget.fullRoute) return null;
    final dir = _currentDir;
    if (dir == null || !dir.anchorPresent || dir.stops.isEmpty) return null;
    final svc = _liveService();
    if (svc == null) return null;
    final you = dir.youIndex.clamp(0, dir.stops.length - 1);

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

  /// Stops between the bus and your stop. Null without anchor context.
  int? _stopsRemaining() {
    final dir = _currentDir;
    final busIdx = _estimatedBusIndex();
    if (dir == null || busIdx == null || dir.stops.isEmpty) return null;
    final youIdx = dir.youIndex.clamp(0, dir.stops.length - 1);
    return (youIdx - busIdx).clamp(0, dir.stops.length);
  }

  /// (prevName, nextName, stopsAway, distMetres) for the map-sheet callout.
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

  /// Live ETA seconds, recomputed from arrivalDate for a smooth countdown.
  int _liveEtaSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  // ── Camera controls (map sheet) ──────────────────────────────────────
  void _recenterOnUser() {
    _didAutoFrame = true; // user took over framing
    final u = LocationService.shared.lastLocation;
    if (u != null) {
      try {
        _mapCtrl.move(LatLng(u.lat, u.lon), 16.0);
      } catch (_) {}
    }
  }

  /// Recenter on the bus's *current* position — refresh the plot first and use
  /// the freshest fix (live / recent / estimate) rather than the mid-glide
  /// marker, so it never lands on a stale past position. Mirrors iOS.
  void _recenterOnBus() {
    _didAutoFrame = true;
    _recomputePlot();
    final c = _liveBusCoord() ?? _estimatedCoord(_liveService());
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    final target = c ??
        (stop != null ? (lat: stop.latitude, lon: stop.longitude) : null);
    if (target == null) return;
    try {
      _mapCtrl.move(LatLng(target.lat, target.lon), 16.0);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.t.bg,
      bottomNavigationBar: (widget.onTab != null && widget.tabSelection != null)
          ? SoftBottomBar(
              selection: widget.tabSelection!, onSelect: widget.onTab!)
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
        builder: (context, _) {
          final t = context.t;
          return Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(t),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                      child: _buildTitleBlock(context, t, _liveService()),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildHeroCard(t),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: RepaintBoundary(child: _buildLiveModule(t)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _buildFirstLastFooter(t),
                    ),
                  ],
                ),
              ),
              if (_toast != null) _buildToast(context, t),
            ],
          );
        },
      ),
    );
  }

  // ── 1. Top bar ────────────────────────────────────────────────────────
  // Back · (spacer) · bell (boarding alert) · save · ⋯ (manage alerts/share).
  Widget _buildTopBar(LyneTheme t) {
    final boardingOn = _boardingAlertOn;
    final saved = AppModel.shared.isFavService(no: widget.svc, stop: widget.stopCode) ||
        AppModel.shared.isFavService(no: widget.svc, stop: null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _MapControl(
            onTap: widget.onBack,
            semanticsLabel: 'Back',
            child: Icon(Icons.arrow_back, size: 20, color: t.fg),
          ),
          const Spacer(),
          // Boarding alert — buzz me before this bus reaches this stop.
          _MapControl(
            onTap: _toggleBoardingAlert,
            semanticsLabel: boardingOn
                ? 'Boarding alert on for bus ${widget.svc}. Tap to cancel.'
                : 'Notify me before bus ${widget.svc} reaches this stop',
            child: Icon(
              boardingOn
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
              color: boardingOn ? t.soon : t.fg,
            ),
          ),
          const SizedBox(width: 8),
          // Save this service.
          _MapControl(
            onTap: _toggleServiceSaved,
            semanticsLabel: saved
                ? 'Bus ${widget.svc} saved. Tap to remove.'
                : 'Save bus ${widget.svc}',
            child: Icon(
              saved ? Icons.directions_bus_rounded : Icons.directions_bus_outlined,
              size: 20,
              color: saved ? t.soon : t.fg,
            ),
          ),
          const SizedBox(width: 8),
          _buildOverflow(t),
        ],
      ),
    );
  }

  /// "⋯" overflow — manage alerts + share. Styled as a round button to match
  /// the other top-bar controls.
  Widget _buildOverflow(LyneTheme t) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: Material(
          color: t.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: PopupMenuButton<String>(
            tooltip: 'More options',
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LyneRadius.md),
            ),
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.line, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.more_horiz, size: 20, color: t.fg),
            ),
            onSelected: (v) {
              if (v == 'manage') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManageAlertsScreen()),
                );
              } else if (v == 'share') {
                _shareBus();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'manage',
                child: Row(
                  children: [
                    Icon(Icons.notifications_rounded, size: 18, color: t.dim),
                    const SizedBox(width: 10),
                    Text('Manage alerts', style: t.sans(14, color: t.fg)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.ios_share_rounded, size: 18, color: t.dim),
                    const SizedBox(width: 10),
                    Text('Share bus ${widget.svc}',
                        style: t.sans(14, color: t.fg)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy a shareable line to the clipboard (no share_plus dependency) and
  /// confirm with a toast.
  void _shareBus() {
    final text =
        'Bus ${widget.svc} from Stop ${widget.stopCode} — tracked on Leyne';
    Clipboard.setData(ClipboardData(text: text));
    _showToast(Icons.check_rounded, 'Bus ${widget.svc} link copied');
  }

  // ── Boarding-alert + save toggles (with toast feedback) ───────────────
  bool get _boardingAlertOn =>
      AppModel.shared.alertFor(
        kind: AlertKind.arrival,
        busNo: widget.svc,
        stopCode: widget.stopCode,
      ) !=
      null;

  /// Arm an arrival alert at this stop (+ best-effort lock-screen tracker), or
  /// cancel both. Quiet — a toast says what happened (manage via the ⋯ menu).
  Future<void> _toggleBoardingAlert() async {
    final m = AppModel.shared;
    final existing = m.alertFor(
      kind: AlertKind.arrival,
      busNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (existing != null) {
      await m.removeAlert(existing.id);
      if (m.isOngoingActive(busNo: widget.svc, stopCode: widget.stopCode)) {
        await m.toggleOngoing(
          busNo: widget.svc,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
        );
      }
      _showToast(Icons.notifications_off_rounded,
          'Boarding alert off for Bus ${widget.svc}');
    } else {
      final live = _liveService();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: widget.svc,
        stopCode: widget.stopCode,
        stopName: DataStore.shared.stopName(widget.stopCode),
        dest: live?.dest ?? '',
        boardStopCode: widget.stopCode,
        leadMinutes: AlertTiming.defaultLead(AlertKind.arrival),
      ));
      if (live != null &&
          m.notificationsEnabled &&
          !m.isOngoingActive(busNo: widget.svc, stopCode: widget.stopCode)) {
        await m.toggleOngoing(
          busNo: widget.svc,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
        );
      }
      _showToast(Icons.notifications_active_rounded,
          "Boarding alert on — we'll buzz you before Bus ${widget.svc} arrives");
    }
  }

  /// Filled = saved (here or anywhere). Clears every save of this service, or
  /// saves it at this stop when none exists. Mirrors iOS toggleServiceSaved.
  void _toggleServiceSaved() {
    final m = AppModel.shared;
    final savedHere = m.isFavService(no: widget.svc, stop: widget.stopCode);
    final savedAnywhere = m.isFavService(no: widget.svc, stop: null);
    if (savedHere || savedAnywhere) {
      if (savedHere) m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      if (savedAnywhere) m.toggleFavService(no: widget.svc, stop: null);
      _showToast(Icons.directions_bus_outlined,
          'Bus ${widget.svc} removed from saved');
    } else {
      m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      _showToast(Icons.directions_bus_rounded,
          'Bus ${widget.svc} saved — find it under Saved');
    }
  }

  // ── Toast ─────────────────────────────────────────────────────────────
  void _showToast(IconData icon, String text) {
    setState(() => _toast = (icon: icon, text: text));
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Widget _buildToast(BuildContext context, LyneTheme t) {
    final toast = _toast!;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.isDark ? 0.34 : 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(toast.icon, size: 16, color: t.soon),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    toast.text,
                    style: t.sans(13, weight: FontWeight.w500, color: t.fg),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 2. Title block ────────────────────────────────────────────────────
  Widget _buildTitleBlock(BuildContext context, LyneTheme t, Service? live) {
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = live != null
        ? ArrivalConfidence.of(monitored: live.monitored, feed: feed)
        : ArrivalConfidence.none;
    final isLive = conf != ArrivalConfidence.none;
    final dest = live?.dest ?? '';

    return Column(
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
    );
  }

  // ── 3. Hero — ETA · stops-away · crowd · deck · next two ───────────────
  Widget _buildHeroCard(LyneTheme t) {
    final s = _liveService();
    final now = DateTime.now();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroEtaRow(t, s, now),
                    const SizedBox(height: 2),
                    Text(
                      _approachContext(s != null),
                      style: t.sans(13, color: t.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (s != null) ...[
                const SizedBox(width: 12),
                CrowdMeter(load: s.load),
              ],
            ],
          ),
          if (s != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: t.line),
            const SizedBox(height: 12),
            _heroFooter(t, s, now),
          ],
        ],
      ),
    );
  }

  Widget _heroEtaRow(LyneTheme t, Service? s, DateTime now) {
    if (s == null) {
      return Text('No live arrival',
          style: t.sans(20, weight: FontWeight.w700, color: t.dim));
    }
    final eta = fmtEta(_liveEtaSec(s, now));
    if (eta.big == 'Arr') {
      return Text('Arriving',
          style: t.sans(30, weight: FontWeight.w700, color: t.soon));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(eta.big, style: t.mono(40, weight: FontWeight.w700, color: t.fg)),
        const SizedBox(width: 5),
        Text(eta.small, style: t.sans(16, weight: FontWeight.w600, color: t.dim)),
      ],
    );
  }

  /// Quiet footer: deck type (+ wheelchair) on the left, the next two arrivals
  /// on the right — vehicle facts kept out of the headline.
  Widget _heroFooter(LyneTheme t, Service s, DateTime now) {
    final next = _nextTwoText(s, now);
    return Row(
      children: [
        Icon(Icons.directions_bus_rounded, size: 13, color: t.dim),
        const SizedBox(width: 6),
        Text(s.deck.word, style: t.mono(11, weight: FontWeight.w500, color: t.dim)),
        if (s.wab) ...[
          const SizedBox(width: 6),
          Icon(Icons.accessible_rounded, size: 13, color: t.dim),
        ],
        const Spacer(),
        if (next.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Then ',
                  style: t.sans(11, weight: FontWeight.w600, color: t.faint)),
              Text(next, style: t.mono(12, weight: FontWeight.w600, color: t.dim)),
            ],
          ),
      ],
    );
  }

  /// "10 · 26 min" for the 2nd/3rd arrivals (empty when neither exists).
  String _nextTwoText(Service s, DateTime now) {
    String? mins(DateTime? d) {
      if (d == null) return null;
      final e = fmtEta(d.difference(now).inSeconds.clamp(0, 1 << 30));
      return e.big == 'Arr' ? 'now' : e.big;
    }

    final parts = [mins(s.followingDate), mins(s.thirdDate)]
        .whereType<String>()
        .toList();
    if (parts.isEmpty) return '';
    return '${parts.join(" · ")} min';
  }

  /// Supporting context beneath the hero number.
  String _approachContext(bool hasService) {
    if (!hasService) return 'Waiting for the next ${widget.svc}';
    final n = _stopsRemaining();
    if (n != null) {
      return n == 0 ? 'At your stop now' : '$n stop${n == 1 ? '' : 's'} away';
    }
    return 'On the way to your stop';
  }

  // ── 4. Live module — route strip + map preview (fills the screen) ──────
  Widget _buildLiveModule(LyneTheme t) {
    final dir = _currentDir;
    final hasStrip =
        dir != null && dir.stops.isNotEmpty && _estimatedBusIndex() != null;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        // Stretch children to full height: the map panel is an all-Positioned
        // Stack, which would otherwise collapse to zero height (blank map).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasStrip) ...[
            SizedBox(
              width: 150,
              child: InkWell(
                onTap: _openRouteCard,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, c) => SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: c.maxHeight),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [_liveRouteStrip(dir)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'FULL ROUTE',
                            style: t
                                .mono(9, weight: FontWeight.w600, color: t.faint)
                                .copyWith(letterSpacing: 0.8),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.keyboard_arrow_up_rounded,
                              size: 13, color: t.faint),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(width: 1, color: t.line),
          ],
          Expanded(
            child: InkWell(
              onTap: _openMapSheet,
              child: _buildMapPanel(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPanel(LyneTheme t) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: _buildMapWidget(
              controller: _previewCtrl,
              interactive: false,
              onReady: () {
                _previewReady = true;
                _framePreview();
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(LyneRadius.full),
                border: Border.all(color: t.line, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_rounded, size: 12, color: t.fg),
                  const SizedBox(width: 5),
                  Text('Open map',
                      style:
                          t.mono(10, weight: FontWeight.w700, color: t.fg)),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_up_rounded, size: 13, color: t.fg),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Compact route strip ───────────────────────────────────────────────
  List<_StripNode> _stripNodes(RouteDirection dir) {
    final stops = dir.stops;
    final busIdx0 = _estimatedBusIndex();
    if (stops.isEmpty || busIdx0 == null) return const [];
    final youIdx = dir.youIndex.clamp(0, stops.length - 1);
    final busIdx = busIdx0.clamp(0, youIdx);
    final n = (youIdx - busIdx).clamp(0, stops.length);

    final nodes = <_StripNode>[];
    if (busIdx > 0) {
      nodes.add(_StripNode(_StripKind.origin, stops.first.name, null));
    }
    final busSub = n == 0 ? 'At your stop' : '$n stop${n == 1 ? '' : 's'} away';
    nodes.add(_StripNode(_StripKind.bus, 'Bus ${widget.svc}', busSub));
    nodes.add(_StripNode(
        _StripKind.you, 'Your stop', DataStore.shared.stopName(widget.stopCode)));
    if (youIdx < stops.length - 1) {
      nodes.add(_StripNode(_StripKind.dest, stops.last.name, null));
    }
    return nodes;
  }

  Widget _liveRouteStrip(RouteDirection dir) {
    final nodes = _stripNodes(dir);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++) _stripRow(nodes, i),
      ],
    );
  }

  Widget _stripRow(List<_StripNode> nodes, int i) {
    final t = context.t;
    final node = nodes[i];
    final isLast = i == nodes.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: isLast ? 24 : 42,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              if (!isLast)
                Positioned(
                  top: 12,
                  child: SizedBox(
                    width: 3,
                    height: 42,
                    child: _stripConnector(node.kind),
                  ),
                ),
              _stripDot(node.kind),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: (node.kind == _StripKind.bus || node.kind == _StripKind.you)
                  ? 0
                  : 3,
            ),
            child: _stripLabel(node, t),
          ),
        ),
      ],
    );
  }

  Widget _stripConnector(_StripKind afterKind) {
    final t = context.t;
    if (afterKind == _StripKind.bus) {
      // The covered run (bus → your stop): solid green.
      return Center(child: Container(width: 2.5, color: t.soon));
    }
    // The rest of the line: a faint dashed rail.
    return CustomPaint(
      painter: _DashedVLinePainter(color: t.faint, strokeWidth: 1.5),
    );
  }

  Widget _stripDot(_StripKind kind) {
    final t = context.t;
    Widget inner;
    switch (kind) {
      case _StripKind.origin:
        inner = Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.faint, width: 1.5),
          ),
        );
      case _StripKind.bus:
        inner = Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.soon,
            shape: BoxShape.circle,
            border: Border.all(color: t.surface, width: 2),
          ),
          child: Icon(Icons.directions_bus_rounded,
              size: 10, color: t.contrastFg),
        );
      case _StripKind.you:
        inner = Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.soon, width: 3),
          ),
        );
      case _StripKind.dest:
        inner = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: t.dim, shape: BoxShape.circle),
        );
    }
    return SizedBox(width: 24, height: 24, child: Center(child: inner));
  }

  Widget _stripLabel(_StripNode node, LyneTheme t) {
    switch (node.kind) {
      case _StripKind.origin:
      case _StripKind.dest:
        return Text(
          node.title,
          style: t.mono(11, color: t.faint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case _StripKind.bus:
      case _StripKind.you:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              node.title,
              style: t.sans(14, weight: FontWeight.w600, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (node.sub != null)
              Text(
                node.sub!,
                style: t.sans(12,
                    color: node.kind == _StripKind.bus ? t.soon : t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );
    }
  }

  // ── Route card (bottom sheet — full route + live bus position) ─────────
  void _openRouteCard() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final t = ctx.t;
            final dest =
                _liveService()?.dest ?? _currentDir?.destinationName ?? '';
            final stops = _timelineStops();
            final dirs = _serviceRoute?.directions.length ?? 0;
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bus ${widget.svc}',
                              style: t.sans(22,
                                  weight: FontWeight.w700, color: t.fg)),
                          if (dest.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text('Towards $dest',
                                style: t.sans(14, color: t.dim)),
                          ],
                          if (dirs > 1) ...[
                            const SizedBox(height: 14),
                            _routeCardDirectionToggle(t, setSheet),
                          ],
                          const SizedBox(height: 14),
                          RouteTimeline(
                            svc: widget.svc,
                            stops: stops,
                            alightId: null,
                            onAlight: (_) {},
                            selectable: false,
                            embedded: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _routeCardDirectionToggle(
      LyneTheme t, void Function(void Function()) setSheet) {
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
          _route = _routeFromDir(sr.directions[newIdx]);
        });
        _recomputePlot();
        setSheet(() {});
      },
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  // ── Map sheet (tapped up from the preview — half height first) ─────────
  Future<void> _openMapSheet() async {
    if (!mounted) return;
    setState(() {
      _mapOpen = true;
      _didAutoFrame = false; // reframe each time the sheet opens
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildMapSheet(ctx),
    );
    if (mounted) setState(() => _mapOpen = false);
  }

  Widget _buildMapSheet(BuildContext ctx) {
    final t = ctx.t;
    final h = MediaQuery.sizeOf(ctx).height * 0.64;
    return Container(
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildMapWidget(
              controller: _mapCtrl,
              interactive: true,
              onReady: _onMapSheetReady,
            ),
          ),
          // Drag handle.
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Title pill — no Done button (drag down to dismiss).
          Positioned(
            left: 16,
            top: 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(LyneRadius.full),
                border: Border.all(color: t.line, width: 1),
              ),
              child: Text('Bus ${widget.svc}',
                  style: t.sans(15, weight: FontWeight.w700, color: t.fg)),
            ),
          ),
          // Live-position callout — bottom-left.
          Positioned(
            left: 16,
            right: 76,
            bottom: 20,
            child: _buildPositionCallout(context, t),
          ),
          // Recenter controls — bottom-right (user when available, then bus).
          Positioned(
            right: 16,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (LocationService.shared.lastLocation != null) ...[
                  _MapControl(
                    onTap: _recenterOnUser,
                    semanticsLabel: 'Center on my location',
                    child:
                        Icon(Icons.my_location_rounded, size: 18, color: t.fg),
                  ),
                  const SizedBox(height: 10),
                ],
                _MapControl(
                  onTap: _recenterOnBus,
                  semanticsLabel: 'Recenter on the bus',
                  child: Icon(Icons.directions_bus_rounded,
                      size: 18, color: t.fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onMapSheetReady() {
    final p = _displayPlot.value;
    if (p != null) {
      _frameSceneIfNeeded(p.lat, p.lon);
    } else {
      final s = DataStore.shared.stopByCode[widget.stopCode];
      if (s != null) {
        try {
          _mapCtrl.move(LatLng(s.latitude, s.longitude), 15.5);
        } catch (_) {}
      }
    }
  }

  // ── Live-position callout ──────────────────────────────────────────────
  Widget _buildPositionCallout(BuildContext context, LyneTheme t) {
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
        final distLabel =
            data.distMetres != null ? ' · ${fmtDistance(data.distMetres!)}' : '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

  // ── Shared FlutterMap (preview + sheet) ────────────────────────────────
  Widget _buildMapWidget({
    required MapController controller,
    required bool interactive,
    VoidCallback? onReady,
  }) {
    final t = context.t;
    final stop = DataStore.shared.stopByCode[widget.stopCode];

    final double centerLat = stop?.latitude ?? 1.3521;
    final double centerLon = stop?.longitude ?? 103.8198;

    final tileUrl = t.isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    return ListenableBuilder(
      listenable: LocationService.shared,
      builder: (context, _) {
        final staticMarkers = <Marker>[];

        if (stop != null) {
          staticMarkers.add(
            Marker(
              point: LatLng(stop.latitude, stop.longitude),
              width: 40,
              height: 44,
              alignment: Alignment.topCenter,
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

        // User dot — gated so a far-away fix (e.g. a default simulator
        // location) can't force the camera to zoom out across the globe.
        final userLoc = LocationService.shared.lastLocation;
        if (userLoc != null &&
            (stop == null ||
                haversine(userLoc.lat, userLoc.lon, stop.latitude,
                        stop.longitude) <
                    50000)) {
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
          mapController: controller,
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLon),
            initialZoom: 15.0,
            onMapReady: onReady,
            interactionOptions: InteractionOptions(
              flags: interactive
                  ? (InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.flingAnimation)
                  : InteractiveFlag.none,
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
            MarkerLayer(markers: staticMarkers),
            _buildBusMarkerLayer(context, t),
            if (interactive)
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

  /// Bus pin layer (AnimatedBuilder on _displayPlot) — only this rebuilds on a
  /// glide frame. Shared by the preview and the map sheet.
  Widget _buildBusMarkerLayer(BuildContext context, LyneTheme t) {
    return AnimatedBuilder(
      animation: _displayPlot,
      builder: (context, _) {
        final plot = _displayPlot.value;
        if (plot == null) return const MarkerLayer(markers: []);

        final tier = plot.tier;
        final estimated = tier == _BusTier.estimated;
        final isRecent = tier == _BusTier.recent;
        final ageSec = plot.ageSec;

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

  // ── 5. First / last bus footer ─────────────────────────────────────────
  Widget _buildFirstLastFooter(LyneTheme t) {
    final tt = DataStore.shared.busTimings(
      serviceNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (tt == null) return const SizedBox.shrink();
    final use24 = AppModel.shared.use24h;
    final first = fmtClock(tt.first, use24h: use24);
    final last = fmtClock(tt.last, use24h: use24);
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: t.faint),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'First $first  ·  Last $last',
            style: t.sans(12, weight: FontWeight.w500, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Route strip model ────────────────────────────────────────────────────────
enum _StripKind { origin, bus, you, dest }

class _StripNode {
  const _StripNode(this.kind, this.title, this.sub);
  final _StripKind kind;
  final String title;
  final String? sub;
}

// ─── Map control button ──────────────────────────────────────────────────────
/// A circular control button (top bar + floating map controls). 48×48 dp tap
/// target wrapping a 40×40 dp visual circle, with a Material ripple.
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
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Material(
            color: t.surface,
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

/// Bus pill marker — solid dark capsule (live/recent) or a light dashed-border
/// "≈" capsule (estimated), honoring the position tiers.
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

/// Paints a vertical dashed line — the inactive rail in the compact route strip.
class _DashedVLinePainter extends CustomPainter {
  _DashedVLinePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    final path = ui.Path()
      ..moveTo(x, 0)
      ..lineTo(x, size.height);
    _drawDashedPath(canvas, path, paint, dash: 2, gap: 4);
  }

  @override
  bool shouldRepaint(_DashedVLinePainter old) =>
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
