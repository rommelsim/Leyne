// SoftFavouritesScreen — Leyne 2.4.0 Favourites tab (Material 3 Android).
//
// Shows the user's saved stops (m.pins) and saved services (m.favServices)
// in two sections, each with a filter-chip row at the top (All / Stops /
// Services / Bus+Stop). Mirrors the layout and data resolution of
// ios-native/Leyne/V2/SoftFavouritesView.swift — Material-native rendering.
//
// Filter semantics (matching iOS):
//   All      → both sections visible
//   Stops    → only Pinned stops
//   Services → only "anywhere" service favourites (isAnywhere == true)
//   Bus+Stop → only stop-specific service favourites (isAnywhere == false)

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

// ─── Filter enum ─────────────────────────────────────────────────────────────

enum _FavFilter { all, stops, services, busStop }

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
  _FavFilter _filter = _FavFilter.all;
  bool _editingStops = false;
  bool _editingServices = false;

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
    DataStore.shared.prefetchNearbyArrivals();
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
    DataStore.shared.prefetchNearbyArrivals();
  }

  bool get _showStops =>
      _filter == _FavFilter.all || _filter == _FavFilter.stops;

  bool get _showServices =>
      _filter == _FavFilter.all ||
      _filter == _FavFilter.services ||
      _filter == _FavFilter.busStop;

  List<FavService> get _filteredServices {
    final all = AppModel.shared.favServices;
    switch (_filter) {
      case _FavFilter.services:
        return all.where((f) => f.isAnywhere).toList();
      case _FavFilter.busStop:
        return all.where((f) => !f.isAnywhere).toList();
      default:
        return all;
    }
  }

  // ── Arrival resolution ──────────────────────────────────────────────────

  /// For a stop-specific favourite: pull its first Service with matching no.
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

  /// For an "anywhere" favourite: scan nearby stops (distance-sorted) for the
  /// first one that serves this bus — mirrors iOS anywhereArrival().
  _Resolved? _anywhereArrival(FavService fav) {
    for (final n in DataStore.shared.nearby) {
      final svc = DataStore.shared
          .servicesFor(n.stopCode)
          .cast<Service?>()
          .firstWhere((s) => s!.no == fav.no, orElse: () => null);
      if (svc != null) {
        return _Resolved(
          svc: svc,
          stopName: n.stopName,
          stopCode: n.stopCode,
        );
      }
    }
    return null;
  }

  _Resolved? _resolve(FavService fav) =>
      fav.isAnywhere ? _anywhereArrival(fav) : _atStopArrival(fav);

  // ── Walk/distance helpers ───────────────────────────────────────────────

  int? _walkMinutes(String code) {
    final here = LocationService.shared.lastLocation;
    if (here == null) return null;
    final stop = DataStore.shared.stopByCode[code];
    if (stop == null) return null;
    final d =
        haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    return walkMinutesFor(d);
  }

  String? _trailingLabel(String code) {
    final here = LocationService.shared.lastLocation;
    if (here == null) return null;
    final stop = DataStore.shared.stopByCode[code];
    if (stop == null) return null;
    final d =
        haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    return fmtDistance(d.round());
  }

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
            final pins = AppModel.shared.pins;
            final isEmpty =
                pins.isEmpty && AppModel.shared.favServices.isEmpty;
            return RefreshIndicator(
              color: t.accent,
              onRefresh: _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _header(context),
                  const SizedBox(height: 16),
                  if (isEmpty)
                    _emptyState(context)
                  else ...[
                    _filterChips(context),
                    const SizedBox(height: 16),
                    if (_showStops) ...[
                      _stopsSection(context),
                      const SizedBox(height: 20),
                    ],
                    if (_showServices) _servicesSection(context),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: t.mono(
                  11,
                  weight: FontWeight.w600,
                  color: t.dim,
                ).copyWith(letterSpacing: 0.6),
              ),
              const SizedBox(height: 2),
              Text(
                'Favourites',
                style: t.sans(28, weight: FontWeight.w700, color: t.fg),
              ),
              Text(
                'Your saved stops and services',
                style: t.sans(13, color: t.dim),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _circleButton(
            icon: Icons.add_rounded,
            label: 'Add a favourite',
            onTap: widget.onOpenSearch,
            context: context,
          ),
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final t = context.t;
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: t.surface,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: t.fg),
          ),
        ),
      ),
    );
  }

  // ─── Filter chips ────────────────────────────────────────────────────────

  Widget _filterChips(BuildContext context) {
    final t = context.t;
    const options = [
      (_FavFilter.all, 'All'),
      (_FavFilter.stops, 'Stops'),
      (_FavFilter.services, 'Services'),
      (_FavFilter.busStop, 'Bus + Stop'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _filterChip(options[i].$1, options[i].$2, t),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(_FavFilter filter, String label, LyneTheme t) {
    final selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.contrast : t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.full),
          border: Border.all(
            color: selected ? t.contrast : t.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: t.sans(
            13,
            weight: FontWeight.w600,
            color: selected ? t.contrastFg : t.fg,
          ),
        ),
      ),
    );
  }

  // ─── Section header ──────────────────────────────────────────────────────

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool showEdit,
    required bool editing,
    required VoidCallback onEditTap,
  }) {
    final t = context.t;
    return Row(
      children: [
        Icon(icon, size: 14, color: t.soon),
        const SizedBox(width: 6),
        Text(
          title,
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
        const Spacer(),
        if (showEdit)
          GestureDetector(
            onTap: onEditTap,
            child: Text(
              editing ? 'Done' : 'Edit',
              style: t.sans(14, weight: FontWeight.w600, color: t.accent),
            ),
          ),
      ],
    );
  }

  Widget _hint(BuildContext context, String text) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: t.sans(13, color: t.faint)),
    );
  }

  // ─── Stops section ───────────────────────────────────────────────────────

  Widget _stopsSection(BuildContext context) {
    final pins = AppModel.shared.pins;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          title: 'Pinned stops',
          icon: Icons.location_on_rounded,
          showEdit: pins.isNotEmpty,
          editing: _editingStops,
          onEditTap: () => setState(() => _editingStops = !_editingStops),
        ),
        const SizedBox(height: 10),
        if (pins.isEmpty)
          _hint(context, 'Pin a stop to see all its arrivals here.')
        else
          for (var i = 0; i < pins.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _stopRow(context, pins[i]),
          ],
      ],
    );
  }

  Widget _stopRow(BuildContext context, Pin pin) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      crossFadeState: _editingStops
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _stopCard(context, pin),
      secondChild: Row(
        children: [
          _removeButton(context, onTap: () {
            setState(() {
              AppModel.shared.pins.removeWhere((p) => p.code == pin.code);
            });
          }),
          const SizedBox(width: 10),
          Expanded(child: _stopCard(context, pin)),
        ],
      ),
    );
  }

  Widget _stopCard(BuildContext context, Pin pin) {
    final dsName = DataStore.shared.stopName(pin.code);
    final stopName = dsName.isEmpty ? pin.code : dsName;
    final nick = pin.nickname.trim();
    final hasNick =
        nick.isNotEmpty && nick.toLowerCase() != stopName.toLowerCase();
    final walk = _walkMinutes(pin.code);
    final trailing = walk != null ? '$walk min' : _trailingLabel(pin.code);

    final all = DataStore.shared.servicesFor(pin.code);
    final tracked = pin.tracked;
    final services = (tracked != null && tracked.isNotEmpty)
        ? all.where((s) => tracked.contains(s.no)).toList()
        : all;

    return _FavStopCard(
      name: hasNick ? nick : stopName,
      code: pin.code,
      desc: hasNick ? stopName : DataStore.shared.roadName(pin.code),
      trailing: trailing,
      services: services,
      feed: Freshness.from(DataStore.shared.lastRefresh(pin.code)),
      onTap: () => widget.onOpenStop(pin.code),
    );
  }

  // ─── Services section ────────────────────────────────────────────────────

  Widget _servicesSection(BuildContext context) {
    final items = _filteredServices;
    final hintText = _filter == _FavFilter.services
        ? "Save a bus 'anywhere' to follow it across stops."
        : _filter == _FavFilter.busStop
            ? 'Track a specific bus at a stop to follow it here.'
            : "Save a bus or tap the pin on a stop's bus row to see it here.";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          title: 'Pinned services',
          icon: Icons.directions_bus_rounded,
          showEdit: items.isNotEmpty,
          editing: _editingServices,
          onEditTap: () =>
              setState(() => _editingServices = !_editingServices),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          _hint(context, hintText)
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _serviceRow(context, items[i]),
          ],
      ],
    );
  }

  Widget _serviceRow(BuildContext context, FavService fav) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      crossFadeState: _editingServices
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _serviceCard(context, fav),
      secondChild: Row(
        children: [
          _removeButton(context, onTap: () {
            AppModel.shared.removeFavService(fav);
          }),
          const SizedBox(width: 10),
          Expanded(child: _serviceCard(context, fav)),
        ],
      ),
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
              // Proximity-coloured badge.
              _ColoredBadge(no: fav.no, fill: badge.fill, fg: badge.fg),
              const SizedBox(width: 12),
              // Route info.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service number + destination inline.
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
                    // Location row.
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
              // ETA column.
              ListenableBuilder(
                listenable: AppModel.shared,
                builder: (context, _) =>
                    _serviceEtas(context, svc, conf),
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
        // Primary ETA.
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
                style: t.mono(12, weight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85)),
              ),
            ],
          ],
        ),
        // Following ETA, when present.
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

  // ─── Remove button ───────────────────────────────────────────────────────

  Widget _removeButton(BuildContext context, {required VoidCallback onTap}) {
    final t = context.t;
    return Semantics(
      label: 'Remove',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          Icons.remove_circle,
          size: 26,
          color: t.crit,
        ),
      ),
    );
  }

  // ─── Empty state ─────────────────────────────────────────────────────────

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
            child: Icon(Icons.star_outline_rounded, size: 28, color: t.accent),
          ),
          const SizedBox(height: 16),
          Text(
            'No favourites yet',
            style: t.sans(20, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 6),
          Text(
            'Pin the stops and buses you use most — '
            'tap the pin on any stop or bus — and they\'ll show up here.',
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
                style: t.sans(14, weight: FontWeight.w600, color: t.onAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Greeting ────────────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'GOOD MORNING';
    if (h >= 12 && h < 17) return 'GOOD AFTERNOON';
    if (h >= 17 && h < 22) return 'GOOD EVENING';
    return 'GOOD NIGHT';
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

/// 48dp service number badge with a proximity-driven fill colour.
/// Extracted because the ServiceBadge in soft_components.dart uses the fixed
/// accent colour; here we override fill and fg from serviceBadgeColors().
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

// ─── Pinned-stop card ────────────────────────────────────────────────────────

/// Compact stop card for the Favourites pinned-stops section.
/// Mirrors _SoftStopCard from soft_home_screen.dart — extracted here to avoid
/// coupling to the home screen's private class.
class _FavStopCard extends StatelessWidget {
  const _FavStopCard({
    required this.name,
    required this.code,
    required this.desc,
    required this.trailing,
    required this.services,
    required this.feed,
    required this.onTap,
  });

  static const int _maxChips = 4;

  final String name;
  final String code;
  final String? desc;
  final String? trailing;
  final List<Service> services;
  final Freshness feed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sorted = [...services]..sort(_compareNo);

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerRow(context, t),
              const SizedBox(height: 11),
              if (sorted.isEmpty)
                _quietRow(context, t)
              else
                _chipRow(context, t, sorted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context, LyneTheme t) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.location_on, size: 18, color: t.fg),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: t.sans(16, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                (desc == null || desc!.isEmpty) ? code : '$code · $desc',
                style: t.mono(11.5, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: t.mono(12, weight: FontWeight.w600, color: t.dim),
          ),
        ],
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ],
    );
  }

  Widget _chipRow(BuildContext context, LyneTheme t, List<Service> sorted) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final now = DateTime.now();
        final visible = sorted.take(_maxChips).toList();
        final overflow =
            sorted.length > _maxChips ? sorted.length - _maxChips : 0;
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
                  style: t.mono(12, weight: FontWeight.w600, color: t.faint),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _quietRow(BuildContext context, LyneTheme t) {
    return Row(
      children: [
        const ConfidenceDot(confidence: ArrivalConfidence.stale, size: 6),
        const SizedBox(width: 7),
        Text('No live arrivals right now',
            style: t.mono(11, color: t.faint)),
      ],
    );
  }

  static int _compareNo(Service a, Service b) {
    int lead(String s) =>
        int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? (1 << 30);
    final c = lead(a.no).compareTo(lead(b.no));
    return c != 0 ? c : a.no.compareTo(b.no);
  }
}

// ─── Mini chip ───────────────────────────────────────────────────────────────

/// Compact "88 · 3 min" chip — identical in shape to the one in
/// soft_home_screen.dart's _MiniBusChip.
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
                child: Text(
                  '~',
                  style: t.mono(9, color: t.faint),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
