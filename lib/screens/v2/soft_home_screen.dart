// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftHomeScreen extends StatefulWidget {
  const SoftHomeScreen(
      {super.key,
      required this.onTab,
      required this.onOpenStop,
      required this.onOpenSearch});
  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;
  final VoidCallback onOpenSearch;

  @override
  State<SoftHomeScreen> createState() => _SoftHomeScreenState();
}

class _SoftHomeScreenState extends State<SoftHomeScreen> {
  bool _showMrtAlert = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warm());
  }

  void _warm() {
    for (final pin in AppModel.shared.pins) {
      DataStore.shared.ensureArrivals(pin.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar:
          SoftTabBar(selection: SoftTab.home, onSelect: widget.onTab),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) {
            final pins = AppModel.shared.pins;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _header(context),
                const SizedBox(height: 16),
                if (pins.isEmpty)
                  _EmptyState(
                    onNearby: () => widget.onTab(SoftTab.nearby),
                    onSearch: widget.onOpenSearch,
                  )
                else ...[
                  _PrimaryPinCard(
                    pin: pins.first,
                    services: _liveServices(pins.first.code),
                    onTap: () => widget.onOpenStop(pins.first.code),
                  ),
                  if (pins.length > 1) ...[
                    const SizedBox(height: 16),
                    Text('Also pinned',
                        style: t.sans(13,
                            weight: FontWeight.w600, color: t.dim)),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.2,
                      children: [
                        for (final pin in pins.skip(1))
                          _SecondaryPinCard(
                            pin: pin,
                            first: _liveServices(pin.code).firstOrNull,
                            onTap: () => widget.onOpenStop(pin.code),
                          ),
                      ],
                    ),
                  ],
                ],
                if (_showMrtAlert) ...[
                  const SizedBox(height: 16),
                  _mrtAlert(context),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(_greeting()),
              const SizedBox(height: 2),
              Text('Your stops',
                  style: t.sans(28, weight: FontWeight.w400, color: t.fg)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: widget.onOpenSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }

  Widget _mrtAlert(BuildContext context) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _showMrtAlert = false),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MRTLineBar(color: MRTLine.ne.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NE Line · short delays',
                      style: t.sans(13,
                          weight: FontWeight.w600, color: t.fg)),
                  const SizedBox(height: 2),
                  Text('Outram Pk ↔ HarbourFront · tap to dismiss',
                      style: t.sans(12, color: t.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Service> _liveServices(String code) {
    final a = DataStore.shared.arrivals[code];
    if (a == null || a.kind != ArrivalStateKind.loaded) return const [];
    return a.services;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }
}

class _PrimaryPinCard extends StatelessWidget {
  const _PrimaryPinCard(
      {required this.pin, required this.services, required this.onTap});
  final Pin pin;
  final List<Service> services;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final primary = services.firstOrNull;
    final next = services.skip(1).firstOrNull;
    final eta = primary == null ? null : fmtEta(primary.etaSec);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelPill(text: pin.nickname.isEmpty ? 'Pinned' : pin.nickname),
            const SizedBox(height: 12),
            Text(_stopName(pin),
                style: t.sans(20, weight: FontWeight.w600, color: t.fg)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: t.bg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  ServiceBadge(
                      svc: primary?.no ?? '—', size: ServiceBadgeSize.md),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            eta == null
                                ? 'Loading…'
                                : eta.live
                                    ? 'Arriving now'
                                    : 'In ${eta.big} ${eta.small}',
                            style: t.sans(15,
                                weight: FontWeight.w600, color: t.fg)),
                        if (primary != null)
                          Text('→ ${primary.dest}',
                              style: t.sans(11, color: t.dim)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: t.dim, size: 18),
                ],
              ),
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              Text(
                'Then ${next.no} ${fmtEta(next.etaSec).big}${fmtEta(next.etaSec).small}',
                style: t.mono(12, color: t.dim),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stopName(Pin pin) {
    final nick = pin.nickname.trim();
    if (nick.isNotEmpty) return nick;
    final n = DataStore.shared.stopName(pin.code);
    return n.isEmpty ? pin.code : n;
  }
}

class _SecondaryPinCard extends StatelessWidget {
  const _SecondaryPinCard(
      {required this.pin, required this.first, required this.onTap});
  final Pin pin;
  final Service? first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelPill(
                text: pin.nickname.isEmpty ? 'Pin' : pin.nickname,
                variant: LabelPillVariant.tinted),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                pin.nickname.isEmpty
                    ? DataStore.shared.stopName(pin.code)
                    : pin.nickname,
                style: t.sans(13, weight: FontWeight.w600, color: t.fg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (first != null)
              Row(
                children: [
                  Text(first!.no,
                      style:
                          t.mono(11, weight: FontWeight.w600, color: t.fg)),
                  const SizedBox(width: 4),
                  Text(
                      '${fmtEta(first!.etaSec).big}${fmtEta(first!.etaSec).small}',
                      style: t.mono(11, color: t.dim)),
                ],
              )
            else
              Text('—', style: t.mono(11, color: t.faint)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNearby, required this.onSearch});
  final VoidCallback onNearby;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: t.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.liveBg, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.push_pin_outlined, size: 28, color: t.accent),
          ),
          const SizedBox(height: 12),
          Text('No stops pinned',
              style: t.sans(20, weight: FontWeight.w600, color: t.fg)),
          const SizedBox(height: 4),
          Text('Pin a bus stop to see live arrivals at a glance.',
              style: t.sans(13, color: t.dim)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onNearby,
            style: FilledButton.styleFrom(
                backgroundColor: t.accent, foregroundColor: t.onAccent),
            child: const Text('Find nearby'),
          ),
        ],
      ),
    );
  }
}
