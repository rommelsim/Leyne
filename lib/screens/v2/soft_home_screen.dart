// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Vertical list of pinned-stop cards. Each card shows the stop name and a
// compact rundown of its live services so the user can clock multiple
// buses at the same stop at a glance.

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
                else
                  for (final pin in pins) ...[
                    _PinCard(
                      pin: pin,
                      services: _filteredServices(pin),
                      onTap: () => widget.onOpenStop(pin.code),
                    ),
                    const SizedBox(height: 12),
                  ],
                if (_showMrtAlert) ...[
                  const SizedBox(height: 4),
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

  List<Service> _filteredServices(Pin pin) {
    final all = _liveServices(pin.code);
    final tracked = pin.tracked;
    if (tracked != null && tracked.isNotEmpty) {
      return all.where((s) => tracked.contains(s.no)).toList();
    }
    return all;
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

/// Unified pinned-stop card: stop name + compact list of live services.
/// Replaces the earlier primary/secondary split so multiple buses at the
/// same stop stack legibly underneath the name.
class _PinCard extends StatelessWidget {
  const _PinCard(
      {required this.pin, required this.services, required this.onTap});
  final Pin pin;
  final List<Service> services;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final visible = services.take(4).toList();
    final dsName = DataStore.shared.stopName(pin.code);
    final stopName = dsName.isEmpty ? pin.code : dsName;
    final nickname = pin.nickname.trim();
    final showEyebrow = nickname.isNotEmpty &&
        nickname.toLowerCase() != stopName.toLowerCase();

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showEyebrow) ...[
                          Eyebrow(nickname),
                          const SizedBox(height: 2),
                        ],
                        Text(stopName,
                            style: t.sans(18,
                                weight: FontWeight.w600, color: t.fg)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: t.dim, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: t.line),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      services.isEmpty ? 'No live arrivals' : '—',
                      style: t.sans(13, color: t.faint)),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _serviceRow(context, visible[i]),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceRow(BuildContext context, Service s) {
    final t = context.t;
    final eta = fmtEta(s.etaSec);
    return Row(
      children: [
        ServiceBadge(svc: s.no, size: ServiceBadgeSize.sm),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eta.live)
                Text('Arriving now',
                    style: t.sans(14,
                        weight: FontWeight.w600, color: t.accent))
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(eta.big,
                        style: t.mono(14,
                            weight: FontWeight.w600, color: t.fg)),
                    const SizedBox(width: 2),
                    Text(eta.small, style: t.mono(12, color: t.dim)),
                  ],
                ),
              Text('→ ${s.dest}',
                  style: t.sans(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
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
          Row(
            children: [
              FilledButton(
                onPressed: onNearby,
                style: FilledButton.styleFrom(
                    backgroundColor: t.accent, foregroundColor: t.onAccent),
                child: const Text('Nearby'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSearch,
                child: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
