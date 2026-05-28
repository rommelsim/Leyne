// SoftBusScreen — Leyne 2.0 Bus tracking (Material 3 Android variant).
// Live arrival numeral + route timeline + live map.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/v2/route_timeline.dart';
import '../../widgets/v2/soft_components.dart';

class SoftBusScreen extends StatefulWidget {
  const SoftBusScreen(
      {super.key,
      required this.stopCode,
      required this.svc,
      required this.onBack});
  final String stopCode;
  final String svc;
  final VoidCallback onBack;

  @override
  State<SoftBusScreen> createState() => _SoftBusScreenState();
}

class _SoftBusScreenState extends State<SoftBusScreen> {
  RouteInfo? _route;
  String? _alightId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      DataStore.shared.ensureArrivals(widget.stopCode);
      final r = await DataStore.shared
          .route(serviceNo: widget.svc, stopCode: widget.stopCode);
      if (mounted) setState(() => _route = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text('Bus tracking',
            style: t.sans(18, weight: FontWeight.w500, color: t.fg)),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Start Live Activity',
            onPressed: () {
              // Live Activity equivalent on Android = ongoing notification.
              // Defer to NotificationsService in a later patch.
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: DataStore.shared,
          builder: (context, _) {
            final live = _liveService();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _compactHeader(context),
                const SizedBox(height: 16),
                _arrivalCard(context, live),
                const SizedBox(height: 16),
                _liveActivityCard(context),
                const SizedBox(height: 16),
                _mapSection(context),
                const SizedBox(height: 16),
                if (_route != null)
                  RouteTimeline(
                    svc: widget.svc,
                    stops: _timelineStops(live),
                    alightId: _alightId,
                    onAlight: (id) => setState(() => _alightId = id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Service? _liveService() {
    final a = DataStore.shared.arrivals[widget.stopCode];
    if (a == null || a.kind != ArrivalStateKind.loaded) return null;
    return a.services.firstWhere((s) => s.no == widget.svc,
        orElse: () => a.services.first);
  }

  Widget _compactHeader(BuildContext context) {
    final t = context.t;
    final ds = DataStore.shared;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('Stop ${widget.stopCode}'),
        const SizedBox(height: 4),
        Text(ds.stopName(widget.stopCode),
            style: t.sans(24, weight: FontWeight.w500, color: t.fg)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.directions_walk, size: 12, color: t.dim),
          const SizedBox(width: 6),
          Text(ds.roadName(widget.stopCode).isEmpty
              ? 'Live · LTA'
              : ds.roadName(widget.stopCode),
              style: t.mono(11, color: t.dim)),
        ]),
      ],
    );
  }

  Widget _arrivalCard(BuildContext context, Service? svc) {
    final t = context.t;
    final eta = svc == null ? null : fmtEta(svc.etaSec);
    final next = svc == null ? null : fmtEta(svc.followingSec);
    // Fixed height (not minHeight) because the child Column uses a
    // Spacer to push "Following" to the bottom — that needs a bounded
    // parent height. The ListView this card sits in provides unbounded
    // height, so an unbounded Spacer crashes layout (RenderBox not laid
    // out → cascading null-check exceptions on the next frame).
    return Container(
      padding: const EdgeInsets.all(18),
      height: 160,
      decoration: BoxDecoration(
          color: t.liveBg, borderRadius: BorderRadius.circular(24)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  ServiceBadge(svc: widget.svc, size: ServiceBadgeSize.sm),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('→ ${svc?.dest ?? "—"}',
                        style: t.sans(13,
                            weight: FontWeight.w500, color: t.fg),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 12),
                const Eyebrow('Next arrival'),
                const Spacer(),
                const Eyebrow('Following'),
                const SizedBox(height: 4),
                Text(next == null ? '—' : '${next.big}${next.small}',
                    style: t.mono(14,
                        weight: FontWeight.w600, color: t.fg)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(eta?.big ?? '—',
                  style: t.mono(56, color: t.accent)
                      .copyWith(letterSpacing: -2, height: 1)),
              Text(eta?.small ?? '',
                  style: t.mono(12, color: t.dim)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveActivityCard(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: t.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: t.liveBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.lock_outline, color: t.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Track in notifications',
                  style: t.sans(14,
                      weight: FontWeight.w600, color: t.fg)),
              Text('Follow Bus ${widget.svc} from your status bar',
                  style: t.sans(12, color: t.dim)),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: t.dim),
      ]),
    );
  }

  Widget _mapSection(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Live map'),
        const SizedBox(height: 8),
        _mapLegend(context),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: LocationService.shared,
          builder: (context, _) {
            final stop = DataStore.shared.stopByCode[widget.stopCode];
            if (stop == null) {
              return Container(
                height: 180,
                decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(20)),
                alignment: Alignment.center,
                child: Text('Loading map…',
                    style: t.mono(11, color: t.dim)),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 200,
                child: _LiveMap(
                  stopLat: stop.latitude,
                  stopLon: stop.longitude,
                  busCoord: _route?.busCoord,
                  busNo: widget.svc,
                  userLoc: LocationService.shared.lastLocation,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _mapLegend(BuildContext context) {
    final t = context.t;
    Widget item(IconData icon, Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: t.mono(9, weight: FontWeight.w600, color: t.dim)
                    .copyWith(letterSpacing: 1)),
          ],
        );
    return Row(
      children: [
        item(Icons.location_on, t.accent, 'STOP'),
        const SizedBox(width: 12),
        item(Icons.directions_bus, t.accent, 'BUS ${widget.svc}'),
        const SizedBox(width: 12),
        item(Icons.my_location, LyneSignal.meBlue, 'YOU'),
      ],
    );
  }

  List<SoftRouteStop> _timelineStops(Service? live) {
    final r = _route;
    if (r == null) return const [];
    final seg = journeySegment(r);
    final youSeq = r.youIndex;
    final busSeq = r.busIndex;
    final baseMin = (live?.etaSec ?? 0) ~/ 60;
    final yIdx = youSeq < 0 ? 0 : youSeq;
    return seg.map((stop) {
      final idx = r.stops.indexWhere((s) => s.code == stop.code);
      SoftRouteStopState state;
      if (busSeq != null && idx == busSeq) {
        state = SoftRouteStopState.here;
      } else if (idx == youSeq) {
        state = SoftRouteStopState.board;
      } else if (idx < (busSeq ?? -1)) {
        state = SoftRouteStopState.past;
      } else {
        state = SoftRouteStopState.next;
      }
      final etaMin = state == SoftRouteStopState.next
          ? (baseMin + (idx - yIdx) * 2).clamp(0, 999)
          : null;
      return SoftRouteStop(
          id: stop.code, name: stop.name, state: state, etaMin: etaMin);
    }).toList();
  }
}

/// Live map for SoftBusScreen — OSM via flutter_map. Same icon language
/// as the iOS SwiftUI map: pin for stop, accent pill (bus icon + svc no)
/// for the live bus, blue dot for the user.
class _LiveMap extends StatelessWidget {
  const _LiveMap({
    required this.stopLat,
    required this.stopLon,
    required this.busCoord,
    required this.busNo,
    required this.userLoc,
  });

  final double stopLat;
  final double stopLon;
  final GeoPoint? busCoord;
  final String busNo;
  final ({double lat, double lon})? userLoc;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lats = <double>[stopLat];
    final lons = <double>[stopLon];
    final b = busCoord;
    if (b != null) {
      lats.add(b.lat);
      lons.add(b.lon);
    }
    final u = userLoc;
    if (u != null) {
      lats.add(u.lat);
      lons.add(u.lon);
    }
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b);
    final maxLon = lons.reduce((a, b) => a > b ? a : b);
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final spanLat = ((maxLat - minLat) * 1.6).clamp(0.004, 0.5);
    final zoom = spanLat < 0.005
        ? 16.0
        : spanLat < 0.01
            ? 15.0
            : spanLat < 0.02
                ? 14.0
                : spanLat < 0.05
                    ? 13.0
                    : 12.0;

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLon),
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.flingAnimation,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.leyne.leyne',
          maxNativeZoom: 19,
        ),
        MarkerLayer(
          markers: [
            // Stop pin — accent location icon with soft shadow.
            Marker(
              point: LatLng(stopLat, stopLon),
              width: 40,
              height: 44,
              alignment: Alignment.topCenter,
              child: _MarkerShadow(
                child: Icon(Icons.location_on,
                    size: 40, color: t.accent),
              ),
            ),
            if (b != null)
              Marker(
                point: LatLng(b.lat, b.lon),
                width: 72,
                height: 32,
                child: _BusPillMarker(busNo: busNo, color: t.accent),
              ),
            if (u != null)
              Marker(
                point: LatLng(u.lat, u.lon),
                width: 20,
                height: 20,
                child: _UserDot(color: LyneSignal.meBlue),
              ),
          ],
        ),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _MarkerShadow extends StatelessWidget {
  const _MarkerShadow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );
}

class _BusPillMarker extends StatelessWidget {
  const _BusPillMarker({required this.busNo, required this.color});
  final String busNo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_bus, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(busNo,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
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
          BoxShadow(
              color: color.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }
}
