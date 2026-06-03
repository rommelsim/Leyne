// SoftStopScreen — Leyne 2.0 Stop detail (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_components.dart';
import '../notifications_screen.dart';

class SoftStopScreen extends StatefulWidget {
  const SoftStopScreen({
    super.key,
    required this.stopCode,
    required this.onBack,
    required this.onOpenBus,
    required this.onSeeAll,
    this.showAll = false,
  });
  final String stopCode;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenBus;
  final VoidCallback onSeeAll;
  final bool showAll;

  @override
  State<SoftStopScreen> createState() => _SoftStopScreenState();
}

class _SoftStopScreenState extends State<SoftStopScreen> {
  _StopSort _sort = _StopSort.arrival;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
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
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Stop ${widget.stopCode}',
          style: t.sans(18, weight: FontWeight.w500, color: t.fg),
        ),
        actions: [_masterBell(context)],
      ),
      // No FAB: pinning is implicit now — the first bell tap pins the stop
      // (tracking that bus), the last untap unpins it. Matches iOS.
      body: SafeArea(
        child: ListenableBuilder(
          // AppModel too, so bell/tracked state and the notifications-off
          // banner repaint when they change.
          listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
          builder: (context, _) {
            final m = AppModel.shared;
            final state = DataStore.shared.arrivals[widget.stopCode];
            final loaded =
                state != null && state.kind == ArrivalStateKind.loaded;
            final sorted = loaded ? _sortServices(state.services) : <Service>[];
            final allNos = sorted.map((s) => s.no).toList();
            final isPinned = m.pinForCode(widget.stopCode) != null;
            return RefreshIndicator(
              color: t.accent,
              onRefresh: () =>
                  DataStore.shared.refreshArrivals(widget.stopCode),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _header(context),
                  if (isPinned && !m.notificationsEnabled) ...[
                    const SizedBox(height: 12),
                    _notifOffBanner(context),
                  ],
                  const SizedBox(height: 16),
                  if (state == null || state.kind == ArrivalStateKind.loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.kind == ArrivalStateKind.empty)
                    _emptyCard(context, 'No buses in operation right now.')
                  else if (state.kind == ArrivalStateKind.error)
                    _emptyCard(
                      context,
                      state.errorMessage ?? 'Couldn\'t reach LTA',
                    )
                  else ...[
                    if (!isPinned) ...[
                      _hintRow(context),
                      const SizedBox(height: 12),
                    ],
                    _sortChips(context),
                    const SizedBox(height: 12),
                    // Uniform card model: every arrival is the same weight,
                    // matching iOS SoftStopView which uses a single arrivalCard
                    // for all services. First card gets richer content (crowd +
                    // then-ETA); the container sizing/styling is identical.
                    _arrivalsList(context, sorted, allNos),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Service> _sortServices(List<Service> services) {
    final out = [...services];
    switch (_sort) {
      case _StopSort.arrival:
        out.sort((a, b) => a.etaSec.compareTo(b.etaSec));
      case _StopSort.distance:
        out.sort((a, b) => _busDistance(a).compareTo(_busDistance(b)));
      case _StopSort.busNo:
        out.sort((a, b) {
          final na = int.tryParse(a.no.replaceAll(RegExp(r'\D'), ''));
          final nb = int.tryParse(b.no.replaceAll(RegExp(r'\D'), ''));
          if (na != null && nb != null && na != nb) return na.compareTo(nb);
          return a.no.compareTo(b.no);
        });
    }
    return out;
  }

  /// Metres from a bus's live GPS position to this stop, or double.maxFinite
  /// when the bus isn't transmitting a position — sinks it to the bottom so
  /// timetable-only buses rank last under the Distance sort.
  double _busDistance(Service bus) {
    final busLat = bus.busLat;
    final busLon = bus.busLon;
    if (busLat == null || busLon == null) return double.maxFinite;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return double.maxFinite;
    return haversine(busLat, busLon, stop.latitude, stop.longitude);
  }

  /// AppBar action: alert me for every bus at this stop / clear all.
  /// State tracks "alerting for ALL services" (not merely pinned) so a
  /// partial subset doesn't masquerade as a lit all-clear bell.
  Widget _masterBell(BuildContext context) {
    final t = context.t;
    final m = AppModel.shared;
    final all = m.allTracked(widget.stopCode); // pinned AND tracking every bus
    final active = all && m.notificationsEnabled;
    return IconButton(
      tooltip: all ? 'Clear all alerts' : 'Alert me for every bus',
      icon: Icon(
        active
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: active ? t.accent : t.dim,
      ),
      onPressed: () async {
        final state = DataStore.shared.arrivals[widget.stopCode];
        final allNos = state != null && state.kind == ArrivalStateKind.loaded
            ? state.services.map((s) => s.no).toList()
            : const <String>[];
        m.setAllTracked(code: widget.stopCode, allNos: allNos, tracked: !all);
        await m.rescheduleIfNeeded();
      },
    );
  }

  Widget _notifOffBanner(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: t.warnBg,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, size: 18, color: t.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Notifications are off — arrival alerts won't fire.",
              style: t.sans(13, color: t.fg),
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

  Widget _hintRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Icon(Icons.notifications_active_outlined, size: 14, color: t.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tap the bell on a bus to be alerted ~1 min before it arrives.',
            style: t.mono(11, color: t.dim),
          ),
        ),
      ],
    );
  }

  Widget _sortChips(BuildContext context) {
    return SegmentedButton<_StopSort>(
      segments: const [
        ButtonSegment(value: _StopSort.arrival, label: Text('ETA')),
        ButtonSegment(value: _StopSort.distance, label: Text('Distance')),
        ButtonSegment(value: _StopSort.busNo, label: Text('Bus no.')),
      ],
      selected: {_sort},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _sort = s.first),
    );
  }

  /// Per-bus alert bell — pins the stop on first tap, unpins on last untap.
  Widget _bell(BuildContext context, String busNo, List<String> allNos) {
    final t = context.t;
    final on = AppModel.shared.isTracked(code: widget.stopCode, busNo: busNo);
    return IconButton(
      tooltip: on ? 'Alerting for bus $busNo' : 'Alert me about bus $busNo',
      icon: Icon(
        on
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: on ? t.accent : t.dim,
        size: 22,
      ),
      onPressed: () async {
        AppModel.shared.toggleTracked(
          code: widget.stopCode,
          busNo: busNo,
          allNos: allNos,
        );
        await AppModel.shared.rescheduleIfNeeded();
      },
    );
  }

  /// Walk-distance chip value: haversine(user → stop). Null when user
  /// location is unavailable — chip is omitted entirely, not faked.
  String? _stopDistanceLabel() {
    final here = LocationService.shared.lastLocation;
    if (here == null) return null;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return null;
    final d = haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    return fmtDistance(d.round());
  }

  Widget _header(BuildContext context) {
    final t = context.t;
    final ds = DataStore.shared;
    final road = ds.roadName(widget.stopCode);
    final distLabel = _stopDistanceLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('Stop ${widget.stopCode}'),
                  const SizedBox(height: 4),
                  Text(
                    ds.stopName(widget.stopCode),
                    style: t.sans(26, weight: FontWeight.w500, color: t.fg),
                  ),
                  if (road.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(road, style: t.mono(11, color: t.dim)),
                  ],
                ],
              ),
            ),
            if (distLabel != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_walk, size: 13, color: t.dim),
                    const SizedBox(width: 3),
                    Text(
                      distLabel,
                      style: t.mono(12, weight: FontWeight.w600, color: t.dim),
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

  /// Uniform arrival cards — all services use the same container style,
  /// matching iOS SoftStopView's single-template arrivalCard(). The first
  /// service retains its richer content (crowd row + then-ETA); thereafter
  /// each card shows destination + crowd + ETA at the same visual weight.
  Widget _arrivalsList(
    BuildContext context,
    List<Service> sorted,
    List<String> allNos,
  ) {
    final t = context.t;
    final visible = widget.showAll ? sorted : sorted.take(4).toList();
    final overflow = !widget.showAll && sorted.length > 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          _arrivalCard(context, visible[i], allNos, isFirst: i == 0),
          if (i < visible.length - 1) const SizedBox(height: kSectionGap / 2),
        ],
        if (overflow) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onSeeAll,
              child: Text(
                'See all ${sorted.length - 4} more →',
                style: t.sans(13, weight: FontWeight.w600, color: t.accent),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Single arrival card. All services share the same container shape/size
  /// (uniform weight). The first card shows the crowd row and then-ETA;
  /// subsequent cards omit them to keep the list scannable without the
  /// old "hero vs supporting cast" hierarchy.
  ///
  /// Imminent (etaSec <= 60 && live) cards gain an accent stroke border
  /// and a soft accent glow — parity with iOS SoftStopView ~line 180.
  Widget _arrivalCard(
    BuildContext context,
    Service bus,
    List<String> allNos, {
    bool isFirst = false,
  }) {
    final t = context.t;
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed);
    final imminent = conf == ArrivalConfidence.live && bus.etaSec <= 60;
    final on = AppModel.shared.isTracked(code: widget.stopCode, busNo: bus.no);
    final eta = fmtEta(bus.etaSec);

    // Imminent: accent stroke @ 0.5 alpha + soft accent glow.
    // Tracked: left-rule border (accent, width 3).
    // Default: t.line hairline.
    final Border? border = on
        ? Border(left: BorderSide(color: t.accent, width: 3))
        : imminent
        ? Border.all(color: t.accent.withValues(alpha: 0.5), width: 1.5)
        : null;

    final List<BoxShadow> shadows = imminent
        ? [
            BoxShadow(
              color: t.accent.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ]
        : const [];

    // Clip the InkWell ripple inside the card's rounded corners.
    // Canonical pattern: Material + clipBehavior wraps the tappable group.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenBus(bus.no),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? t.liveBg : t.surface,
            borderRadius: BorderRadius.circular(LyneRadius.lg),
            border: border,
            boxShadow: shadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ServiceBadge(svc: bus.no, size: ServiceBadgeSize.lg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '→ ${bus.dest}',
                          style: t
                              .mono(10, weight: FontWeight.w600, color: t.dim)
                              .copyWith(letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          eta.live
                              ? 'Arriving now'
                              : 'In ${eta.big} ${eta.small}',
                          style: t.sans(
                            22,
                            weight: FontWeight.w600,
                            color: t.fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _bell(context, bus.no, allNos),
                ],
              ),
              if (isFirst) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    CrowdMeter(load: bus.load),
                    const SizedBox(width: 8),
                    Text(
                      '· Then ${fmtEta(bus.followingSec).big}'
                      '${fmtEta(bus.followingSec).small}',
                      style: t.mono(11, color: t.dim),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context, String message) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_bus, color: t.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: t.sans(14, color: t.fg)),
          ),
        ],
      ),
    );
  }
}

enum _StopSort { arrival, distance, busNo }
