// SoftStopScreen — Leyne 2.0 Stop detail (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
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
            icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text('Stop ${widget.stopCode}',
            style: t.sans(18, weight: FontWeight.w500, color: t.fg)),
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
            final loaded = state != null &&
                state.kind == ArrivalStateKind.loaded;
            final sorted =
                loaded ? _sortServices(state.services) : <Service>[];
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
                      context, state.errorMessage ?? 'Couldn\'t reach LTA')
                else ...[
                  if (!isPinned) ...[
                    _hintRow(context),
                    const SizedBox(height: 12),
                  ],
                  _sortChips(context),
                  const SizedBox(height: 12),
                  _primaryCard(context, sorted.first, allNos),
                  const SizedBox(height: 16),
                  _otherBuses(context, sorted.skip(1).toList(), allNos),
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
        m.setAllTracked(
            code: widget.stopCode, allNos: allNos, tracked: !all);
        await m.rescheduleIfNeeded();
      },
    );
  }

  Widget _notifOffBanner(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
          color: t.warnBg, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.notifications_off_outlined, size: 18, color: t.warn),
        const SizedBox(width: 10),
        Expanded(
          child: Text("Notifications are off — arrival alerts won't fire.",
              style: t.sans(13, color: t.fg)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NotificationsScreen())),
          child: Text('Enable',
              style: t.sans(13, weight: FontWeight.w600, color: t.accent)),
        ),
      ]),
    );
  }

  Widget _hintRow(BuildContext context) {
    final t = context.t;
    return Row(children: [
      Icon(Icons.notifications_active_outlined, size: 14, color: t.accent),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
            'Tap the bell on a bus to be alerted ~1 min before it arrives.',
            style: t.mono(11, color: t.dim)),
      ),
    ]);
  }

  Widget _sortChips(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<_StopSort>(
        segments: const [
          ButtonSegment(value: _StopSort.arrival, label: Text('Soonest')),
          ButtonSegment(value: _StopSort.busNo, label: Text('Bus no.')),
        ],
        selected: {_sort},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _sort = s.first),
      ),
    );
  }

  /// Per-bus alert bell — pins the stop on first tap, unpins on last untap.
  Widget _bell(BuildContext context, String busNo, List<String> allNos) {
    final t = context.t;
    final on = AppModel.shared
        .isTracked(code: widget.stopCode, busNo: busNo);
    return IconButton(
      tooltip: on ? 'Alerting for bus $busNo' : 'Alert me about bus $busNo',
      icon: Icon(
        on ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
        color: on ? t.accent : t.dim,
        size: 22,
      ),
      onPressed: () async {
        AppModel.shared.toggleTracked(
            code: widget.stopCode, busNo: busNo, allNos: allNos);
        await AppModel.shared.rescheduleIfNeeded();
      },
    );
  }

  Widget _header(BuildContext context) {
    final t = context.t;
    final ds = DataStore.shared;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('Stop ${widget.stopCode}'),
        const SizedBox(height: 4),
        Text(ds.stopName(widget.stopCode),
            style: t.sans(26, weight: FontWeight.w500, color: t.fg)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.directions_walk, size: 14, color: t.dim),
          const SizedBox(width: 6),
          Text(
              ds.roadName(widget.stopCode).isEmpty
                  ? 'Live · LTA'
                  : ds.roadName(widget.stopCode),
              style: t.mono(11, color: t.dim)),
        ]),
      ],
    );
  }

  Widget _primaryCard(
      BuildContext context, Service primary, List<String> allNos) {
    final t = context.t;
    final eta = fmtEta(primary.etaSec);
    final on = AppModel.shared
        .isTracked(code: widget.stopCode, busNo: primary.no);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => widget.onOpenBus(primary.no),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: t.liveBg,
            borderRadius: BorderRadius.circular(24),
            // Tracked: a left accent rule (shape, not just colour) so the
            // alert state reads even on the already-liveBg card.
            border: on
                ? Border(left: BorderSide(color: t.accent, width: 3))
                : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ServiceBadge(svc: primary.no, size: ServiceBadgeSize.lg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('→ ${primary.dest}',
                        style: t.mono(10,
                                weight: FontWeight.w600, color: t.dim)
                            .copyWith(letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                        eta.live
                            ? 'Arriving now'
                            : 'In ${eta.big} ${eta.small}',
                        style: t.sans(22,
                            weight: FontWeight.w600, color: t.fg)),
                  ],
                ),
              ),
              _bell(context, primary.no, allNos),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: t.accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                  '${primary.load.label.toLowerCase()} · Then ${fmtEta(primary.followingSec).big}${fmtEta(primary.followingSec).small}',
                  style: t.mono(11, color: t.dim)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _otherBuses(
      BuildContext context, List<Service> services, List<String> allNos) {
    final t = context.t;
    final visible =
        widget.showAll ? services : services.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(widget.showAll ? 'All arrivals' : 'Other buses',
              style: t.sans(13, weight: FontWeight.w600, color: t.dim)),
          const Spacer(),
          if (!widget.showAll && services.length > 3)
            TextButton(
              onPressed: widget.onSeeAll,
              child: Text('See all ${services.length} →',
                  style: t.sans(13,
                      weight: FontWeight.w600, color: t.accent)),
            ),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              color: t.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _busRow(context, visible[i], allNos),
                if (i < visible.length - 1)
                  Divider(color: t.line, height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _busRow(BuildContext context, Service bus, List<String> allNos) {
    final t = context.t;
    final eta = fmtEta(bus.etaSec);
    final on =
        AppModel.shared.isTracked(code: widget.stopCode, busNo: bus.no);
    return InkWell(
      onTap: () => widget.onOpenBus(bus.no),
      child: Container(
        decoration: BoxDecoration(
          color: on ? t.liveBg : Colors.transparent,
          // Tracked rows carry a left accent rule + tint — two non-colour-
          // alone cues for the alert state.
          border: on
              ? Border(left: BorderSide(color: t.accent, width: 3))
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(children: [
          ServiceBadge(svc: bus.no, size: ServiceBadgeSize.sm),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bus.dest,
                    style: t.sans(14,
                        weight: FontWeight.w500, color: t.fg)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: t.accent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(bus.load.label.toLowerCase(),
                      style: t.mono(10, color: t.dim)),
                ]),
              ],
            ),
          ),
          Text(eta.big + eta.small,
              style: t.mono(13,
                  weight: FontWeight.w600, color: t.accent)),
          _bell(context, bus.no, allNos),
        ]),
      ),
    );
  }

  Widget _emptyCard(BuildContext context, String message) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(Icons.directions_bus, color: t.dim),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: t.sans(14, color: t.fg)),
        ),
      ]),
    );
  }
}

enum _StopSort { arrival, busNo }
