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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../data/alert_timing.dart';
import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/analytics_service.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_mrt_station_screen.dart';

class SoftStopScreen extends StatefulWidget {
  const SoftStopScreen({
    super.key,
    required this.stopCode,
    required this.onBack,
    required this.onOpenBus,
    required this.onSeeAll,
    this.showAll = false,
    this.onTab,
    this.tabSelection,
  });
  final String stopCode;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenBus;
  final VoidCallback onSeeAll;
  final bool showAll;

  /// When provided, the tab bar stays visible on this pushed detail page so the
  /// user can switch tabs without backing out. [tabSelection] is the tab the
  /// page was opened from (kept highlighted). Null for deep-link contexts.
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftStopScreen> createState() => _SoftStopScreenState();
}

class _SoftStopScreenState extends State<SoftStopScreen>
    with WidgetsBindingObserver {
  // Default to bus-number order so a stop's services read like a roster
  // (2, 10, 53, 53M, 98A, NR7) rather than reshuffling on every ETA tick.
  // Matches iOS SoftStopView. ETA / distance remain in the sort menu.
  _StopSort _sort = _StopSort.busNo;

  /// Inline expand state for the grouped arrivals list. Opened from a
  /// "see all" entry (widget.showAll) starts expanded.
  late bool _expanded = widget.showAll;

  /// Services shown before the "Show more" expander kicks in.
  static const int _collapsedCount = 6;

  /// Keeps THIS stop's arrivals live while the screen is open. The global
  /// tick only refreshes pinned/alerted stops, so an open unpinned stop was
  /// never re-fetched (stale until pull-to-refresh — owner-reported on iOS;
  /// same gap here). ensureArrivals is freshness-gated (~25s) and deduped
  /// internally, so a 5s cadence is cheap.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
    });
    AnalyticsService.stopViewed(code: widget.stopCode, kind: StopKind.bus);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from background: timers were suspended with the isolate, so
    // the arrivals can be minutes old — refetch immediately.
    if (state == AppLifecycleState.resumed) {
      DataStore.shared.refreshArrivals(widget.stopCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      // Bare tab bar (no anchored banner): the Stop screen carries its ad as an
      // inline 300×250 MREC below the arrivals instead, so exactly one ad shows
      // here — iOS parity (SoftRoot omits the bottom gutter for `.stop`).
      bottomNavigationBar:
          (widget.onTab != null && widget.tabSelection != null)
              ? SoftTabBar(
                  selection: widget.tabSelection!, onSelect: widget.onTab!)
              : null,
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
                  const SizedBox(height: 20),
                  // ── MRT interchange card (stops at a station) ──────────
                  ..._interchangeCard(context),
                  // ── Arrivals section ────────────────────────────────────
                  _arrivalSection(context, state, sorted, isPinned),
                  // ── Inline 300×250 MREC ─────────────────────────────────
                  // Normal view: a single ad at the end of the content. The
                  // full "See all" view instead drops one ad mid-list (in
                  // _arrivalsList) so the long list carries exactly one ad too.
                  if (!widget.showAll) const MediumRectAd(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── MRT interchange card ────────────────────────────────────────────────
  // When the stop's name resolves to an MRT station ("Farrer Rd Stn Exit A"
  // → Farrer Road), a compact card links straight into that station's detail
  // (crowd, forecast, disruptions). Feature parity with iOS's interchange
  // card on the WhereSia Bus Stop screen.

  List<Widget> _interchangeCard(BuildContext context) {
    final t = context.t;
    final stopName = DataStore.shared.stopName(widget.stopCode);
    final resolved = resolveMrtStation(stopName);
    if (resolved == null) return const [];
    // The detail screen needs the geo record (lat/lon for its nearby-stops
    // section) — match the resolved display name against the geo dataset.
    final geoMatches = MrtGeo.all.where(
      (s) => s.name.toLowerCase() == resolved.name.toLowerCase(),
    );
    if (geoMatches.isEmpty) return const [];
    final station = geoMatches.first;
    final crowd = _interchangeCrowd(station, resolved.codes);
    return [
      Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SoftMrtStationScreen(
                  station: station,
                  onBack: () => Navigator.of(context).pop(),
                  onTab: widget.onTab ?? (_) {},
                  tabSelection: widget.tabSelection ?? SoftTab.home,
                  onOpenStop: (code) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SoftStopScreen(
                          stopCode: code,
                          onBack: () => Navigator.of(context).pop(),
                          onOpenBus: widget.onOpenBus,
                          onSeeAll: () {},
                          onTab: widget.onTab,
                          tabSelection: widget.tabSelection,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Wrap(
                  spacing: 4,
                  children: resolved.codes.take(3).map((c) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.color,
                        borderRadius: BorderRadius.circular(LyneRadius.full),
                      ),
                      child: Text(
                        c.code,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolved.name,
                        style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'MRT at this stop',
                        style: t.mono(10, color: t.dim),
                      ),
                    ],
                  ),
                ),
                if (crowd != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _crowdDotColor(crowd.level, t),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _crowdLevelLabel(crowd.level),
                    style: t.mono(11, weight: FontWeight.w600, color: t.fg),
                  ),
                  const SizedBox(width: 10),
                ],
                Icon(Icons.chevron_right_rounded, color: t.dim),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  /// This station's live crowd reading, looked up from [DataStore.crowdByLine]
  /// via the interchange's first line code — mirrors iOS SoftStopView's
  /// `store.wsCrowd(for: station)`. Null when the line isn't tracked or no
  /// reading has landed yet; the `.unknown` level is also treated as "no
  /// reading" (iOS excludes it from the chip too).
  StationCrowd? _interchangeCrowd(MrtGeoStation station, List<MrtCode> codes) {
    if (codes.isEmpty) return null;
    final line = _lineFromStationCode(codes.first.code);
    if (line == null) return null;
    final list = DataStore.shared.crowdByLine[line];
    if (list == null) return null;
    StationCrowd? match;
    for (final entry in list) {
      for (final code in station.codes) {
        if (entry.code.toUpperCase() == code.toUpperCase()) {
          match = entry;
          break;
        }
      }
      if (match != null) break;
    }
    if (match == null || match.level == CrowdLevel.unknown) return null;
    return match;
  }

  /// Two-letter station-code prefix → [MRTLine]. Mirrors the private
  /// `_lineFromCode` in SoftMrtStationScreen (kept local since that one
  /// isn't exported).
  static MRTLine? _lineFromStationCode(String code) {
    if (code.length < 2) return null;
    switch (code.substring(0, 2).toUpperCase()) {
      case 'EW':
      case 'CG':
        return MRTLine.ew;
      case 'NS':
        return MRTLine.ns;
      case 'NE':
        return MRTLine.ne;
      case 'CC':
      case 'CE':
        return MRTLine.cc;
      case 'DT':
        return MRTLine.dt;
      case 'TE':
        return MRTLine.te;
      default:
        return null;
    }
  }

  /// Crowd dot colour — NEUTRAL ink (owner decision 2026-07-03, iOS
  /// WhereSia rule: crowd is never colour-coded; the word carries it).
  Color _crowdDotColor(CrowdLevel level, LyneTheme t) {
    return level == CrowdLevel.unknown ? t.faint : t.fg;
  }

  String _crowdLevelLabel(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.low:
        return 'Low';
      case CrowdLevel.moderate:
        return 'Moderate';
      case CrowdLevel.high:
        return 'High';
      case CrowdLevel.unknown:
        return 'Unknown';
    }
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
            icon: Icons.arrow_back_rounded,
            onTap: widget.onBack,
          ),
        ),
        const Spacer(),
        // Star menu — pin/unpin this stop or save a specific bus here,
        // without leaving the page (replaces the old save-sheet-only flow).
        _starMenu(context, isPinned),
        // Sort moved out of the top bar into a visible pill above the list.
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
              isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
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
  /// A visible pill (current order + swap icon), sitting above the list — moved
  /// out of the top-bar overflow so sorting is one easy tap.
  Widget _sortPill(BuildContext context) {
    final t = context.t;
    return Semantics(
      label: 'Sort arrivals',
      button: true,
      child: PopupMenuButton<_StopSort>(
        tooltip: 'Sort arrivals',
        padding: EdgeInsets.zero,
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: t.line, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert_rounded, size: 15, color: t.fg),
              const SizedBox(width: 5),
              Text(_sortLabel,
                  style: t.sans(13, weight: FontWeight.w600, color: t.fg)),
            ],
          ),
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
          ..._activeAlertRows(context),
          _arrivalsList(context, sorted),
        ],
      ],
    );
  }

  /// "Watching" section — the buses at this stop the user is being notified
  /// about. One row each: bus + destination, with a ✕ to stop watching (Undo
  /// snackbar). The fixed "3 & 1 min" timing isn't repeated per row (it's the
  /// same for every alert); the eyebrow says it once.
  List<Widget> _activeAlertRows(BuildContext context) {
    final t = context.t;
    final mine = AppModel.shared.alerts
        .where((a) =>
            a.kind == AlertKind.arrival && a.stopCode == widget.stopCode)
        .toList();
    if (mine.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          children: [
            Text(
              'WATCHING',
              style: t
                  .mono(11, weight: FontWeight.w700, color: t.soon)
                  .copyWith(letterSpacing: 1.2),
            ),
            const SizedBox(width: 8),
            Text(
              'alerted 3 & 1 min before',
              style: t.mono(10, color: t.dim).copyWith(letterSpacing: 0.2),
            ),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: t.soonBg,
          borderRadius: BorderRadius.circular(LyneRadius.md),
        ),
        child: Column(
          children: [
            for (var i = 0; i < mine.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Icon(Icons.visibility_rounded, size: 18, color: t.soon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: 'Bus ${mine[i].busNo}',
                            style: t.sans(14,
                                weight: FontWeight.w700, color: t.fg),
                          ),
                          if (mine[i].dest.isNotEmpty)
                            TextSpan(
                              text: '  ·  To ${mine[i].dest}',
                              style: t.sans(13, color: t.dim),
                            ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Row exists only while the alert does, so a toggle is
                    // meaningless (off → vanishes). ✕ stops watching, with Undo.
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Stop watching Bus ${mine[i].busNo}',
                      icon: Icon(Icons.close_rounded, size: 20, color: t.dim),
                      onPressed: () => toggleArrivalAlert(
                        busNo: mine[i].busNo,
                        stopCode: mine[i].stopCode,
                        stopName: mine[i].stopName,
                        dest: mine[i].dest,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Section title above the grouped arrivals list. (LIVE moved up to the
  /// title block's walk/distance row.)
  Widget _sectionHeader(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Text(
          'Arrivals',
          style: t.sans(15, weight: FontWeight.w600, color: t.dim),
        ),
        const Spacer(),
        _sortPill(context),
      ],
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _StopSort.arrival:
        return 'ETA';
      case _StopSort.busNo:
        return 'Bus no.';
      case _StopSort.distance:
        return 'Distance';
    }
  }

  // ── Arrivals list ─────────────────────────────────────────────────────────

  /// The grouped arrivals card: one row per service with hairline dividers,
  /// then a "Show more" expander past [_collapsedCount]. Mirrors iOS
  /// SoftStopView's "All arriving buses" list.
  Widget _arrivalsList(BuildContext context, List<Service> sorted) {
    final canCollapse = sorted.length > _collapsedCount;
    final shown = (_expanded || !canCollapse)
        ? sorted
        : sorted.take(_collapsedCount).toList();

    // Full "See all" view: drop ONE inline ad at the list's midpoint so it
    // rides along with content the user is actively scrolling, rather than
    // stacking another at the bottom. Only worth splitting once there are
    // enough rows. The normal view keeps its single bottom MREC instead.
    final injectAd = widget.showAll && shown.length >= 6;

    // SlidableAutoCloseBehavior: opening one row's Notify action closes any
    // other open one (shared 'arrivals' group tag).
    return SlidableAutoCloseBehavior(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (injectAd) ...[
            _arrivalsCard(context, shown.sublist(0, shown.length ~/ 2),
                canCollapse: false, total: sorted.length),
            const MediumRectAd(),
            const SizedBox(height: 16),
            _arrivalsCard(context, shown.sublist(shown.length ~/ 2),
                canCollapse: canCollapse, total: sorted.length),
          ] else
            _arrivalsCard(context, shown,
                canCollapse: canCollapse, total: sorted.length),
        ],
      ),
    );
  }

  /// One grouped arrivals card: a row per service split by hairline dividers,
  /// plus the "Show more" expander when [canCollapse]. Pulled out of
  /// [_arrivalsList] so the full view can render two cards with an ad between.
  Widget _arrivalsCard(
    BuildContext context,
    List<Service> rows, {
    required bool canCollapse,
    required int total,
  }) {
    final t = context.t;
    return Material(
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
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
              _swipeNotify(context, rows[i], _busRow(context, rows[i])),
            ],
            if (canCollapse) ...[
              Divider(height: 1, thickness: 1, color: t.line),
              _showMoreRow(context, total),
            ],
          ],
        ),
      ),
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
    final etas = _arrivalTimes(bus, now);
    final leadSec = etas.first;
    final later = etas.skip(1).map((s) => fmtEta(s).big).toList();
    // The blue "pulling in" mark — reserved for a GPS-confirmed arrival
    // under a minute out. Static (no pulsing — owner-flagged as distracting
    // on iOS; the capsule + row wash carry it instead).
    final arrivingNow =
        fmtEta(leadSec).big == 'Arr' && conf == ArrivalConfidence.live;

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}',
      hint: 'Opens bus ${bus.no}',
      button: true,
      child: InkWell(
        onTap: () => widget.onOpenBus(bus.no),
        child: Container(
          // Margin + padding together always sum to the original 16/14 inset
          // so non-arriving rows stay pixel-identical; only the fill colour
          // changes. Keeps every row the same height (no divider jitter) and
          // keeps the highlight inset from the card's own rounded edges
          // rather than bleeding full-width (owner-flagged on iOS).
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: arrivingNow
                ? t.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // Badge keeps its standard look — proximity is not colour-coded.
              _coloredBadge(bus.no, t),
              const SizedBox(width: 12),
              // Destination is the flexible element: it wraps to two lines
              // before truncating so "To Kampong Bahru Ter" reads in full.
              // The badge and lead ETA keep their intrinsic width.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bus.dest.isEmpty ? 'Bus ${bus.no}' : 'To ${bus.dest}',
                      style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _secondLine(t, bus, conf, later),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ONE big next-bus ETA (iOS parity) instead of the old
              // three-column ETA wall; later arrivals move to the quiet
              // "then …" line above. Arriving swaps in a solid capsule.
              if (arrivingNow)
                _arrivingCapsule(t)
              else
                _leadEta(t, leadSec, conf),
            ],
          ),
        ),
      ),
    );
  }

  /// Second line under the destination: WAB/deck attrs · "then 12 · 24 min"
  /// (later arrivals, omitted when there are none) · crowd meter trailing.
  /// Omitted entirely when there's nothing to show, so schedule-only ghost
  /// rows stay single-line.
  Widget _secondLine(
    LyneTheme t,
    Service bus,
    ArrivalConfidence conf,
    List<String> later,
  ) {
    final showAttrs =
        _showServiceAttrs(conf) && (bus.wab || bus.deck != Deck.sd);
    final showThen = later.isNotEmpty;
    // Crowd only for a confirmed (non-schedule-only) arrival — mirrors iOS
    // SoftStopView's `!sched` gate on the crowd gauge.
    final showCrowd = bus.monitored;
    if (!showAttrs && !showThen && !showCrowd) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          if (showAttrs) _serviceAttrs(t, bus, conf),
          if (showAttrs && showThen) const SizedBox(width: 8),
          if (showThen)
            Flexible(
              child: Text(
                'then ${later.join(' · ')} min',
                style: t.mono(11, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(),
          if (showCrowd) CrowdMeter(load: bus.load),
        ],
      ),
    );
  }

  /// Solid accent "ARRIVING" capsule — the sanctioned live-accent exception,
  /// shown in place of the big ETA when the lead bus is under a minute out
  /// with a live GPS fix.
  Widget _arrivingCapsule(LyneTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'ARRIVING',
        style: t
            .mono(11, weight: FontWeight.w700, color: Colors.white)
            .copyWith(letterSpacing: 0.8),
      ),
    );
  }

  /// The one big next-bus ETA. Scheduled/aged arrivals carry the
  /// whisper-quiet "~" prefix; the numeral itself always stays full-ink
  /// (timeliness is the promise — see feedback_timely_over_honest).
  Widget _leadEta(LyneTheme t, int sec, ArrivalConfidence conf) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (!arriving && conf != ArrivalConfidence.live)
              Text('~', style: t.mono(14, color: t.dim)),
            Text(
              arriving ? 'Arr' : eta.big,
              style: t.mono(20, weight: FontWeight.w600, color: t.fg),
            ),
          ],
        ),
        Text(arriving ? 'now' : eta.small, style: t.mono(10, color: t.dim)),
      ],
    );
  }

  /// Whether to surface WAB / deck attributes. Only for confirmed arrivals —
  /// timetable-only ghost buses don't carry reliable per-trip attributes.
  bool _showServiceAttrs(ArrivalConfidence conf) =>
      conf == ArrivalConfidence.live || conf == ArrivalConfidence.stale;

  /// Small inline row of service attribute chips: wheelchair (WAB) and
  /// deck type when it's not plain single-deck. Colour is dim so it never
  /// competes with the ETA. Shown only when [_showServiceAttrs] is true.
  Widget _serviceAttrs(LyneTheme t, Service bus, ArrivalConfidence conf) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bus.wab) ...[
          Semantics(
            label: 'Wheelchair accessible',
            excludeSemantics: true,
            child: Icon(Icons.accessible_rounded, size: 13, color: t.dim),
          ),
        ],
        if (bus.wab && bus.deck != Deck.sd) const SizedBox(width: 5),
        if (bus.deck != Deck.sd) ...[
          Text(
            bus.deck == Deck.dd ? 'Double-deck' : 'Bendy',
            style: t.mono(10, color: t.faint),
          ),
        ],
      ],
    );
  }

  /// Wrap a bus row so swiping it RIGHT reveals Notify/Stop + Save actions
  /// (replaces the old side bell). Tapping the row still opens the bus; the
  /// swipe arms/removes the arrival alert or favourites the service at this
  /// stop in one gesture, with an Undo snackbar for the alert.
  Widget _swipeNotify(BuildContext context, Service bus, Widget child) {
    final t = context.t;
    final on = AppModel.shared.alertFor(
          kind: AlertKind.arrival,
          busNo: bus.no,
          stopCode: widget.stopCode,
        ) !=
        null;
    final favOn =
        AppModel.shared.isFavService(no: bus.no, stop: widget.stopCode);
    return Slidable(
      key: ValueKey('notify-${bus.no}'),
      groupTag: 'arrivals',
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.55,
        children: [
          SlidableAction(
            onPressed: (_) => toggleArrivalAlert(
              busNo: bus.no,
              stopCode: widget.stopCode,
              stopName: DataStore.shared.stopName(widget.stopCode),
              dest: bus.dest,
            ),
            backgroundColor: on ? t.surfaceHi : t.soon,
            foregroundColor: on ? t.fg : t.onAccent,
            icon: on ? Icons.visibility_off : Icons.visibility_rounded,
            label: on ? 'Stop' : 'Notify',
          ),
          SlidableAction(
            onPressed: (_) => AppModel.shared
                .toggleFavService(no: bus.no, stop: widget.stopCode),
            backgroundColor: favOn ? t.surfaceHi : t.accent,
            foregroundColor: favOn ? t.fg : t.onAccent,
            icon: favOn ? Icons.star_rounded : Icons.star_outline_rounded,
            label: favOn ? 'Saved' : 'Save',
          ),
        ],
      ),
      child: child,
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

  Widget _coloredBadge(String svc, LyneTheme t) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(14), // ServiceBadgeSize.md.radius
      ),
      child: Text(svc,
          style: t.sans(18, weight: FontWeight.w600, color: t.onAccent)),
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

  // No footer: the title block's LIVE/"Updated" freshness label already
  // carries provenance, and users don't care where the data comes from
  // (owner, 2026-07-02) — matches iOS SoftStopView, which dropped its
  // legend/disclaimer for the same reason.

  // ── Sort & distance helpers (unchanged logic) ─────────────────────────────

  List<Service> _sortServices(List<Service> services) {
    final out = [...services];
    switch (_sort) {
      case _StopSort.arrival:
        out.sort((a, b) => a.etaSec.compareTo(b.etaSec));
      case _StopSort.distance:
        out.sort((a, b) => _busDistance(a).compareTo(_busDistance(b)));
      case _StopSort.busNo:
        // Natural order: 2 < 10 < 53 < 53M < 98A < NR7 (letter-prefixed night
        // services last) — the old digit-strip put "NR7" in the 7s.
        out.sort((a, b) => naturalCompare(a.no, b.no));
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
