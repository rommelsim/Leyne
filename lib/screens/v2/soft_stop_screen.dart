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

  /// Inline expand state for the grouped arrivals list. Opened from a
  /// "see all" entry (widget.showAll) starts expanded.
  late bool _expanded = widget.showAll;

  /// Services shown before the "Show more" expander kicks in.
  static const int _collapsedCount = 6;

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
                  _arrivalSection(context, state, sorted, isPinned),
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
        // Star menu — pin/unpin this stop or save a specific bus here,
        // without leaving the page (replaces the old save-sheet-only flow).
        _starMenu(context, isPinned),
        const SizedBox(width: 10),
        // Sort overflow — PopupMenuButton with three sort options.
        _sortOverflow(context),
      ],
    );
  }

  /// Star popup: pin/unpin (Saved) + "save a bus here". The star fills green
  /// when the stop is pinned. Mirrors iOS SoftStopView's star Menu.
  Widget _starMenu(BuildContext context, bool isPinned) {
    final t = context.t;
    final name = DataStore.shared.stopName(widget.stopCode);
    // Save toggle — pins/unpins this stop. A pin glyph fills when saved; to
    // save a specific bus instead, open the bus and toggle its (bus-glyph)
    // save there.
    return Semantics(
      label: isPinned ? '$name saved. Tap to remove.' : 'Save stop $name',
      button: true,
      child: Material(
        color: t.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppModel.shared.togglePin(widget.stopCode),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 20,
              color: isPinned ? t.soon : t.fg,
            ),
          ),
        ),
      ),
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
    final isLive =
        Freshness.from(ds.lastRefresh(widget.stopCode)) == Freshness.live;

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
        // Walk + dist row (left) + LIVE / freshness (right)
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
            // LIVE when the feed is live; otherwise the freshness label.
            if (isLive)
              Semantics(
                label: 'Live feed',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: t.soon, shape: BoxShape.circle),
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
              )
            else if (freshness != null)
              Text(freshness, style: t.mono(12, color: t.dim)),
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
          _arrivalsList(context, sorted),
        ],
      ],
    );
  }

  /// Section title above the grouped arrivals list. (LIVE moved up to the
  /// title block's walk/distance row.)
  Widget _sectionHeader(BuildContext context) {
    final t = context.t;
    return Text(
      'All arriving buses',
      style: t.sans(15, weight: FontWeight.w600, color: t.dim),
    );
  }

  // ── Arrivals list ─────────────────────────────────────────────────────────

  /// The grouped arrivals card: one row per service with hairline dividers,
  /// then a "Show more" expander past [_collapsedCount]. Mirrors iOS
  /// SoftStopView's "All arriving buses" list.
  Widget _arrivalsList(BuildContext context, List<Service> sorted) {
    final t = context.t;
    final canCollapse = sorted.length > _collapsedCount;
    final shown = (_expanded || !canCollapse)
        ? sorted
        : sorted.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.line, width: 1),
            ),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
                  _busRow(context, shown[i]),
                ],
                if (canCollapse) ...[
                  Divider(height: 1, thickness: 1, color: t.line),
                  _showMoreRow(context, sorted.length),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _footer(context),
      ],
    );
  }

  // ── Service row (inside the grouped card) ─────────────────────────────────
  //
  // badge · "To {dest}" · its next three arrival times in columns. The whole
  // row opens the bus view. No per-row bell (matches iOS SoftStopView); alert
  // management lives in the bus view's Notify button.

  Widget _busRow(BuildContext context, Service bus) {
    final t = context.t;
    final now = DateTime.now();
    final feed =
        Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed);
    final sec = _liveSec(bus, now);
    final badge = serviceBadgeColors(etaSec: sec, confidence: conf, t: t);
    final etas = _arrivalTimes(bus, now);

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}',
      hint: 'Opens bus ${bus.no}',
      button: true,
      child: InkWell(
        onTap: () => widget.onOpenBus(bus.no),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _coloredBadge(bus.no, badge.fill, badge.fg, t),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bus.dest.isEmpty ? 'Bus ${bus.no}' : 'To ${bus.dest}',
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _etaColumns(t, etas, conf),
            ],
          ),
        ),
      ),
    );
  }

  /// Up to three arrival columns ("Arr · 13 · 24 min") split by hairlines. The
  /// lead column carries proximity colour + a live signal; the rest are ink.
  Widget _etaColumns(LyneTheme t, List<int> etas, ArrivalConfidence conf) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < etas.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 30, color: t.line),
            const SizedBox(width: 10),
          ],
          _etaColumn(t, etas[i], lead: i == 0, conf: conf),
        ],
      ],
    );
  }

  Widget _etaColumn(LyneTheme t, int sec,
      {required bool lead, required ArrivalConfidence conf}) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    final color =
        lead ? etaColor(etaSec: sec, confidence: conf, t: t) : t.fg;
    final isGhost = conf == ArrivalConfidence.unconfirmed;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (isGhost)
                ExcludeSemantics(
                  child: Text('~',
                      style: t.mono(11,
                          weight: FontWeight.w400, color: t.faint)),
                ),
              Text(
                arriving ? 'Arr' : eta.big,
                style: t.mono(20, weight: FontWeight.w600, color: color),
              ),
              if (lead && arriving && conf == ArrivalConfidence.live) ...[
                const SizedBox(width: 1),
                ExcludeSemantics(
                  child: Transform.translate(
                    offset: const Offset(0, -7),
                    child: Icon(Icons.sensors, size: 9, color: t.soon),
                  ),
                ),
              ],
            ],
          ),
          Text(
            arriving ? 'now' : eta.small,
            style: t.mono(10, color: t.dim),
          ),
        ],
      ),
    );
  }

  /// "Show more" / "Show less" expander at the foot of the grouped card.
  Widget _showMoreRow(BuildContext context, int total) {
    final t = context.t;
    return Semantics(
      button: true,
      label: _expanded ? 'Show fewer buses' : 'Show all $total buses',
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(
                _expanded ? 'Show less' : 'Show more',
                style: t.sans(14, weight: FontWeight.w600, color: t.fg),
              ),
              const Spacer(),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: t.dim,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live seconds for a service — recomputed from arrivalDate for smoothness.
  int _liveSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  /// 1–3 upcoming arrival times (seconds) for a service, dropping any that
  /// aren't strictly later than the previous one.
  List<int> _arrivalTimes(Service s, DateTime now) {
    final first = _liveSec(s, now);
    final result = [first];
    int? second;
    if (s.followingDate != null) {
      second = s.followingDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    } else if (s.followingSec > first) {
      second = s.followingSec;
    }
    if (second != null && second > first) result.add(second);
    final third = s.thirdDate;
    if (third != null) {
      final sec = third.difference(now).inSeconds.clamp(0, 1 << 30);
      if (sec > result.last) result.add(sec);
    }
    return result;
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
