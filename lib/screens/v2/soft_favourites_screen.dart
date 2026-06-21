// SoftFavouritesScreen — Leyne 2.4.0 "Saved" tab (Material 3 Android).
//
// DESIGN (2.4.0 restyle — mirrors SoftFavouritesView.swift):
//   • Large bold title "Saved" (matches bottom-tab label).
//   • Three-segment filter: All | Stops | Buses.
//       All   = pinned stops first (section "Saved stops"), then saved bus
//               services (section "Buses").
//       Stops = only AppModel.shared.pins.
//       Buses = only AppModel.shared.favServices.
//   • Stop cards: 46×46 pin tile with gold star, stop name,
//     "Stop {code} · road" (mono), walk/distance, mini-chip bus row.
//   • Swipe gestures (Dismissible) — endToStart only (LEFT swipe = delete):
//       Pinned stop    → swipe LEFT → unpin via togglePin; confirmDismiss
//                        returns false so Dismissible never removes the widget.
//       Saved service  → swipe LEFT → removeFavService; same false return.
//   • Empty state: when pins AND favServices are both empty.
//   • "+ Add stop" row at the bottom, always visible (outside empty state).
//   • SoftTab.favourites is used internally (bottom bar label is "Saved"
//     via SoftBottomBar — no change needed here).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
import '../../widgets/v2/soft_tab_bar.dart';

// ─── Segment enum ─────────────────────────────────────────────────────────────

enum _Segment { all, stops, buses, mrt }

// ─── Distance helpers ─────────────────────────────────────────────────────────

int _walkMinFromLocation(String code) {
  final here = LocationService.shared.lastLocation;
  if (here == null) return 0;
  final stop = DataStore.shared.stopByCode[code];
  if (stop == null) return 0;
  final d = haversine(here.lat, here.lon, stop.latitude, stop.longitude);
  final m = walkMinutesFor(d);
  return m < 1 ? 1 : m;
}

int _distanceMFromLocation(String code) {
  final here = LocationService.shared.lastLocation;
  if (here == null) return 0;
  final stop = DataStore.shared.stopByCode[code];
  if (stop == null) return 0;
  return haversine(here.lat, here.lon, stop.latitude, stop.longitude).round();
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SoftFavouritesScreen extends StatefulWidget {
  const SoftFavouritesScreen({
    super.key,
    required this.onTab,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onOpenStation,
    required this.onOpenSearch,
  });

  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;
  final void Function(String stopCode, String svc) onOpenBus;
  final void Function(MrtGeoStation station) onOpenStation;
  final VoidCallback onOpenSearch;

  @override
  State<SoftFavouritesScreen> createState() => _SoftFavouritesScreenState();
}

class _SoftFavouritesScreenState extends State<SoftFavouritesScreen> {
  _Segment _segment = _Segment.all;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmArrivals());
  }

  void _warmArrivals() {
    for (final pin in AppModel.shared.pins) {
      DataStore.shared.ensureArrivals(pin.code);
    }
    for (final fav in AppModel.shared.favServices) {
      if (fav.stop != null) {
        DataStore.shared.ensureArrivals(fav.stop!);
      }
    }
  }

  Future<void> _refreshAll() async {
    final futures = <Future<void>>[];
    for (final pin in AppModel.shared.pins) {
      futures.add(DataStore.shared.refreshArrivals(pin.code));
    }
    for (final fav in AppModel.shared.favServices) {
      if (fav.stop != null) {
        futures.add(DataStore.shared.refreshArrivals(fav.stop!));
      }
    }
    await Future.wait(futures);
  }

  // ── Derived lists ───────────────────────────────────────────────────────

  List<Pin> get _visiblePins {
    switch (_segment) {
      case _Segment.all:
      case _Segment.stops:
        return AppModel.shared.pins;
      case _Segment.buses:
      case _Segment.mrt:
        return const [];
    }
  }

  List<FavService> get _visibleServices {
    switch (_segment) {
      case _Segment.all:
      case _Segment.buses:
        return AppModel.shared.favServices;
      case _Segment.stops:
      case _Segment.mrt:
        return const [];
    }
  }

  List<MrtGeoStation> get _visibleStations {
    switch (_segment) {
      case _Segment.all:
      case _Segment.mrt:
        return AppModel.shared.savedMrtStations;
      case _Segment.stops:
      case _Segment.buses:
        return const [];
    }
  }

  bool get _isEmpty =>
      AppModel.shared.pins.isEmpty &&
      AppModel.shared.favServices.isEmpty &&
      AppModel.shared.savedMrtStations.isEmpty;

  // ── Arrival resolution for services section ─────────────────────────────

  _Resolved? _atStopArrival(FavService fav) {
    final code = fav.stop!;
    final svc = DataStore.shared
        .servicesFor(code)
        .cast<Service?>()
        .firstWhere((s) => s!.no == fav.no, orElse: () => null);
    if (svc == null) return null;
    return _Resolved(
      svc: svc,
      stopName: DataStore.shared.stopName(code),
      stopCode: code,
    );
  }

  _Resolved? _resolve(FavService fav) =>
      fav.isAnywhere ? null : _atStopArrival(fav);

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.favourites,
        onSelect: widget.onTab,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            AppModel.shared,
            DataStore.shared,
            LocationService.shared,
          ]),
          builder: (context, _) {
            // Auto-exit edit mode when the list becomes empty.
            if (_editing && _isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(() => _editing = false),
              );
            }
            return RefreshIndicator(
              color: t.accent,
              // Disable pull-to-refresh while editing — drag gestures conflict.
              onRefresh: _editing ? () async {} : _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _header(context),
                  const SizedBox(height: 14),
                  _segmentedControl(context),
                  const SizedBox(height: 16),
                  if (_isEmpty)
                    _emptyState(context)
                  else ...[
                    _stopsArea(context),
                    if (_visibleServices.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _servicesSection(context),
                    ],
                    // Saved MRT stations. In the MRT segment, show a hint when
                    // none are saved (the segment is otherwise empty); in All,
                    // only render the section when there are stations.
                    if (_segment == _Segment.mrt && _visibleStations.isEmpty)
                      _mrtEmptyHint(context)
                    else if (_visibleStations.isNotEmpty) ...[
                      if (_segment == _Segment.all) const SizedBox(height: 20),
                      _stationsSection(context),
                    ],
                    const SizedBox(height: 16),
                    _addStopRow(context),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final t = context.t;
    final canEdit = !_isEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Saved',
            style: t.sans(29, weight: FontWeight.w700, color: t.fg),
          ),
        ),
        if (canEdit)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _editing = !_editing),
            child: Padding(
              // Expand tap target without shifting layout.
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
              child: AnimatedSwitcher(
                duration: LyneMotion.short,
                child: Text(
                  _editing ? 'Done' : 'Edit',
                  key: ValueKey(_editing),
                  style: t.sans(
                    16,
                    weight: _editing ? FontWeight.w600 : FontWeight.w400,
                    color: t.accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Segmented control ────────────────────────────────────────────────────

  Widget _segmentedControl(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Row(
        children: [
          _segmentPill(context, 'All', _Segment.all, t),
          _segmentPill(context, 'Stops', _Segment.stops, t),
          _segmentPill(context, 'Buses', _Segment.buses, t),
          _segmentPill(context, 'MRT', _Segment.mrt, t),
        ],
      ),
    );
  }

  Widget _segmentPill(
    BuildContext context,
    String label,
    _Segment value,
    LyneTheme t,
  ) {
    final active = _segment == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _segment = value),
        child: AnimatedContainer(
          duration: LyneMotion.short,
          curve: LyneMotion.standardCurve,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? t.soon : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: t.sans(
              13,
              weight: FontWeight.w600,
              color: active ? t.contrastFg : t.dim,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Stops area ──────────────────────────────────────────────────────────

  Widget _stopsArea(BuildContext context) {
    final t = context.t;
    final pins = _visiblePins;

    // In the "all" segment, show the section header above stops.
    // In "stops" segment the section is self-evident — omit.
    // In "buses"/"mrt" segments there are no pins to render.
    if (_segment == _Segment.buses || _segment == _Segment.mrt) {
      return const SizedBox.shrink();
    }

    if (pins.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          'Pin a stop to see all its arrivals here.',
          style: t.sans(13, color: t.faint),
        ),
      );
    }

    final sectionHeader = _segment == _Segment.all
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 14, color: t.soon),
                const SizedBox(width: 6),
                Text(
                  'Saved stops',
                  style: t.sans(15, weight: FontWeight.w600, color: t.dim),
                ),
              ],
            ),
          )
        : null;

    if (_editing) {
      // ReorderableListView requires a fixed height when used inline inside a
      // ListView. We use shrinkWrap + NeverScrollableScrollPhysics so it
      // expands to its natural content height and delegates scrolling to the
      // outer ListView.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?sectionHeader,
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Remove the default drag elevation / Material shadow.
            proxyDecorator: (child, index, animation) =>
                Material(elevation: 0, color: Colors.transparent, child: child),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...pins];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              AppModel.shared.reorderPins(
                reordered.map((p) => p.code).toList(),
              );
            },
            children: [
              for (final pin in pins)
                Padding(
                  key: ValueKey('reorder-pin-${pin.code}'),
                  padding: EdgeInsets.only(bottom: pin == pins.last ? 0 : 10),
                  child: Row(
                    children: [
                      Expanded(child: _pinCard(context, pin)),
                      const SizedBox(width: 8),
                      ReorderableDragStartListener(
                        index: pins.indexOf(pin),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 22,
                            color: context.t.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // Normal (non-edit) mode — Dismissible swipe-to-delete.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?sectionHeader,
        for (var i = 0; i < pins.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _pinRow(context, pins[i]),
        ],
      ],
    );
  }

  Widget _pinRow(BuildContext context, Pin pin) {
    final t = context.t;
    final code = pin.code;

    return Dismissible(
      key: ValueKey('fav-$code'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.togglePin(code);
        // Always return false — AppModel mutation + ListenableBuilder rebuilds
        // the list; we never let Dismissible remove the widget itself.
        return false;
      },
      child: _pinCard(context, pin),
    );
  }

  Widget _pinCard(BuildContext context, Pin pin) {
    final code = pin.code;
    final dsName = DataStore.shared.stopName(code);
    final stopName = dsName.isEmpty ? code : dsName;
    final road = DataStore.shared.roadName(code);

    // If pin has a nickname, show it as title and stopName as desc.
    final nick = pin.nickname.trim();
    final hasNick =
        nick.isNotEmpty && nick.toLowerCase() != stopName.toLowerCase();
    final displayName = hasNick ? nick : stopName;
    final desc = hasNick ? stopName : (road.isEmpty ? null : road);

    // Service list — respects tracked subset.
    final allSvcs = DataStore.shared.servicesFor(code);
    final tracked = pin.tracked;
    final services = (tracked != null && tracked.isNotEmpty)
        ? allSvcs.where((s) => tracked.contains(s.no)).toList()
        : allSvcs;

    final walkMin = _walkMinFromLocation(code);
    final distM = _distanceMFromLocation(code);

    return _FavStopCard(
      name: displayName,
      code: code,
      desc: desc,
      road: road,
      walkMin: walkMin,
      distanceM: distM,
      services: services,
      feed: Freshness.from(DataStore.shared.lastRefresh(code)),
      onTap: () => widget.onOpenStop(code),
    );
  }

  // ─── Saved services section ───────────────────────────────────────────────

  Widget _servicesSection(BuildContext context) {
    final t = context.t;
    final items = _visibleServices;

    final sectionHeader = Row(
      children: [
        Icon(Icons.directions_bus_rounded, size: 14, color: t.soon),
        const SizedBox(width: 6),
        Text(
          'Buses',
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
      ],
    );

    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader,
          const SizedBox(height: 10),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, index, animation) =>
                Material(elevation: 0, color: Colors.transparent, child: child),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...items];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              AppModel.shared.reorderFavServices(
                reordered.map((f) => f.id).toList(),
              );
            },
            children: [
              for (final fav in items)
                Padding(
                  key: ValueKey('reorder-svc-${fav.id}'),
                  padding: EdgeInsets.only(bottom: fav == items.last ? 0 : 8),
                  child: Row(
                    children: [
                      Expanded(child: _serviceCard(context, fav)),
                      const SizedBox(width: 8),
                      ReorderableDragStartListener(
                        index: items.indexOf(fav),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 22,
                            color: t.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // Normal (non-edit) mode — Dismissible swipe-to-delete.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader,
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _serviceRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _serviceRow(BuildContext context, FavService fav) {
    final t = context.t;

    return Dismissible(
      key: ValueKey('fav-${fav.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.removeFavService(fav);
        return false;
      },
      child: _serviceCard(context, fav),
    );
  }

  Widget _serviceCard(BuildContext context, FavService fav) {
    final t = context.t;
    final resolved = _resolve(fav);
    final svc = resolved?.svc;
    final stopCode = resolved?.stopCode ?? fav.stop;

    final conf = svc != null
        ? ArrivalConfidence.of(
            monitored: svc.monitored,
            feed: Freshness.from(
              DataStore.shared.lastRefresh(resolved!.stopCode),
            ),
          )
        : ArrivalConfidence.none;

    final whereName =
        resolved?.stopName ??
        (fav.isAnywhere
            ? 'No nearby arrivals'
            : DataStore.shared.stopName(fav.stop ?? ''));

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stopCode != null
            ? () => widget.onOpenBus(stopCode, fav.no)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Badge keeps its standard look — proximity is not colour-coded.
              _ColoredBadge(no: fav.no, fill: t.accent, fg: t.onAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: fav.no,
                            style: t.sans(
                              15,
                              weight: FontWeight.w700,
                              color: t.fg,
                            ),
                          ),
                          if (svc != null)
                            TextSpan(
                              text: '  Towards ${svc.dest}',
                              style: t.sans(14, color: t.fg),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          fav.isAnywhere
                              ? Icons.location_on_rounded
                              : Icons.location_on_outlined,
                          size: 11,
                          color: t.dim,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            fav.isAnywhere
                                ? 'Near you · $whereName'
                                : whereName,
                            style: t.mono(11, color: t.dim),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: AppModel.shared,
                builder: (context, _) => _serviceEtas(context, svc, conf),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 16, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceEtas(
    BuildContext context,
    Service? svc,
    ArrivalConfidence conf,
  ) {
    final t = context.t;
    if (svc == null) {
      return Text(
        '—',
        style: t.mono(16, weight: FontWeight.w600, color: t.faint),
      );
    }
    final now = DateTime.now();
    final liveSec = svc.arrivalDate != null
        ? svc.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
        : svc.etaSec;
    final eta = fmtEta(liveSec);
    final color = etaColor(etaSec: liveSec, confidence: conf, t: t);
    final arriving = eta.big == 'Arr';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              arriving ? 'Arr' : eta.big,
              style: t.mono(18, weight: FontWeight.w700, color: color),
            ),
            if (!arriving) ...[
              const SizedBox(width: 2),
              Text(
                eta.small,
                style: t.mono(
                  12,
                  weight: FontWeight.w600,
                  color: color.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
        if (!arriving && svc.followingSec > 0) ...[
          const SizedBox(height: 1),
          _followingLabel(context, svc),
        ],
      ],
    );
  }

  Widget _followingLabel(BuildContext context, Service svc) {
    final t = context.t;
    final followEta = fmtEta(svc.followingSec);
    if (followEta.big.isEmpty || followEta.big == 'Arr') {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final parts = <String>[followEta.big];
    if (svc.thirdDate != null) {
      final thirdSec = svc.thirdDate!
          .difference(now)
          .inSeconds
          .clamp(0, 1 << 30);
      final third = fmtEta(thirdSec);
      if (third.big.isNotEmpty && third.big != 'Arr') {
        parts.add(third.big);
      }
    }
    return Text(
      '${parts.join(' · ')} min',
      style: t.mono(11, weight: FontWeight.w500, color: t.dim),
    );
  }

  // ─── Saved MRT stations section ───────────────────────────────────────────

  Widget _stationsSection(BuildContext context) {
    final t = context.t;
    final items = _visibleStations;

    final sectionHeader = Row(
      children: [
        Icon(Icons.train_rounded, size: 14, color: t.soon),
        const SizedBox(width: 6),
        Text(
          'Saved stations',
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
      ],
    );

    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHeader,
          const SizedBox(height: 10),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, index, animation) =>
                Material(elevation: 0, color: Colors.transparent, child: child),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...items];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              AppModel.shared.reorderSavedMrt(
                reordered.map((s) => s.id).toList(),
              );
            },
            children: [
              for (final station in items)
                Padding(
                  key: ValueKey('reorder-mrt-${station.id}'),
                  padding: EdgeInsets.only(
                    bottom: station == items.last ? 0 : 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _stationCard(context, station)),
                      const SizedBox(width: 8),
                      ReorderableDragStartListener(
                        index: items.indexOf(station),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 22,
                            color: t.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // Normal (non-edit) mode — Dismissible swipe-to-delete.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader,
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _stationRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _stationRow(BuildContext context, MrtGeoStation station) {
    final t = context.t;
    return Dismissible(
      key: ValueKey('fav-mrt-${station.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.removeMrtSaved(station);
        return false;
      },
      child: _stationCard(context, station),
    );
  }

  Widget _stationCard(BuildContext context, MrtGeoStation station) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenStation(station),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.surfaceHi,
                  borderRadius: BorderRadius.circular(LyneRadius.md),
                ),
                child: Icon(Icons.train_rounded, size: 20, color: t.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: t.sans(16, weight: FontWeight.w600, color: t.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: station.codes.map((code) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: lineColorFor(code),
                            borderRadius: BorderRadius.circular(LyneRadius.full),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 16, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }

  /// Hint shown in the MRT segment when no stations are saved yet (mirrors iOS
  /// hint "Save an MRT station to track it here.").
  Widget _mrtEmptyHint(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        'Save an MRT station to see it here.',
        style: t.sans(13, color: t.faint),
      ),
    );
  }

  // ─── Add stop row ─────────────────────────────────────────────────────────

  Widget _addStopRow(BuildContext context) {
    final t = context.t;
    // The Buses segment lists saved services, so the add row adds a bus there;
    // otherwise it adds a stop. Search finds both either way — only the label
    // follows the section the user is looking at.
    final isBuses = _segment == _Segment.buses;
    final isMrt = _segment == _Segment.mrt;
    final addLabel = isBuses
        ? 'Add bus'
        : isMrt
        ? 'Add station'
        : 'Add stop';
    return Semantics(
      label: isBuses
          ? 'Add a bus to favourites'
          : isMrt
          ? 'Add an MRT station to favourites'
          : 'Add a stop to favourites',
      button: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpenSearch,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surfaceHi,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_rounded, size: 18, color: LyneSignal.meBlue),
                ),
                const SizedBox(width: 12),
                Text(
                  addLabel,
                  style: t.sans(
                    15,
                    weight: FontWeight.w600,
                    color: LyneSignal.meBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Dismiss background helper ────────────────────────────────────────────

  Widget _dismissBackground({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
    required EdgeInsets padding,
  }) {
    // Ink must contrast the `color` fill (always t.crit). In Leyne's MONOCHROME
    // palette t.crit is #111 ink in light mode but **white** in dark mode, so a
    // hardcoded Colors.white icon/label rendered white-on-white in dark mode —
    // the Delete affordance vanished. t.contrastFg is the ink paired with
    // t.crit/t.contrast and flips correctly per mode (dark→#0F0F0F, light→white).
    final t = context.t;
    final ink = t.contrastFg;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      alignment: alignment,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ink, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────

  Widget _emptyState(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.star_outline_rounded,
              size: 28,
              color: LyneSignal.meBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No favourites yet',
            style: t.sans(20, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 6),
          Text(
            'Pin the stops and buses you use most — '
            "tap the pin on any stop or bus — and they'll show up here.",
            style: t.sans(13, color: t.dim),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: widget.onOpenSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(LyneRadius.full),
              ),
              child: Text(
                'Find a stop',
                style: t.sans(14, weight: FontWeight.w600, color: t.onAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Resolved arrival ────────────────────────────────────────────────────────

class _Resolved {
  const _Resolved({
    required this.svc,
    required this.stopName,
    required this.stopCode,
  });
  final Service svc;
  final String stopName;
  final String stopCode;
}

// ─── Service badge ───────────────────────────────────────────────────────────

/// 48dp service-number badge — standard accent fill (proximity is not
/// colour-coded; soon-ness reads from the ETA ink, not the badge).
class _ColoredBadge extends StatelessWidget {
  const _ColoredBadge({required this.no, required this.fill, required this.fg});

  final String no;
  final Color fill;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        no,
        style: t.sans(18, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── Favourite stop card ─────────────────────────────────────────────────────

/// Compact card matching iOS FavStopCard in SoftFavouritesView.swift:
///   46×46 pin tile · name (sans 17 w600) · "Stop {code} · road" (mono 12.5 dim)
///   · single compact meta line (walk + soonest arrival with "~" whisper)
///   · trailing chevron.
///
/// No divider, no mini-chip bus row (removed for parity with iOS). The whole
/// card taps to open the full stop view. `pin.nickname` and `pin.tracked`
/// handling is in the caller (_pinCard); the card just renders the resolved
/// name/desc and services it receives.
class _FavStopCard extends StatelessWidget {
  const _FavStopCard({
    required this.name,
    required this.code,
    required this.desc,
    required this.road,
    required this.walkMin,
    required this.distanceM,
    required this.services,
    required this.feed,
    required this.onTap,
  });

  final String name;
  final String code;
  final String? desc;
  final String road;
  final int walkMin;
  final int distanceM;
  final List<Service> services;
  final Freshness feed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Semantics(
      button: true,
      label: 'Open $name',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.line, width: 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 46×46 place tile — location glyph. Star badge removed:
                // everything in this tab is already saved, so the badge adds
                // noise without info.
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surfaceHi,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.location_on_rounded, size: 20, color: t.fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListenableBuilder(
                    listenable: AppModel.shared,
                    builder: (context, _) => _identityText(context, t),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityText(BuildContext context, LyneTheme t) {
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: t.sans(17, weight: FontWeight.w600, color: t.fg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: t.mono(12.5, color: t.dim),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        _compactMeta(t),
      ],
    );
  }

  /// Single merged meta line: walk time + soonest arrival with "~" whisper.
  /// Mirrors iOS FavStopCard.compactMeta — no chip row, no divider.
  Widget _compactMeta(LyneTheme t) {
    final now = DateTime.now();
    final sorted = [...services]..sort(_compareEta);
    final soonest = sorted.isEmpty ? null : sorted.first;
    final hasLocation = walkMin > 0 || distanceM > 0;
    if (!hasLocation && soonest == null) return const SizedBox.shrink();

    String? whenText;
    if (soonest != null) {
      final sec = soonest.arrivalDate != null
          ? soonest.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
          : soonest.etaSec;
      final eta = fmtEta(sec);
      whenText = eta.big == 'Arr'
          ? 'next now'
          : 'next in ${eta.big} ${eta.small}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLocation) ...[
          Icon(Icons.directions_walk_rounded, size: 12, color: t.soon),
          const SizedBox(width: 3),
          Text(
            '${walkMin < 1 ? 1 : walkMin} min',
            style: t.mono(12, weight: FontWeight.w500, color: t.soon),
          ),
          if (soonest != null) ...[
            const SizedBox(width: 5),
            Text('·', style: t.mono(12, color: t.faint)),
            const SizedBox(width: 5),
          ],
        ],
        if (soonest != null && whenText != null) ...[
          Icon(Icons.directions_bus_outlined, size: 11, color: t.dim),
          const SizedBox(width: 3),
          Text(
            whenText,
            style: t.mono(12, weight: FontWeight.w500, color: t.fg),
          ),
        ],
      ],
    );
  }

  static int _compareEta(Service a, Service b) => a.etaSec.compareTo(b.etaSec);
}
