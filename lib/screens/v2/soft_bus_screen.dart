// SoftBusScreen — Leyne 3.0 immersive bus tracking (Material 3 Android).
//
// Full-bleed map backdrop with a draggable bottom sheet. The peek answers
// "when's my bus" instantly; pulling up reveals Alerts + route timeline. The
// map uses flutter_map with free CartoDB basemap tiles (no API key, no
// billing) — a clean modern style, not the dated default OSM raster. The bus
// pin is always plotted in one of three honest tiers:
//   • LIVE      — Service.busLat/busLon present → solid accent pill
//   • RECENT    — last-known fix <150s → dimmed solid pill, "last seen"
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
import 'package:flutter/physics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  // ── Bus pin animation (glide between positions) ──────────────────────
  // Performance: the glide drives _displayCoord (a ValueNotifier) instead
  // of calling setState on the whole State. AnimatedBuilder inside
  // _buildMap listens only to this notifier, so map tiles and the rest of
  // the Stack do NOT rebuild during a 1.5-second glide.
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
    if (_didAutoFrame) return;
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
    final showFull = widget.fullRoute || (dir != null && !dir.anchorPresent);
    final seg = showFull ? r.stops : journeySegment(r);
    final youSeq = r.youIndex;
    final busSeq = r.busIndex;
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
      SoftRouteStopState state;
      if (busSeq != null && idx == busSeq) {
        state = SoftRouteStopState.here;
      } else if (canMarkBoard && idx == youSeq) {
        state = SoftRouteStopState.board;
      } else if (idx < (busSeq ?? -1)) {
        state = SoftRouteStopState.past;
      } else {
        state = SoftRouteStopState.next;
      }
      return SoftRouteStop(id: stop.code, name: stop.name, state: state);
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar — the map is full-bleed and floating controls replace it.
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
        builder: (context, _) {
          final live = _liveService();
          final isPinned = AppModel.shared.isPinned(widget.stopCode);
          return Stack(
            children: [
              // ── Full-bleed map backdrop ──────────────────────────────
              Positioned.fill(child: _buildMap(context)),

              // ── Floating top controls (back + bus badge + pin + recenter)
              _FloatingTopBar(
                svc: widget.svc,
                onBack: widget.onBack,
                onRecenter: _recenterOnUser,
                isPinned: isPinned,
                onPin: () => AppModel.shared.togglePin(widget.stopCode),
              ),

              // ── Draggable bottom sheet ───────────────────────────────
              _DraggableSheet(
                peek: 0.42,
                minFraction: 0.30,
                maxFraction: 0.92,
                header: _buildSheetHeader(context, live),
                body: _buildSheetBody(context, live),
              ),
            ],
          );
        },
      ),
    );
  }

  void _recenterOnUser() {
    _didAutoFrame = true; // user took over framing
    final u = LocationService.shared.lastLocation;
    if (u != null) {
      _mapCtrl.move(LatLng(u.lat, u.lon), 16.0);
    }
  }

  // ── Map ──────────────────────────────────────────────────────────────
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

  // ── Sheet header ─────────────────────────────────────────────────────
  Widget _buildSheetHeader(BuildContext context, Service? live) {
    final t = context.t;
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = live != null
        ? ArrivalConfidence.of(monitored: live.monitored, feed: feed)
        : ArrivalConfidence.none;
    // Timely-first: show LIVE whenever there's a service with an ETA.
    final pillConf = conf == ArrivalConfidence.none
        ? ArrivalConfidence.none
        : ArrivalConfidence.live;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Bus service'),
              const SizedBox(height: 2),
              Text(
                'Towards ${live?.dest ?? '—'}',
                style: t.sans(22, weight: FontWeight.w700, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ConfidenceStatusPill(confidence: pillConf),
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

  // ── Sheet body ───────────────────────────────────────────────────────
  Widget _buildSheetBody(BuildContext context, Service? live) {
    final t = context.t;
    final st = DataStore.shared.arrivals[widget.stopCode];
    final allNos = st != null && st.kind == ArrivalStateKind.loaded
        ? st.services.map((s) => s.no).toList()
        : <String>[];

    // Compute timeline stops once — used for both the count label and the
    // RouteTimeline widget. Previously called 4 times in one build pass.
    final timelineStops = _timelineStops();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.line),
        const SizedBox(height: 4),
        _heroETA(context, live),
        const SizedBox(height: 20),
        // ── Alerts ──────────────────────────────────────────────────
        const Eyebrow('Alerts'),
        const SizedBox(height: 8),
        _notifyButton(context, allNos),
        if (live != null) ...[
          const SizedBox(height: 12),
          _ongoingCard(context, live),
        ],
        const SizedBox(height: 20),
        // ── Route timeline ──────────────────────────────────────────
        if (_route != null) ...[
          // Direction toggle — only shown when the service has more than one
          // direction (virtually all routes).  Uses a SegmentedButton so
          // Material handles selection, focus, and accessibility states.
          if ((_serviceRoute?.directions.length ?? 0) > 1) ...[
            _buildDirectionToggle(context, t),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(Icons.route_rounded, size: 14, color: t.dim),
              const SizedBox(width: 6),
              Eyebrow(
                timelineStops.isEmpty
                    ? 'Full route'
                    : 'Full route · ${timelineStops.length} stops',
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: t.line)),
            ],
          ),
          const SizedBox(height: 6),
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
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Hero ETA ─────────────────────────────────────────────────────────
  Widget _heroETA(BuildContext context, Service? svc) {
    final t = context.t;

    if (svc == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Arriving at ${DataStore.shared.stopName(widget.stopCode)}'),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '—',
                style: t
                    .mono(64, color: t.faint)
                    .copyWith(letterSpacing: -2, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bus ${widget.svc} has passed — no live data',
            style: t.sans(13, color: t.dim),
          ),
        ],
      );
    }

    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: svc.monitored, feed: feed);
    final eta = fmtEta(svc.etaSec);
    final next = fmtEta(svc.followingSec);
    final thirdSec = svc.thirdDate
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 1 << 30);
    final third = thirdSec != null ? fmtEta(thirdSec) : null;
    final imminent = conf == ArrivalConfidence.live && eta.live;
    final whisper =
        conf == ArrivalConfidence.stale ||
        conf == ArrivalConfidence.unconfirmed;
    // Whisper when the current tier is anything other than a fresh live fix.
    // Reads directly from the first-class tier — no re-derive of svc.busLat.
    final currentTier = _currentTarget?.tier;
    final pinEstimated =
        currentTier == _BusTier.estimated || currentTier == _BusTier.recent;
    final showWhisper = whisper || pinEstimated;

    // Stop walk-distance suffix — mirroring iOS stopDistanceSuffix.
    String distSuffix = '';
    final here = LocationService.shared.lastLocation;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (here != null && stop != null) {
      final d = haversine(here.lat, here.lon, stop.latitude, stop.longitude);
      distSuffix = ' · ${fmtDistance(d.round())} away';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('Arriving at ${DataStore.shared.stopName(widget.stopCode)}'),
        const SizedBox(height: 12),
        // Hero numeral row.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              eta.big == 'Arr' ? 'Now' : eta.big,
              style: t
                  .mono(
                    64,
                    color: conf == ArrivalConfidence.none
                        ? t.faint
                        : (imminent ? t.accent : t.fg),
                  )
                  .copyWith(letterSpacing: -2, height: 1),
            ),
            if (eta.big != 'Arr') ...[
              const SizedBox(width: 4),
              Text(
                eta.small,
                style: t.mono(20, color: imminent ? t.accent : t.dim),
              ),
            ],
            if (showWhisper) ...[
              const SizedBox(width: 4),
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0.7,
                  child: Text('~', style: t.mono(14, color: t.faint)),
                ),
              ),
            ],
            const Spacer(),
            // Next-two label — right-aligned, baseline-aligned with the numeral.
            if (_nextTwoLabel(svc, next, third) != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _nextTwoLabel(svc, next, third)!,
                  style: t.mono(13, weight: FontWeight.w600, color: t.dim),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // Stop code + distance + crowd.
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Stop ',
                      style: t.sans(13, color: t.dim),
                    ),
                    TextSpan(
                      text: widget.stopCode,
                      style: t.mono(13, weight: FontWeight.w700, color: t.fg),
                    ),
                    TextSpan(
                      text: distSuffix,
                      style: t.sans(13, color: t.dim),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            CrowdMeter(load: svc.load),
          ],
        ),
      ],
    );
  }

  String? _nextTwoLabel(Service svc, Eta next, Eta? third) {
    if (next.big == 'Arr' || next.big.isEmpty) return null;
    if (third != null && third.big != 'Arr' && third.big.isNotEmpty) {
      return 'then ${next.big} · ${third.big} min';
    }
    return 'then ${next.big} min';
  }

  // ── Notify button ────────────────────────────────────────────────────
  Widget _notifyButton(BuildContext context, List<String> allNos) {
    final t = context.t;
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
  Widget _ongoingCard(BuildContext context, Service live) {
    final t = context.t;
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

// ─── Floating top bar ────────────────────────────────────────────────────────
/// Back chevron + bus badge + pin capsule + recenter button, floating over the
/// map. Mirrors iOS floatingTopControls: back · badge · recenter · pin.
class _FloatingTopBar extends StatelessWidget {
  const _FloatingTopBar({
    required this.svc,
    required this.onBack,
    required this.onRecenter,
    required this.isPinned,
    required this.onPin,
  });

  final String svc;
  final VoidCallback onBack;
  final VoidCallback onRecenter;
  final bool isPinned;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // Back button.
            _MapControl(
              onTap: onBack,
              semanticsLabel: 'Back',
              child: Icon(Icons.chevron_left_rounded, size: 22, color: t.fg),
            ),
            const SizedBox(width: 10),
            // Bus badge — identity capsule.
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: t.contrast,
                borderRadius: BorderRadius.circular(LyneRadius.full),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.directions_bus_rounded,
                    size: 15,
                    color: t.contrastFg,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    svc,
                    style: t.sans(
                      17,
                      weight: FontWeight.w700,
                      color: t.contrastFg,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Recenter on user.
            _MapControl(
              onTap: onRecenter,
              semanticsLabel: 'Center on my location',
              child: Icon(Icons.my_location_rounded, size: 18, color: t.fg),
            ),
            const SizedBox(width: 8),
            // Pin / Unpin capsule — mirrors iOS pin capsule.
            // Uses Material + InkWell for ripple; 48dp tap target, 40dp visual.
            Semantics(
              label: isPinned ? 'Unpin this stop' : 'Pin this stop to Home',
              button: true,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Material(
                    color: isPinned ? t.accent : t.surface,
                    borderRadius: BorderRadius.circular(LyneRadius.full),
                    elevation: 0,
                    child: InkWell(
                      onTap: onPin,
                      borderRadius: BorderRadius.circular(LyneRadius.full),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(LyneRadius.full),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 5,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 13,
                              color: isPinned ? t.onAccent : t.fg,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isPinned ? 'Pinned' : 'Pin',
                              style: t.sans(
                                13,
                                weight: FontWeight.w600,
                                color: isPinned ? t.onAccent : t.fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular control button that floats over the map.
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
    // 48dp touch target wraps a 40dp visual circle.
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

// ─── Draggable bottom sheet ──────────────────────────────────────────────────
/// A bottom sheet that snaps between a peek fraction and near-full height.
/// Mirrors iOS DraggableSheet semantics: drag the handle to move, release to
/// snap; tap the handle to toggle. Lives in a ZStack-style Stack over the map.
class _DraggableSheet extends StatefulWidget {
  const _DraggableSheet({
    required this.peek,
    required this.minFraction,
    required this.maxFraction,
    required this.header,
    required this.body,
  });

  /// Sheet peek height as a fraction of the screen (0–1).
  final double peek;
  final double minFraction;
  final double maxFraction;
  final Widget header;
  final Widget body;

  @override
  State<_DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<_DraggableSheet>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // Drag offset (delta from the current snap base) stored in a ValueNotifier
  // so only the Transform.translate — not the whole sheet body — rebuilds on
  // pointer-move and during the settle animation.
  final ValueNotifier<double> _dragNotifier = ValueNotifier(0);

  // Spring-driven settle so the sheet flings/eases to its snap point with
  // real physics instead of teleporting. Unbounded because the simulation
  // drives the offset directly (it may briefly overshoot before settling).
  late final AnimationController _settleCtrl;

  // Latest collapsed translation (sheetH - peekH), refreshed each layout so
  // the gesture math uses the live value.
  double _collapsedY = 0;

  @override
  void initState() {
    super.initState();
    _settleCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() => _dragNotifier.value = _settleCtrl.value);
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    _dragNotifier.dispose();
    super.dispose();
  }

  /// Current absolute translateY (0 = fully expanded, _collapsedY = peek),
  /// clamped to the travel range.
  double get _absolute {
    final base = _expanded ? 0.0 : _collapsedY;
    return (base + _dragNotifier.value).clamp(0.0, _collapsedY);
  }

  /// Hand the current absolute position to the new snap base without a visual
  /// jump, then spring the offset back to rest — carrying [velocity] (px/s)
  /// so a flick flings naturally.
  void _settleTo(bool expand, double velocity) {
    final absolute = _absolute;
    final newBase = expand ? 0.0 : _collapsedY;
    setState(() => _expanded = expand);
    _dragNotifier.value = absolute - newBase; // continuous across the flip
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 480,
      ratio: 1,
    );
    _settleCtrl.animateWith(
      SpringSimulation(spring, _dragNotifier.value, 0, velocity),
    );
  }

  /// Pick the snap target from fling velocity, falling back to nearest edge.
  void _onDragEnd(double velocity) {
    if (velocity < -300) {
      _settleTo(true, velocity); // fling up → expand
    } else if (velocity > 300) {
      _settleTo(false, velocity); // fling down → collapse
    } else {
      _settleTo(_absolute < _collapsedY / 2, velocity); // snap to nearest
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenH = constraints.maxHeight;
        final peekH = screenH * widget.peek;
        final maxH = screenH * widget.maxFraction;
        final sheetH = maxH;
        final collapsedY = sheetH - peekH;
        _collapsedY = collapsedY; // keep gesture math in sync with layout

        // The sheet content (Material + Column) is built once here and
        // passed as the non-rebuilding `child` of ValueListenableBuilder.
        // Only the Transform.translate wrapper rebuilds on drag.
        final sheetContent = Material(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          child: Column(
            children: [
              // Handle + header (always visible in peek).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _settleCtrl.stop(),
                onVerticalDragUpdate: (d) {
                  _dragNotifier.value += d.delta.dy;
                },
                onVerticalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0),
                onTap: () => _settleTo(!_expanded, 0),
                child: Semantics(
                  label: _expanded
                      ? 'Collapse details'
                      : 'Expand for alerts and full route',
                  button: true,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.faint,
                          borderRadius: BorderRadius.circular(LyneRadius.full),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: widget.header,
                      ),
                    ],
                  ),
                ),
              ),
              // Scrollable body (routes, timeline, etc.).
              Expanded(
                child: SingleChildScrollView(
                  physics: _expanded
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: widget.body,
                ),
              ),
            ],
          ),
        );

        return Stack(
          children: [
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: sheetH,
              // ValueListenableBuilder wraps only Transform.translate.
              // The sheet body is passed as `child` so it is NOT rebuilt
              // on every pointer-move event — only the translate offset changes.
              child: ValueListenableBuilder<double>(
                valueListenable: _dragNotifier,
                builder: (context, drag, child) {
                  final baseY = _expanded ? 0.0 : collapsedY;
                  final y = (baseY + drag).clamp(0.0, collapsedY);
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: child,
                  );
                },
                child: sheetContent,
              ),
            ),
          ],
        );
      },
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
            Text(
              estimated ? '≈ $busNo' : busNo,
              // Use LyneTheme.monoBase so the font matches the rest of the
              // app's mono styling rather than a hard-coded 'monospace'.
              style: LyneTheme.monoBase.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textFg,
              ),
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
