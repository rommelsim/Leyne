// Home — the departures-first main view. A white header (nearest stop + crowd
// chip) over a scrolling sheet: a transfer-to-MRT card, then the live-arrivals
// list with a Time / Bus-number sort and an expandable "see all".

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import 'redesign_bridge.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_data.dart';
import 'redesign_theme.dart';

class RdHomeScreen extends StatefulWidget {
  const RdHomeScreen({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdHomeScreen> createState() => _RdHomeScreenState();
}

class _RdHomeScreenState extends State<RdHomeScreen> {
  Timer? _pump;

  @override
  void initState() {
    super.initState();
    LocationService.shared.startIfAuthorized();
    DataStore.shared.prefetchNearbyArrivals();
    // Keep nearby arrivals warm (the freshness gate inside ensureArrivals
    // prevents over-fetching against LTA's rate limit).
    _pump = Timer.periodic(const Duration(seconds: 12), (_) {
      DataStore.shared.prefetchNearbyArrivals();
      final code = widget.c.currentNearby?.stopCode;
      if (code != null) DataStore.shared.ensureArrivals(code);
    });
  }

  @override
  void dispose() {
    _pump?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(c: widget.c),
          Expanded(child: _Sheet(c: widget.c)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final stop = c.currentStop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => c.go('switch'),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            RdIcon(Symbols.near_me, size: 15, color: t.primary, fill: 1),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                  stop.distShort.isEmpty ? 'Nearest stop' : 'Nearest stop · ${stop.distShort}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: rdText(size: 12, weight: FontWeight.w600, color: t.onVariant)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(stop.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: rdText(
                                      size: 28, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.7)),
                            ),
                            RdMrtBadgeRow(stopName: stop.name),
                            RdIcon(Symbols.chevron_right, size: 24, color: t.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Listener(
                      onPointerDown: (_) => c.saveDown(),
                      onPointerUp: (_) => c.saveUp(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: t.outlineVariant),
                        ),
                        alignment: Alignment.center,
                        child: RdIcon(
                          c.stopSaved ? Symbols.bookmark : Symbols.bookmark_border,
                          size: 21,
                          color: c.stopSaved ? t.primary : t.onVariant,
                          fill: c.stopSaved ? 1 : 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    RdCircleButton(
                      icon: Symbols.account_circle,
                      iconColor: t.onVariant,
                      onTap: () => c.go('settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: t.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RdIcon(Symbols.signpost, size: 16, color: t.onVariant, fill: 1),
                      const SizedBox(width: 7),
                      Text(stop.code.isEmpty ? stop.dist : 'Stop ${stop.code}',
                          style: rdText(size: 12.5, weight: FontWeight.w700, color: t.onSurface)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final arrivals = c.visibleArrivals;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      physics: const ClampingScrollPhysics(),
      children: [
        // Transfer-to-MRT card (order:-1 in the design → top of the sheet).
        _TransferCard(c: c),
        // LIVE ARRIVALS header.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LIVE ARRIVALS',
                  style: rdText(size: 11, weight: FontWeight.w800, color: t.onVariant, letterSpacing: 0.66)),
              Row(
                children: [
                  RdDot(t.bus),
                  const SizedBox(width: 6),
                  Text(_freshnessLabel(c), style: rdText(size: 11, weight: FontWeight.w600, color: t.onVariant)),
                ],
              ),
            ],
          ),
        ),
        // Sort toggle.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SortTab(label: 'Time', active: c.sortBy == 'eta', onTap: () => c.setSort('eta')),
                  _SortTab(label: 'Bus number', active: c.sortBy == 'number', onTap: () => c.setSort('number')),
                ],
              ),
            ),
          ),
        ),
        // Arrivals.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Column(
            children: [
              for (var i = 0; i < arrivals.length; i++)
                _ArrivalRow(c: c, a: arrivals[i], highlighted: i == 0),
              if (c.canExpandArrivals)
                GestureDetector(
                  onTap: c.toggleArrivals,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(c.arrivalsExpanded ? 'Show fewer arrivals' : 'See all arrivals',
                            style: rdText(size: 12.5, weight: FontWeight.w700, color: t.primary)),
                        const SizedBox(width: 5),
                        RdIcon(c.arrivalsExpanded ? Symbols.expand_less : Symbols.expand_more,
                            size: 18, color: t.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SortTab extends StatelessWidget {
  const _SortTab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? t.primary : const Color(0x00000000),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label,
            style: rdText(size: 13, weight: FontWeight.w700, color: active ? t.onPrimary : t.onVariant)),
      ),
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.c, required this.a, required this.highlighted});
  final RedesignController c;
  final RdArrival a;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final hi = highlighted;
    final occ = rdOcc(a.load, t);
    return GestureDetector(
      onTap: () => c.openBus(a.route, c.currentNearby?.stopCode),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hi ? t.primaryContainer : t.scLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: hi ? t.primary : t.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 50),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hi ? t.primary : t.scHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(a.route,
                  style: rdText(size: 19, weight: FontWeight.w800, color: hi ? t.onPrimary : t.onSurface)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.dest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rdText(
                          size: 16,
                          weight: FontWeight.w800,
                          color: hi ? t.onPrimaryContainer : t.onSurface,
                          letterSpacing: -0.16)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      RdIcon(occ.icon, size: 16, color: occ.color, fill: 1),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(occ.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rdText(size: 11.5, weight: FontWeight.w600, color: occ.color)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: a.min,
                        style: rdText(
                            size: 22,
                            weight: FontWeight.w900,
                            color: hi ? t.primary : t.onSurface,
                            height: 0.9,
                            letterSpacing: -0.44)),
                    TextSpan(text: ' min', style: rdText(size: 11, weight: FontWeight.w700, color: t.onVariant)),
                  ]),
                ),
                if (a.then != null) ...[
                  const SizedBox(height: 3),
                  Text(a.then!, style: rdText(size: 10.5, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ],
            ),
            const SizedBox(width: 6),
            RdIcon(Symbols.chevron_right, size: 20, color: hi ? t.primary : t.outline),
          ],
        ),
      ),
    );
  }
}

String _freshnessLabel(RedesignController c) {
  final code = c.currentNearby?.stopCode;
  final last = code == null ? null : DataStore.shared.lastRefresh(code);
  if (last == null) return 'Updating…';
  final s = DateTime.now().difference(last).inSeconds;
  if (s < 5) return 'Updated just now';
  if (s < 60) return 'Updated ${s}s ago';
  return 'Updated ${s ~/ 60}m ago';
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final nm = c.nearestMrt;
    if (nm == null) return const SizedBox.shrink();
    final st = nm.station;
    return GestureDetector(
      onTap: () => c.openStationNamed(st.name),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: t.transferOrange, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: RdIcon(Symbols.directions_subway, size: 23, color: t.transferOnOrange, fill: 1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEAREST MRT',
                      style: rdText(size: 9, weight: FontWeight.w700, color: t.onVariant, letterSpacing: 0.63)),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Flexible(
                        child: Text(st.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rdText(size: 16, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.16)),
                      ),
                      for (final code in st.codes.take(2)) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: lineColorFor(code), borderRadius: BorderRadius.circular(6)),
                          child: Text(code,
                              style: rdText(size: 9.5, weight: FontWeight.w800, color: rdMrtBadgeFg(code))),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${nm.walkMin} min walk · ${fmtDistance(nm.distanceM)}',
                      style: rdText(size: 11.5, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: t.surface, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: RdIcon(Symbols.directions_walk, size: 19, color: t.primary, fill: 1),
            ),
            const SizedBox(width: 4),
            RdIcon(Symbols.chevron_right, size: 20, color: t.outline),
          ],
        ),
      ),
    );
  }
}

/// Bottom Nearby / Saved navigation bar (top-level screens only).
class RdBottomNav extends StatelessWidget {
  const RdBottomNav({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final onMap = c.screen == 'map';
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 7, 0, 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                label: 'Nearby',
                icon: Symbols.near_me,
                fill: 1,
                active: onMap,
                onTap: c.toMap,
              ),
              _NavItem(
                label: 'Saved',
                icon: Symbols.bookmark,
                fill: 0,
                active: false,
                onTap: () => c.go('saved'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.fill,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final double fill;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? t.primaryContainer : const Color(0x00000000),
              borderRadius: BorderRadius.circular(999),
            ),
            child: RdIcon(icon,
                size: active ? 20 : 21,
                color: active ? t.onPrimaryContainer : t.onVariant,
                fill: fill),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: rdText(
                  size: 9.5,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? t.onSurface : t.onVariant)),
        ],
      ),
    );
  }
}
