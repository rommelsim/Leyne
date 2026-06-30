// Detail screens — Stop (bus routes at a stop), Station (MRT directions +
// station info), and Route (bus route timeline with live tracking).

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../theme.dart' show MRTLine;
import 'redesign_bridge.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_data.dart';
import 'redesign_route_timeline.dart';
import 'redesign_theme.dart';

// ============================================================== STOP screen

class RdStopScreen extends StatefulWidget {
  const RdStopScreen({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdStopScreen> createState() => _RdStopScreenState();
}

class _RdStopScreenState extends State<RdStopScreen> {
  @override
  void initState() {
    super.initState();
    final code = widget.c.currentNearby?.stopCode;
    if (code != null) DataStore.shared.ensureArrivals(code);
  }

  String _freshness() {
    final code = widget.c.currentNearby?.stopCode;
    final last = code == null ? null : DataStore.shared.lastRefresh(code);
    if (last == null) return 'Live from LTA';
    final s = DateTime.now().difference(last).inSeconds;
    return s < 60 ? 'Live from LTA · refreshed ${s}s ago' : 'Live from LTA · refreshed ${s ~/ 60}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = RdTheme.of(context);
    final stop = c.currentStop;
    final arrivals = stop.arrivals;
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RdCircleButton(icon: Symbols.arrow_back, bordered: false, iconSize: 24, onTap: c.back),
                RdCircleButton(
                  icon: Symbols.bookmark,
                  iconColor: c.stopSaved ? t.primary : t.onVariant,
                  fill: c.stopSaved ? 1 : 0,
                  iconSize: 21,
                  onTap: c.toggleSaveStop,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(stop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: rdText(size: 28, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.56)),
                    ),
                    RdMrtBadgeRow(stopName: stop.name),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (stop.dist.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(11)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RdIcon(Symbols.directions_walk, size: 16, color: t.onVariant),
                            const SizedBox(width: 5),
                            Text(stop.dist, style: rdText(size: 12.5, weight: FontWeight.w700, color: t.onSurface)),
                          ],
                        ),
                      ),
                    if (stop.code.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(stop.code, style: rdText(size: 12, weight: FontWeight.w600, color: t.onVariant)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: arrivals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RdIcon(Symbols.directions_bus, size: 26, color: t.outline),
                        const SizedBox(height: 6),
                        Text('No live arrivals right now',
                            style: rdText(size: 13, weight: FontWeight.w600, color: t.onVariant)),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    children: [
                      for (final a in arrivals) ...[
                        _StopRouteCard(c: c, a: a),
                        const SizedBox(height: 9),
                      ],
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RdIcon(Symbols.schedule, size: 16, color: t.onVariant),
                            const SizedBox(width: 7),
                            Text(_freshness(),
                                style: rdText(size: 11.5, weight: FontWeight.w500, color: t.onVariant)),
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

class _StopRouteCard extends StatelessWidget {
  const _StopRouteCard({required this.c, required this.a});
  final RedesignController c;
  final RdArrival a;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final occ = rdOcc(a.load, t);
    return GestureDetector(
      onTap: () => c.openBus(a.route, c.currentNearby?.stopCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: t.scLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.outlineVariant),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.route, style: rdText(size: 19, weight: FontWeight.w900, color: t.onSurface)),
                  Text(a.dest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rdText(size: 10, weight: FontWeight.w500, color: t.onVariant)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      RdDot(occ.color, size: 6),
                      const SizedBox(width: 4),
                      Text(occ.label, style: rdText(size: 10, weight: FontWeight.w500, color: t.onVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: a.min, style: rdText(size: 26, weight: FontWeight.w900, color: t.primary, height: 1)),
                  TextSpan(text: ' min', style: rdText(size: 9, weight: FontWeight.w500, color: t.onVariant)),
                ])),
                if (a.then != null) ...[
                  const SizedBox(height: 2),
                  Text(a.then!, style: rdText(size: 10, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ],
            ),
            const SizedBox(width: 14),
            RdIcon(Symbols.chevron_right, size: 20, color: t.outline),
          ],
        ),
      ),
    );
  }
}

// =========================================================== STATION screen

class RdStationScreen extends StatefulWidget {
  const RdStationScreen({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdStationScreen> createState() => _RdStationScreenState();
}

class _RdStationScreenState extends State<RdStationScreen> {
  MrtGeoStation? get _station {
    final name = widget.c.activeStationName;
    if (name == null) return null;
    for (final s in MrtGeo.all) {
      if (s.name == name) return s;
    }
    return null;
  }

  MRTLine? _lineFor(String code) {
    final p = (code.length >= 2 ? code.substring(0, 2) : code).toUpperCase();
    for (final l in MRTLine.values) {
      if (l.code == p) return l;
    }
    return null;
  }

  List<MRTLine> get _lines {
    final s = _station;
    if (s == null) return const [];
    final seen = <MRTLine>{};
    final out = <MRTLine>[];
    for (final code in s.codes) {
      final l = _lineFor(code);
      if (l != null && seen.add(l)) out.add(l);
    }
    return out;
  }

  CrowdLevel? get _crowd {
    final s = _station;
    if (s == null) return null;
    for (final line in _lines) {
      final list = DataStore.shared.crowdByLine[line];
      if (list != null) {
        for (final sc in list) {
          if (s.codes.contains(sc.code)) return sc.level;
        }
      }
    }
    return null;
  }

  TrainAlert? get _disruption {
    for (final a in DataStore.shared.trainAlerts) {
      final l = a.line;
      if (l != null && _lines.contains(l)) return a;
    }
    return null;
  }

  String? get _walkText {
    final s = _station;
    final loc = LocationService.shared.lastLocation;
    if (s == null || loc == null) return null;
    final d = haversine(loc.lat, loc.lon, s.lat, s.lon);
    final walk = (d / 80).round().clamp(1, 999);
    return '$walk min walk · ${fmtDistance(d.round())}';
  }

  @override
  void initState() {
    super.initState();
    DataStore.shared.refreshTrainAlertsIfStale();
    for (final l in _lines) {
      DataStore.shared.refreshCrowd(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = RdTheme.of(context);
    final s = _station;
    final crowd = _crowd;
    final disruption = _disruption;
    final walk = _walkText;
    final bad = disruption != null;
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(children: [
              RdCircleButton(icon: Symbols.arrow_back, iconColor: t.onSurface, iconSize: 23, onTap: c.back),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s?.name ?? 'Station',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: rdText(size: 28, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.56)),
              if (s != null) ...[
                const SizedBox(height: 9),
                Row(children: [
                  for (final code in s.codes.take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: lineColorFor(code), borderRadius: BorderRadius.circular(7)),
                        child: Text(code, style: rdText(size: 11, weight: FontWeight.w800, color: rdMrtBadgeFg(code))),
                      ),
                    ),
                ]),
              ],
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 9),
                Row(children: [
                  RdDot(_lines.first.color, size: 9),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(_lines.map((l) => '${l.displayName} Line').join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rdText(size: 12.5, weight: FontWeight.w600, color: t.onVariant)),
                  ),
                ]),
              ],
              const SizedBox(height: 11),
              Row(children: [
                if (walk != null) _chip(t, icon: Symbols.directions_walk, text: walk, bg: t.scHigh, fg: t.onSurface),
                if (walk != null && crowd != null) const SizedBox(width: 8),
                if (crowd != null) _crowdChip(t, crowd),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                GestureDetector(
                  onTap: c.toLines,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: bad ? t.mrtContainer : t.busContainer, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      RdIcon(bad ? Symbols.warning : Symbols.check_circle, size: 19, color: bad ? t.mrt : t.bus, fill: 1),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(disruption?.title ?? 'All your lines running normally',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rdText(size: 12.5, weight: FontWeight.w800, color: bad ? t.onMrtContainer : t.onBusContainer)),
                          Text(disruption?.detail ?? 'Tap to see the full network status',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: rdText(size: 11, weight: FontWeight.w500, color: bad ? t.onMrtContainer : t.onBusContainer)),
                        ]),
                      ),
                      RdIcon(Symbols.chevron_right, size: 18, color: bad ? t.onMrtContainer : t.onBusContainer),
                    ]),
                  ),
                ),
                const SizedBox(height: 11),
                GestureDetector(
                  onTap: () => c.go('switch'),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.scLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.outlineVariant),
                    ),
                    child: Row(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: t.primaryContainer, borderRadius: BorderRadius.circular(11)),
                          alignment: Alignment.center,
                          child: RdIcon(Symbols.directions_bus, size: 20, color: t.onPrimaryContainer, fill: 1)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('GETTING THERE',
                              style: rdText(size: 9, weight: FontWeight.w800, color: t.onVariant, letterSpacing: 0.54)),
                          Text('Buses & stops nearby', style: rdText(size: 13.5, weight: FontWeight.w800, color: t.onSurface)),
                        ]),
                      ),
                      RdIcon(Symbols.chevron_right, size: 18, color: t.outline),
                    ]),
                  ),
                ),
                const SizedBox(height: 11),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RdIcon(Symbols.info, size: 15, color: t.onVariant),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text("Live train arrival times aren't published by LTA — showing crowd & line status.",
                          style: rdText(size: 11.5, weight: FontWeight.w500, color: t.onVariant)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(RdTokens t, {required IconData icon, required String text, required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RdIcon(icon, size: 16, color: t.onVariant),
          const SizedBox(width: 5),
          Text(text, style: rdText(size: 12.5, weight: FontWeight.w700, color: fg)),
        ]),
      );

  Widget _crowdChip(RdTokens t, CrowdLevel level) {
    final (String label, Color dot, Color bg, Color fg) = switch (level) {
      CrowdLevel.low => ('Not crowded', t.bus, t.busContainer, t.onBusContainer),
      CrowdLevel.moderate => ('Some crowd', t.amber, t.amberContainer, t.onAmberContainer),
      CrowdLevel.high => ('Crowded', t.mrt, t.mrtContainer, t.onMrtContainer),
      CrowdLevel.unknown => ('Crowd —', t.outline, t.scHigh, t.onVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        RdDot(dot, size: 8),
        const SizedBox(width: 5),
        Text(label, style: rdText(size: 12.5, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ============================================================= ROUTE screen

class RdRouteScreen extends StatefulWidget {
  const RdRouteScreen({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdRouteScreen> createState() => _RdRouteScreenState();
}

class _RdRouteScreenState extends State<RdRouteScreen> {
  RouteInfo? _route;

  String get _svc => widget.c.activeService ?? '';
  String? get _stopCode => widget.c.activeRouteStop;

  /// The live arrival for this bus at the anchor stop — drives the ETA and the
  /// amenity row (load / deck / wheelchair) from real LTA data.
  Service? get _liveService {
    final code = _stopCode;
    if (code == null) return null;
    for (final s in DataStore.shared.servicesFor(code)) {
      if (s.no == _svc) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final code = _stopCode;
    if (code != null) {
      DataStore.shared.ensureArrivals(code);
      DataStore.shared.route(serviceNo: _svc, stopCode: code).then((r) {
        if (mounted) setState(() => _route = r);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = RdTheme.of(context);
    final live = _liveService;
    final dest = (_route != null && _route!.stops.isNotEmpty) ? _route!.stops.last.name : (live?.dest ?? '');
    final occ = live != null ? rdOcc(rdLoad(live.load), t) : null;
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RdCircleButton(icon: Symbols.arrow_back, iconSize: 23, onTap: c.back),
                    RdCircleButton(
                      icon: Symbols.bookmark,
                      iconColor: c.routeSaved ? t.primary : t.onVariant,
                      fill: c.routeSaved ? 1 : 0,
                      iconSize: 22,
                      onTap: c.saveRoute,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(11, 5, 14, 5),
                  decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RdIcon(Symbols.directions_bus, size: 18, color: t.onPrimary, fill: 1),
                      const SizedBox(width: 7),
                      Text(_svc, style: rdText(size: 23, weight: FontWeight.w900, color: t.onPrimary, letterSpacing: -0.46)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dest.isEmpty ? 'Route' : dest,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rdText(size: 27, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.68)),
                          if (_stopCode != null) ...[
                            const SizedBox(height: 3),
                            Text('From ${DataStore.shared.stopName(_stopCode!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: rdText(size: 14, weight: FontWeight.w500, color: t.onVariant)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: live != null ? rdMinLabel(live.etaSec) : '—',
                              style: rdText(size: 40, weight: FontWeight.w900, color: t.primary, height: 0.85, letterSpacing: -1.6)),
                          TextSpan(text: ' min', style: rdText(size: 15, weight: FontWeight.w700, color: t.primary)),
                        ])),
                        const SizedBox(height: 6),
                        Text('to your stop', style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
                      ],
                    ),
                  ],
                ),
                if (live != null && occ != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 16),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _Amenity(icon: occ.icon, label: occ.label, color: occ.color),
                        _Amenity(icon: Symbols.directions_bus, label: live.deck.word, color: t.primary),
                        if (live.wab) _Amenity(icon: Symbols.accessible, label: 'Wheelchair accessible', color: t.primary),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 16),
              ],
            ),
          ),
          Container(height: 1, color: t.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 18)),
          // Timeline.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 16),
                  child: Text('Route', style: rdText(size: 18, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.18)),
                ),
                if (_route != null)
                  RdRouteTimeline(c: c, route: _route!)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 34),
                    child: Center(
                      child: Text('Loading route…',
                          style: rdText(size: 13, weight: FontWeight.w500, color: t.onVariant)),
                    ),
                  ),
              ],
            ),
          ),
          // Notify button.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Center(
                child: GestureDetector(
                  onTap: c.trackFromRoute,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 44),
                    decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RdIcon(Symbols.notifications_active, size: 21, color: t.onPrimary, fill: 1),
                        const SizedBox(width: 9),
                        Text('Notify me', style: rdText(size: 15, weight: FontWeight.w700, color: t.onPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Amenity extends StatelessWidget {
  const _Amenity({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RdIcon(icon, size: 19, color: color, fill: 1),
        const SizedBox(width: 6),
        Text(label, style: rdText(size: 12.5, weight: FontWeight.w600, color: t.onSurface)),
      ],
    );
  }
}
