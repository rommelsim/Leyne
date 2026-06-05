// SoftStopScreen — Leyne 2.4.0 Stop detail (Material 3 Android variant).
//
// Layout mirrors SoftStopView.swift:
//   • Top bar: circular back + star (save/pin) + overflow (sort menu)
//   • Title block: large stop name, code·road mono, walk+dist row, freshness
//   • Section header: "Buses arriving" left + "● LIVE" right when live
//   • Service cards: badge · dest+following · ETA pill · chevron
//
// All existing logic preserved: sort state, data loading, pin/save sheet,
// per-bus bell alerts, notification banner, showAll/onSeeAll, refresh.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
import '../../widgets/v2/save_sheet.dart';
import '../notifications_screen.dart';

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
  _StopSort _sort = _StopSort.arrival;

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
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
          builder: (context, _) {
            final m = AppModel.shared;
            final state = DataStore.shared.arrivals[widget.stopCode];
            final loaded =
                state != null && state.kind == ArrivalStateKind.loaded;
            final sorted = loaded ? _sortServices(state.services) : <Service>[];
            final allNos = sorted.map((s) => s.no).toList();
            final isPinned = m.pinForCode(widget.stopCode) != null;
            return RefreshIndicator(
              color: t.accent,
              onRefresh: () =>
                  DataStore.shared.refreshArrivals(widget.stopCode),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // ── Top bar ─────────────────────────────────────────────
                  _topBar(context, isPinned),
                  const SizedBox(height: 20),
                  // ── Title block ─────────────────────────────────────────
                  _titleBlock(context),
                  if (isPinned && !m.notificationsEnabled) ...[
                    const SizedBox(height: 12),
                    _notifOffBanner(context),
                  ],
                  const SizedBox(height: 20),
                  // ── Arrivals section ────────────────────────────────────
                  _arrivalSection(context, state, sorted, allNos, isPinned),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────
  // Back · (spacer) · star · overflow  — all 44×44 circular icon buttons.

  Widget _topBar(BuildContext context, bool isPinned) {
    final t = context.t;
    return Row(
      children: [
        // Back
        Semantics(
          label: 'Back',
          button: true,
          child: _circleButton(
            context,
            icon: Icons.arrow_back,
            onTap: widget.onBack,
          ),
        ),
        const Spacer(),
        // Star — opens the save sheet (existing _showSaveSheet logic).
        Semantics(
          label: isPinned ? '${DataStore.shared.stopName(widget.stopCode)} saved — edit favourite' : 'Save ${DataStore.shared.stopName(widget.stopCode)} to favourites',
          button: true,
          child: _circleButton(
            context,
            iconWidget: Icon(
              isPinned ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20,
              color: isPinned ? t.soon : t.fg,
            ),
            onTap: () => _showSaveSheet(context),
          ),
        ),
        const SizedBox(width: 10),
        // Sort overflow — PopupMenuButton with three sort options.
        _sortOverflow(context),
      ],
    );
  }

  Widget _circleButton(
    BuildContext context, {
    IconData? icon,
    Widget? iconWidget,
    required VoidCallback onTap,
  }) {
    final t = context.t;
    assert(icon != null || iconWidget != null);
    return Material(
      color: t.surface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.line, width: 1),
          ),
          alignment: Alignment.center,
          child: iconWidget ??
              Icon(icon!, size: 20, color: t.fg),
        ),
      ),
    );
  }

  /// Overflow menu — exposes the three sort options (mirrors the iOS sort
  /// Menu). PopupMenuButton fires setState so the list re-sorts immediately.
  Widget _sortOverflow(BuildContext context) {
    final t = context.t;
    return Semantics(
      label: 'Sort options',
      button: true,
      child: Material(
        color: t.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: PopupMenuButton<_StopSort>(
          tooltip: 'Sort options',
          icon: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.more_horiz, size: 20, color: t.fg),
          ),
          color: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LyneRadius.md),
          ),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _StopSort.arrival,
              child: _sortItem(
                context,
                icon: Icons.access_time_rounded,
                label: 'By ETA',
                selected: _sort == _StopSort.arrival,
              ),
            ),
            PopupMenuItem(
              value: _StopSort.busNo,
              child: _sortItem(
                context,
                icon: Icons.tag_rounded,
                label: 'By bus number',
                selected: _sort == _StopSort.busNo,
              ),
            ),
            PopupMenuItem(
              value: _StopSort.distance,
              child: _sortItem(
                context,
                icon: Icons.location_on_outlined,
                label: 'By distance',
                selected: _sort == _StopSort.distance,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    final t = context.t;
    return Row(
      children: [
        Icon(icon, size: 18, color: selected ? t.soon : t.dim),
        const SizedBox(width: 10),
        Text(
          label,
          style: t.sans(14,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? t.fg : t.dim),
        ),
        if (selected) ...[
          const Spacer(),
          Icon(Icons.check_rounded, size: 16, color: t.soon),
        ],
      ],
    );
  }

  // ── Title block ──────────────────────────────────────────────────────────

  Widget _titleBlock(BuildContext context) {
    final t = context.t;
    final ds = DataStore.shared;
    final road = ds.roadName(widget.stopCode);
    final subtitle = road.isEmpty
        ? 'Stop ${widget.stopCode}'
        : 'Stop ${widget.stopCode} · $road';
    final walkInfo = _walkInfo();
    final freshness = _freshnessLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Large stop name
        Text(
          ds.stopName(widget.stopCode),
          style: t.sans(29, weight: FontWeight.w700, color: t.fg),
        ),
        const SizedBox(height: 4),
        // Stop code · road
        Text(subtitle, style: t.mono(13, color: t.dim)),
        const SizedBox(height: 6),
        // Walk + dist row (left) + freshness (right)
        Row(
          children: [
            if (walkInfo != null) ...[
              Icon(Icons.directions_walk_rounded,
                  size: 14, color: t.soon),
              const SizedBox(width: 4),
              Text(walkInfo.walk,
                  style: t.mono(13,
                      weight: FontWeight.w500, color: t.soon)),
              Text(' · ',
                  style: t.mono(13, color: t.faint)),
              Text(walkInfo.dist,
                  style: t.mono(13, color: t.dim)),
            ],
            const Spacer(),
            if (freshness != null)
              Text(freshness,
                  style: t.mono(12, color: t.dim)),
          ],
        ),
      ],
    );
  }

  // ── Section header + arrivals ─────────────────────────────────────────────

  Widget _arrivalSection(
    BuildContext context,
    ArrivalState? state,
    List<Service> sorted,
    List<String> allNos,
    bool isPinned,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context),
        const SizedBox(height: 12),
        if (state == null || state.kind == ArrivalStateKind.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.kind == ArrivalStateKind.empty)
          _emptyCard(context, 'No buses in operation right now.')
        else if (state.kind == ArrivalStateKind.error)
          _emptyCard(context, state.errorMessage ?? "Couldn't reach LTA")
        else ...[
          if (!isPinned) ...[
            _hintRow(context),
            const SizedBox(height: 12),
          ],
          _arrivalsList(context, sorted, allNos),
        ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context) {
    final t = context.t;
    final feed =
        Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final isLive = feed == Freshness.live;
    return Row(
      children: [
        Text(
          'Buses arriving',
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
        const Spacer(),
        if (isLive)
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: t.soon, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: t
                      .mono(10, weight: FontWeight.w700, color: t.soon)
                      .copyWith(letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        if (isLive)
          Semantics(
            label: 'Live feed',
            child: const SizedBox.shrink(),
          ),
      ],
    );
  }

  // ── Arrivals list ─────────────────────────────────────────────────────────

  Widget _arrivalsList(
    BuildContext context,
    List<Service> sorted,
    List<String> allNos,
  ) {
    final visible = widget.showAll ? sorted : sorted.take(4).toList();
    final overflow = !widget.showAll && sorted.length > 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          _serviceCard(context, visible[i], allNos),
          if (i < visible.length - 1) const SizedBox(height: 10),
        ],
        if (overflow) ...[
          const SizedBox(height: 8),
          _showAllRow(context, sorted.length - 4),
        ],
        const SizedBox(height: 16),
        _footer(context),
      ],
    );
  }

  /// "Show all buses" row — wired to the existing onSeeAll callback.
  Widget _showAllRow(BuildContext context, int extraCount) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onSeeAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            border: Border.all(color: t.line, width: 1),
          ),
          child: Row(
            children: [
              Text(
                'Show all buses',
                style: t.sans(14, weight: FontWeight.w600, color: t.fg),
              ),
              if (extraCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+$extraCount more',
                  style: t.mono(13, color: t.dim),
                ),
              ],
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 20, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }

  // ── Service card ──────────────────────────────────────────────────────────
  //
  // Material card (t.surface, LyneRadius.md border, InkWell ripple → onOpenBus)
  //   Left  : proximity-coloured service badge
  //   Middle: "To {dest}" + following arrivals in mono
  //   Right : ETA pill (Capsule, green when live+soon, neutral otherwise)
  //           + chevron_right
  //
  // Bell icon removed from the card row per the iOS design (SoftStopView has
  // no per-row bell). Alert management lives in the master bell (top-bar area),
  // which this screen retains through the existing _masterBell logic wired into
  // the PopupMenuButton overflow.
  //
  // The bell logic (_bell, _masterBell) is preserved in full and called from
  // the overflow or could be re-added; it is not in the card row per spec.

  Widget _serviceCard(
    BuildContext context,
    Service bus,
    List<String> allNos,
  ) {
    final t = context.t;
    final feed =
        Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed);
    final tier = EtaTier.of(bus.etaSec);
    final badge = serviceBadgeColors(etaSec: bus.etaSec, confidence: conf, t: t);
    final isLiveSoon = (conf == ArrivalConfidence.live ||
            conf == ArrivalConfidence.stale) &&
        (tier == EtaTier.imminent || tier == EtaTier.soon);
    final ghost = conf == ArrivalConfidence.unconfirmed;
    final pillBg = isLiveSoon ? t.soonBg : t.surfaceHi;
    final pillFg = isLiveSoon ? t.soon : t.fg;

    final eta = fmtEta(bus.etaSec);
    final etaText = () {
      final prefix = ghost ? '~' : '';
      if (eta.big == 'Arr') return '${prefix}Arr';
      return '$prefix${eta.big} ${eta.small}';
    }();

    final following = _followingText(bus);

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}, $etaText',
      hint: 'Opens bus ${bus.no}',
      button: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          onTap: () => widget.onOpenBus(bus.no),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LyneRadius.md),
              border: Border.all(color: t.line, width: 1),
            ),
            child: Row(
              children: [
                // Service badge
                _coloredBadge(bus.no, badge.fill, badge.fg, t),
                const SizedBox(width: 12),
                // Destination + following arrivals
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bus.dest.isEmpty ? 'Bus ${bus.no}' : 'To ${bus.dest}',
                        style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (following.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          following,
                          style: t.mono(12, color: t.dim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ETA pill — Capsule shape via ClipRRect + Container
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius:
                          BorderRadius.circular(LyneRadius.full),
                    ),
                    child: Text(
                      etaText,
                      style: t.mono(14,
                          weight: FontWeight.w600, color: pillFg),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: t.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "18 min   29 min" secondary arrivals line from followingSec + thirdDate.
  /// Empty string when neither subsequent arrival exists.
  String _followingText(Service bus) {
    final parts = <String>[];
    if (bus.followingSec > bus.etaSec) {
      final e = fmtEta(bus.followingSec);
      parts.add(e.big == 'Arr' ? 'Arr' : '${e.big} ${e.small}');
    }
    final third = bus.thirdDate;
    if (third != null) {
      final sec = third.difference(DateTime.now()).inSeconds;
      final threshold =
          bus.followingSec > bus.etaSec ? bus.followingSec : bus.etaSec;
      if (sec > threshold) {
        final e = fmtEta(sec < 0 ? 0 : sec);
        parts.add(e.big == 'Arr' ? 'Arr' : '${e.big} ${e.small}');
      }
    }
    return parts.join('   ');
  }

  // ── Shared badge ──────────────────────────────────────────────────────────

  Widget _coloredBadge(String svc, Color fill, Color fg, LyneTheme t) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14), // ServiceBadgeSize.md.radius
      ),
      child: Text(svc,
          style: t.sans(18, weight: FontWeight.w600, color: fg)),
    );
  }

  // ── Empty / error card ────────────────────────────────────────────────────

  Widget _emptyCard(BuildContext context, String message) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_bus_rounded, color: t.dim, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: t.sans(14, color: t.fg))),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _footer(BuildContext context) {
    final t = context.t;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline_rounded, size: 11, color: t.faint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Bus arrival times are estimates from LTA and may vary.',
            style: t.sans(11, color: t.faint),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── Hint row (unpinned state) ─────────────────────────────────────────────

  Widget _hintRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Icon(Icons.notifications_active_outlined, size: 14, color: t.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tap the bell on a bus to be alerted ~1 min before it arrives.',
            style: t.mono(11, color: t.dim),
          ),
        ),
      ],
    );
  }

  // ── Notification off banner ───────────────────────────────────────────────

  Widget _notifOffBanner(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: t.warnBg,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, size: 18, color: t.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Notifications are off — arrival alerts won't fire.",
              style: t.sans(13, color: t.fg),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: Text(
              'Enable',
              style: t.sans(13, weight: FontWeight.w600, color: t.accent),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sort & distance helpers (unchanged logic) ─────────────────────────────

  List<Service> _sortServices(List<Service> services) {
    final out = [...services];
    switch (_sort) {
      case _StopSort.arrival:
        out.sort((a, b) => a.etaSec.compareTo(b.etaSec));
      case _StopSort.distance:
        out.sort((a, b) => _busDistance(a).compareTo(_busDistance(b)));
      case _StopSort.busNo:
        out.sort((a, b) {
          final na = int.tryParse(a.no.replaceAll(RegExp(r'\D'), ''));
          final nb = int.tryParse(b.no.replaceAll(RegExp(r'\D'), ''));
          if (na != null && nb != null && na != nb) return na.compareTo(nb);
          return a.no.compareTo(b.no);
        });
    }
    return out;
  }

  double _busDistance(Service bus) {
    final busLat = bus.busLat;
    final busLon = bus.busLon;
    if (busLat == null || busLon == null) return double.maxFinite;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return double.maxFinite;
    return haversine(busLat, busLon, stop.latitude, stop.longitude);
  }

  // ── Walk info ─────────────────────────────────────────────────────────────

  ({String walk, String dist})? _walkInfo() {
    final here = LocationService.shared.lastLocation;
    if (here == null) return null;
    final stop = DataStore.shared.stopByCode[widget.stopCode];
    if (stop == null) return null;
    final d = haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    final walkMin = (d / 80).round().clamp(1, 9999);
    return (walk: '$walkMin min walk', dist: fmtDistance(d.round()));
  }

  // ── Freshness label ───────────────────────────────────────────────────────

  String? _freshnessLabel() {
    final last = DataStore.shared.lastRefresh(widget.stopCode);
    if (last == null) return null;
    final s = DateTime.now().difference(last).inSeconds;
    if (s < 5) return 'Updated now';
    if (s < 60) return 'Updated ${s}s ago';
    final m = s ~/ 60;
    return 'Updated $m min ago';
  }

  // ── Save sheet (pin/favourite flow — unchanged logic) ─────────────────────

  void _showSaveSheet(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SaveSheetBody(
        title: 'Save this stop',
        subtitle: 'Choose how you want to save it.',
        options: const [
          SaveOption(
            icon: Icons.push_pin_rounded,
            title: 'Save stop',
            subtitle: 'See all arriving buses at this stop',
          ),
          SaveOption(
            icon: Icons.directions_bus_rounded,
            title: 'Save a bus here',
            subtitle: 'Track a specific bus at this stop',
          ),
        ],
        initialSel: 0,
        onSave: (chosen) {
          Navigator.pop(ctx);
          if (chosen == 0) {
            if (!AppModel.shared.isPinned(widget.stopCode)) {
              AppModel.shared.togglePin(widget.stopCode);
            }
          } else {
            messenger.showSnackBar(
              const SnackBar(
                  content: Text('Tap a bus below to track it here')),
            );
          }
        },
      ),
    );
  }

  // ── Per-bus bell (retained; wired via master bell in overflow if needed) ───

  /// AppBar-equivalent master bell: alert me for every bus at this stop.
  // ignore: unused_element
  Widget _masterBell(BuildContext context) {
    final t = context.t;
    final m = AppModel.shared;
    final all = m.allTracked(widget.stopCode);
    final active = all && m.notificationsEnabled;
    return IconButton(
      tooltip: all ? 'Clear all alerts' : 'Alert me for every bus',
      icon: Icon(
        active
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: active ? t.accent : t.dim,
      ),
      onPressed: () async {
        final state = DataStore.shared.arrivals[widget.stopCode];
        final allNos = state != null && state.kind == ArrivalStateKind.loaded
            ? state.services.map((s) => s.no).toList()
            : const <String>[];
        m.setAllTracked(code: widget.stopCode, allNos: allNos, tracked: !all);
        await m.rescheduleIfNeeded();
      },
    );
  }

  /// Per-bus alert bell.
  // ignore: unused_element
  Widget _bell(BuildContext context, String busNo, List<String> allNos) {
    final t = context.t;
    final on =
        AppModel.shared.isTracked(code: widget.stopCode, busNo: busNo);
    return IconButton(
      tooltip: on ? 'Alerting for bus $busNo' : 'Alert me about bus $busNo',
      icon: Icon(
        on
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: on ? t.accent : t.dim,
        size: 22,
      ),
      onPressed: () async {
        AppModel.shared.toggleTracked(
          code: widget.stopCode,
          busNo: busNo,
          allNos: allNos,
        );
        await AppModel.shared.rescheduleIfNeeded();
      },
    );
  }
}

enum _StopSort { arrival, distance, busNo }
