// SoftNearbyScreen — Leyne 2.0 Nearby (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

enum SoftNearbySort { distance, arrival, service }

class SoftNearbyScreen extends StatefulWidget {
  const SoftNearbyScreen(
      {super.key, required this.onTab, required this.onOpenStop});
  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;

  @override
  State<SoftNearbyScreen> createState() => _SoftNearbyScreenState();
}

class _SoftNearbyScreenState extends State<SoftNearbyScreen> {
  SoftNearbySort _sort = SoftNearbySort.distance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await LocationService.shared.startIfAuthorized();
      final loc = LocationService.shared.lastLocation;
      if (loc != null) {
        DataStore.shared.updateNearby(loc.lat, loc.lon);
      }
      DataStore.shared.prefetchNearbyArrivals();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar:
          SoftBottomBar(selection: SoftTab.nearby, onSelect: widget.onTab),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [DataStore.shared, LocationService.shared]),
          builder: (context, _) {
            final sorted = _sorted();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Eyebrow('Stops within 500m'),
                const SizedBox(height: 2),
                Text('Near you',
                    style: t.sans(28, weight: FontWeight.w400, color: t.fg)),
                const SizedBox(height: 16),
                SortChipRow<SoftNearbySort>(
                  selection: _sort,
                  options: const [
                    (value: SoftNearbySort.distance, label: 'Distance'),
                    (value: SoftNearbySort.arrival, label: 'Arrival'),
                    (value: SoftNearbySort.service, label: 'Service'),
                  ],
                  onSelect: (v) => setState(() => _sort = v),
                ),
                const SizedBox(height: 16),
                if (sorted.isEmpty)
                  Text(_emptyMessage(),
                      style: t.sans(13, color: t.dim))
                else
                  for (final s in sorted.take(20)) ...[
                    _row(context, s),
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<NearbyStop> _sorted() {
    final list = List<NearbyStop>.of(DataStore.shared.nearby);
    switch (_sort) {
      case SoftNearbySort.distance:
        return list;
      case SoftNearbySort.arrival:
        list.sort((a, b) => _soonest(a).compareTo(_soonest(b)));
        return list;
      case SoftNearbySort.service:
        list.sort((a, b) => b.services.length.compareTo(a.services.length));
        return list;
    }
  }

  int _soonest(NearbyStop s) {
    final a = DataStore.shared.arrivals[s.stopCode];
    if (a == null || a.kind != ArrivalStateKind.loaded) return 1 << 30;
    return a.services
        .map((x) => x.etaSec)
        .fold(1 << 30, (m, e) => e < m ? e : m);
  }

  String _emptyMessage() {
    switch (LocationService.shared.auth) {
      case LocAuth.denied:
      case LocAuth.deniedForever:
        return 'Location is off. Enable in Settings to see nearby stops.';
      case LocAuth.notDetermined:
        return 'Allow location access to find stops near you.';
      case LocAuth.authorized:
        return 'Looking for nearby stops…';
    }
  }

  Widget _row(BuildContext context, NearbyStop stop) {
    final t = context.t;
    final live = DataStore.shared.arrivals[stop.stopCode];
    final first = (live != null && live.kind == ArrivalStateKind.loaded)
        ? live.services.firstOrNull
        : null;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.onOpenStop(stop.stopCode),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              WalkTile(minutes: stop.walkMin),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.stopName,
                        style: t.sans(15,
                            weight: FontWeight.w600, color: t.fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(
                          '${fmtDistance(stop.distanceM)} · ${stop.stopCode}',
                          style: t.mono(11, color: t.dim)),
                      if (first != null) ...[
                        Text(' · ', style: t.mono(11, color: t.faint)),
                        Text(
                            '${first.no} ${fmtEta(first.etaSec).big}${fmtEta(first.etaSec).small}',
                            style: t.mono(11,
                                weight: FontWeight.w600, color: t.accent)),
                      ],
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.dim, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
