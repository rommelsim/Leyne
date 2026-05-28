// SoftStopScreen — Leyne 2.0 Stop detail (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';

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
      ),
      floatingActionButton: ListenableBuilder(
        listenable: AppModel.shared,
        builder: (context, _) {
          final isPinned =
              AppModel.shared.pins.any((p) => p.code == widget.stopCode);
          return FloatingActionButton.extended(
            onPressed: () => AppModel.shared.togglePin(widget.stopCode),
            backgroundColor: isPinned ? t.accent : t.surface,
            foregroundColor: isPinned ? t.onAccent : t.fg,
            icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            label: Text(isPinned ? 'Pinned' : 'Pin'),
          );
        },
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: DataStore.shared,
          builder: (context, _) {
            final state = DataStore.shared.arrivals[widget.stopCode];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _header(context),
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
                  _primaryCard(context, state.services.first),
                  const SizedBox(height: 16),
                  _otherBuses(context, state.services.skip(1).toList()),
                ],
              ],
            );
          },
        ),
      ),
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

  Widget _primaryCard(BuildContext context, Service primary) {
    final t = context.t;
    final eta = fmtEta(primary.etaSec);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => widget.onOpenBus(primary.no),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: t.liveBg, borderRadius: BorderRadius.circular(24)),
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
              Icon(Icons.chevron_right, color: t.dim),
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

  Widget _otherBuses(BuildContext context, List<Service> services) {
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
                _busRow(context, visible[i]),
                if (i < visible.length - 1)
                  Divider(color: t.line, height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _busRow(BuildContext context, Service bus) {
    final t = context.t;
    final eta = fmtEta(bus.etaSec);
    return InkWell(
      onTap: () => widget.onOpenBus(bus.no),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
