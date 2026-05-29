// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Vertical list of pinned-stop cards. Each card shows the stop name and a
// compact rundown of its live services so the user can clock multiple
// buses at the same stop at a glance.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
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
  /// Line codes the user has tapped to dismiss this session. Cleared
  /// when the app cold-starts so a new disruption surfaces again.
  final Set<String> _dismissedAlerts = {};

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
          SoftBottomBar(selection: SoftTab.home, onSelect: widget.onTab),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            AppModel.shared,
            DataStore.shared,
            LocationService.shared,
          ]),
          builder: (context, _) {
            final pins = AppModel.shared.pins;
            return RefreshIndicator(
              color: context.t.accent,
              onRefresh: () => Future.wait(
                pins.map((p) => DataStore.shared.refreshArrivals(p.code)),
              ),
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                      walkMinutes: _walkMinutes(pin.code),
                      onTap: () => widget.onOpenStop(pin.code),
                    ),
                    const SizedBox(height: 12),
                  ],
                ..._mrtAlertCards(context),
              ],
            ),
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

  List<Widget> _mrtAlertCards(BuildContext context) {
    final visible = DataStore.shared.trainAlerts
        .where((a) => !_dismissedAlerts.contains(a.id))
        .toList();
    if (visible.isEmpty) return const [];
    final out = <Widget>[const SizedBox(height: 4)];
    for (var i = 0; i < visible.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 10));
      out.add(_mrtAlertCard(context, visible[i]));
    }
    return out;
  }

  Widget _mrtAlertCard(BuildContext context, TrainAlert alert) {
    final t = context.t;
    final color = alert.line?.color ?? t.dim;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _dismissedAlerts.add(alert.id)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MRTLineBar(color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title,
                      style: t.sans(13,
                          weight: FontWeight.w600, color: t.fg)),
                  const SizedBox(height: 2),
                  Text(alert.detail,
                      style: t.sans(12, color: t.dim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
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

  /// Walk-time minutes from the user's last known location to the stop.
  /// 80 m/min ≈ 5 km/h to match the iOS heuristic. Nil when location
  /// hasn't been fixed yet — the chip is hidden in that case.
  int? _walkMinutes(String code) {
    final here = LocationService.shared.lastLocation;
    final stop = DataStore.shared.stopByCode[code];
    if (here == null || stop == null) return null;
    final d = _haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    return math.max(1, (d / 80).round());
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double v) => v * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }
}

/// Pinned-stop card matching the Soft 2.0 prototype: pin-chip + stop-name
/// + walk-time header row, up to 3 services sorted by next arrival with
/// right-aligned ETA ("now" in accent, otherwise mono), an overflow
/// "+N more arrivals →" link, and a quiet state when no live arrivals.
class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.pin,
    required this.services,
    required this.walkMinutes,
    required this.onTap,
  });

  static const int _maxVisible = 3;

  final Pin pin;
  final List<Service> services;
  final int? walkMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sorted = [...services]..sort((a, b) => a.etaSec.compareTo(b.etaSec));
    final visible = sorted.take(_maxVisible).toList();
    final overflow = math.max(0, sorted.length - _maxVisible);
    final dsName = DataStore.shared.stopName(pin.code);
    final stopName = dsName.isEmpty ? pin.code : dsName;
    final nick = pin.nickname.trim();
    // Empty when there's no real nickname — the card then shows no chip
    // rather than a redundant "PIN" label. Matches iOS SoftPinCard.
    final chip = (nick.isEmpty ||
            nick.toLowerCase() == stopName.toLowerCase())
        ? ''
        : nick.toUpperCase();

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
              _header(context, chip: chip, stopName: stopName),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                _quietRow(context)
              else ...[
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _serviceRow(context, visible[i]),
                ],
                if (overflow > 0) ...[
                  const SizedBox(height: 10),
                  Text('+$overflow more arrivals →',
                      style: t.sans(12,
                          weight: FontWeight.w500, color: t.dim)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context,
      {required String chip, required String stopName}) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (chip.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.liveBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(chip,
                style: t.mono(10, weight: FontWeight.w600, color: t.accent)
                    .copyWith(letterSpacing: 0.8)),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(stopName,
              style: t.sans(17, weight: FontWeight.w600, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (walkMinutes != null) ...[
          const SizedBox(width: 8),
          _walkChip(context, walkMinutes!),
        ],
      ],
    );
  }

  Widget _walkChip(BuildContext context, int minutes) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.liveBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 12, color: t.dim),
          const SizedBox(width: 4),
          Text('$minutes m',
              style: t.mono(11, weight: FontWeight.w600, color: t.dim)),
        ],
      ),
    );
  }

  Widget _serviceRow(BuildContext context, Service s) {
    final t = context.t;
    final eta = fmtEta(s.etaSec);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ServiceBadge(svc: s.no, size: ServiceBadgeSize.sm),
        const SizedBox(width: 10),
        Expanded(
          child: Text('→ ${s.dest}',
              style: t.sans(13, color: t.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (eta.live)
          Text('now',
              style: t.sans(13, weight: FontWeight.w600, color: t.accent))
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(eta.big,
                  style: t.mono(13, weight: FontWeight.w600, color: t.fg)),
              const SizedBox(width: 2),
              Text(eta.small, style: t.mono(11, color: t.dim)),
            ],
          ),
      ],
    );
  }

  Widget _quietRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: t.dim.withValues(alpha: 0.6),
                shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('Quiet · no live arrivals',
            style: t.sans(13, color: t.dim)),
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
