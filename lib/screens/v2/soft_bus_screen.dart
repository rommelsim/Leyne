// SoftBusScreen — Leyne 2.0 Bus tracking (Material 3 Android variant).
// Live arrival numeral + route timeline + map placeholder.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
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
    return Container(
      padding: const EdgeInsets.all(18),
      constraints: const BoxConstraints(minHeight: 160),
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
        Row(children: [
          const Eyebrow('Live map'),
          const Spacer(),
          LegendDot(label: 'BUS ${widget.svc}', color: t.accent),
          const SizedBox(width: 10),
          LegendDot(label: 'ME', color: LyneSignal.meBlue),
        ]),
        const SizedBox(height: 8),
        Container(
          height: 180,
          decoration: BoxDecoration(
              color: t.surface, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: Text('Live map · LTA',
              style: t.mono(11, color: t.dim)),
        ),
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
