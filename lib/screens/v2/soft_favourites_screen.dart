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
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
import '../../widgets/v2/soft_tab_bar.dart';

// ─── Segment enum ─────────────────────────────────────────────────────────────

enum _Segment { all, stops, buses }

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
    required this.onOpenSearch,
  });

  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;
  final void Function(String stopCode, String svc) onOpenBus;
  final VoidCallback onOpenSearch;

  @override
  State<SoftFavouritesScreen> createState() => _SoftFavouritesScreenState();
}

class _SoftFavouritesScreenState extends State<SoftFavouritesScreen> {
  _Segment _segment = _Segment.all;

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
        return const [];
    }
  }

  List<FavService> get _visibleServices {
    switch (_segment) {
      case _Segment.all:
      case _Segment.buses:
        return AppModel.shared.favServices;
      case _Segment.stops:
        return const [];
    }
  }

  bool get _isEmpty =>
      AppModel.shared.pins.isEmpty && AppModel.shared.favServices.isEmpty;

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
            return RefreshIndicator(
              color: t.accent,
              onRefresh: _refreshAll,
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
    return Text(
      'Saved',
      style: t.sans(29, weight: FontWeight.w700, color: t.fg),
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
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
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
    // In "buses" segment there are no pins to render.
    if (_segment == _Segment.buses) return const SizedBox.shrink();

    if (pins.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          'Pin a stop to see all its arrivals here.',
          style: t.sans(13, color: t.faint),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_segment == _Segment.all) ...[
          Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 14, color: t.soon),
              const SizedBox(width: 6),
              Text(
                'Saved stops',
                style: t.sans(15, weight: FontWeight.w600, color: t.dim),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
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
        icon: Icons.delete,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_bus_rounded, size: 14, color: t.soon),
            const SizedBox(width: 6),
            Text(
              'Buses',
              style: t.sans(15, weight: FontWeight.w600, color: t.dim),
            ),
          ],
        ),
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
        icon: Icons.delete,
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

    final badge = serviceBadgeColors(
      etaSec: svc?.etaSec ?? (1 << 30),
      confidence: conf,
      t: t,
    );

    final whereName = resolved?.stopName ??
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
              _ColoredBadge(no: fav.no, fill: badge.fill, fg: badge.fg),
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
                            style: t.sans(15,
                                weight: FontWeight.w700, color: t.fg),
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
              Icon(Icons.chevron_right, size: 16, color: t.faint),
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
                style: t.mono(12,
                    weight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85)),
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
      final thirdSec =
          svc.thirdDate!.difference(now).inSeconds.clamp(0, 1 << 30);
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

  // ─── Add stop row ─────────────────────────────────────────────────────────

  Widget _addStopRow(BuildContext context) {
    final t = context.t;
    return Semantics(
      label: 'Add a stop to favourites',
      button: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpenSearch,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  child: Icon(Icons.add, size: 18, color: LyneSignal.meBlue),
                ),
                const SizedBox(width: 12),
                Text(
                  'Add stop',
                  style: t.sans(15,
                      weight: FontWeight.w600, color: LyneSignal.meBlue),
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
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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
            child: Icon(Icons.star_outline_rounded, size: 28,
                color: LyneSignal.meBlue),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(LyneRadius.full),
              ),
              child: Text(
                'Find a stop',
                style:
                    t.sans(14, weight: FontWeight.w600, color: t.onAccent),
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

// ─── Proximity-coloured service badge ────────────────────────────────────────

/// 48dp service-number badge with a proximity-driven fill.
class _ColoredBadge extends StatelessWidget {
  const _ColoredBadge({
    required this.no,
    required this.fill,
    required this.fg,
  });

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

/// Mirrors FavStopCard in SoftFavouritesView.swift:
///   46×46 pin tile (gold star always shown — every stop here is pinned)
///   → name (sans 17 w600) + "Stop {code} · road" (mono 12.5 dim)
///   → walk/distance row (when location is available)
///   → 1px divider
///   → mini-chip bus row (up to 4 chips + "+N" overflow)
///
/// The chip row is wrapped in ListenableBuilder(AppModel.shared) so ETAs
/// tick on the 1-second heartbeat without rebuilding the whole card.
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

  static const int _maxChips = 4;

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
    final sorted = [...services]..sort(_compareEta);

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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityRow(context, t),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 1, color: t.line),
                ),
                ListenableBuilder(
                  listenable: AppModel.shared,
                  builder: (context, _) => sorted.isEmpty
                      ? _quietRow(t)
                      : _chipRow(context, t, sorted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityRow(BuildContext context, LyneTheme t) {
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';
    final hasLocation = walkMin > 0 || distanceM > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 46×46 pin tile — gold star badge always shown (all stops here are pinned).
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surfaceHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.location_on, size: 20, color: t.fg),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: t.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star,
                  size: 11,
                  color: Color(0xFFF5B500),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: t.sans(17, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: t.mono(12.5, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasLocation) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_walk, size: 13, color: t.soon),
                    const SizedBox(width: 3),
                    Text(
                      '${walkMin < 1 ? 1 : walkMin} min walk',
                      style: t.mono(12.5,
                          weight: FontWeight.w500, color: t.soon),
                    ),
                    const SizedBox(width: 5),
                    Text('·', style: t.mono(12.5, color: t.faint)),
                    const SizedBox(width: 5),
                    Text(
                      fmtDistance(distanceM),
                      style: t.mono(12.5, color: t.dim),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ],
    );
  }

  Widget _chipRow(BuildContext context, LyneTheme t, List<Service> sorted) {
    final now = DateTime.now();
    final visible = sorted.take(_maxChips).toList();
    final overflow = sorted.length > _maxChips ? sorted.length - _maxChips : 0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in visible)
          _MiniChip(
            svc: s.no,
            etaSec: s.arrivalDate != null
                ? s.arrivalDate!
                    .difference(now)
                    .inSeconds
                    .clamp(0, 1 << 30)
                : s.etaSec,
            confidence: ArrivalConfidence.of(
              monitored: s.monitored,
              feed: feed,
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '+$overflow',
              style:
                  t.mono(12, weight: FontWeight.w600, color: t.faint),
            ),
          ),
      ],
    );
  }

  Widget _quietRow(LyneTheme t) {
    return Row(
      children: [
        const ConfidenceDot(confidence: ArrivalConfidence.stale, size: 6),
        const SizedBox(width: 7),
        Text('No live arrivals right now',
            style: t.mono(12, color: t.faint)),
      ],
    );
  }

  static int _compareEta(Service a, Service b) =>
      a.etaSec.compareTo(b.etaSec);
}

// ─── Mini chip ───────────────────────────────────────────────────────────────

/// Compact "88 · 3 min" chip — same shape as _MiniBusChip in soft_home_screen.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.svc,
    required this.etaSec,
    required this.confidence,
  });

  final String svc;
  final int etaSec;
  final ArrivalConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final eta = fmtEta(etaSec);
    final arriving = eta.big == 'Arr';
    final imminent = confidence == ArrivalConfidence.live && eta.live;
    final whisper = confidence == ArrivalConfidence.stale ||
        confidence == ArrivalConfidence.unconfirmed;
    final label = arriving ? 'now' : '${eta.big} ${eta.small}';

    return Container(
      height: 27,
      padding: const EdgeInsets.only(left: 4, right: 9),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(LyneRadius.full),
        border: Border.all(color: t.line, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 18,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.line, width: 0.5),
            ),
            child: Text(
              svc,
              style: t.mono(12, weight: FontWeight.w700, color: t.fg),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: t.mono(
              12,
              weight: FontWeight.w600,
              color: imminent ? t.accent : t.dim,
            ),
          ),
          if (whisper) ...[
            const SizedBox(width: 1),
            ExcludeSemantics(
              child: Opacity(
                opacity: 0.7,
                child: Text('~', style: t.mono(9, color: t.faint)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
