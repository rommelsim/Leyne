// SoftStopScreen — Leyne Stop detail (Material 3 Android variant).
//
// Layout mirrors the current iOS WhereSia spec, ios-native/Leyne/WhereSia/
// WSBusStopView.swift (NOT the dormant V2/SoftStopView.swift predecessor
// this screen used to track):
//   • Top bar: circular back + star (save/pin) — no sort menu. WhereSia has
//     no per-stop sort control; the board is always number-sorted.
//   • Title block: large stop name, "● LIVE" (when loaded) + code · ROAD ·
//     Updated h:mm on one line. No walk/distance row (not in the iOS spec).
//   • No section header text before the arrivals list (iOS goes straight
//     from the interchange card into the service rows).
//   • Service rows: neutral (never accent-coloured) route tile · destination
//     + ETA on one line · deck/wheelchair/"then…"/crowd on a second line ·
//     trailing chevron. A monitored bus under a minute out swaps the ETA for
//     the solid accent "ARRIVING" capsule.
//
// All existing logic preserved: data loading, pin toggle, per-bus alerts
// (swipe actions — the Material-idiomatic equivalent of iOS's long-press
// context menu), notification banner, showAll/onSeeAll, refresh.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../data/alert_timing.dart';
import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/analytics_service.dart';
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

  /// This screen itself never shows a tab bar (pushed detail screens don't —
  /// see [SoftDetailBottomBar]); these are threaded through only so a further
  /// pushed screen (e.g. the interchange card's MRT station detail, or a Stop
  /// opened from it) can carry the tab the user originally came from. Null
  /// for deep-link contexts.
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftStopScreen> createState() => _SoftStopScreenState();
}

class _SoftStopScreenState extends State<SoftStopScreen>
    with WidgetsBindingObserver {
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
      // Pushed detail screen: no tab bar — iOS hides its floating tab bar on
      // push (WSRoot.swift: "detail screens are focused tasks with their own
      // chrome"). The ad banner still shows (Android's ad inventory is
      // independent of iOS's), stacked above the inline 300×250 MREC further
      // down the list — two ad slots on this screen by design.
      bottomNavigationBar: const SoftDetailBottomBar(),
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
                        'MRT AT THIS STOP',
                        style: t
                            .mono(9, color: t.dim)
                            .copyWith(letterSpacing: 0.6),
                      ),
                    ],
                  ),
                ),
                if (crowd != null) ...[
                  _miniGauge(_crowdFraction(crowd.level), t),
                  const SizedBox(width: 6),
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

  /// Gauge fill fraction — 34/67/100%, matching iOS `CrowdLevel.wsFraction`.
  double _crowdFraction(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.low:
        return 0.34;
      case CrowdLevel.moderate:
        return 0.67;
      case CrowdLevel.high:
        return 1.0;
      case CrowdLevel.unknown:
        return 0;
    }
  }

  /// A small neutral occupancy bar (never colour-coded — owner decision
  /// 2026-07-03) mirroring iOS's `WSChip`/`CrowdGauge`: a hairline track with
  /// a fg-coloured fill proportional to [fraction].
  Widget _miniGauge(double fraction, LyneTheme t) {
    return Container(
      width: 22,
      height: 5,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: t.line,
        borderRadius: BorderRadius.circular(99),
      ),
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0, 1),
        child: Container(
          decoration: BoxDecoration(
            color: t.fg,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
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
  // Back · (spacer) · star  — 44×44 circular icon buttons. Mirrors iOS
  // WSBusStopView's nav-bar back + bookmark trailing button, drawn in-content
  // (Flutter idiom) rather than as native chrome.

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
        // Pin/unpin this stop — matches iOS's bookmark toggle exactly (no
        // popup; a plain toggle). The star fills when the stop is saved.
        _starMenu(context, isPinned),
      ],
    );
  }

  /// Pin/unpin toggle. The star fills when the stop is saved. Mirrors iOS
  /// WSBusStopView's trailing bookmark button (`togglePin`).
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
          child: iconWidget ?? Icon(icon!, size: 20, color: t.fg),
        ),
      ),
    );
  }

  // ── Title block ──────────────────────────────────────────────────────────

  Widget _titleBlock(BuildContext context) {
    final t = context.t;
    final ds = DataStore.shared;
    final state = ds.arrivals[widget.stopCode];
    // LIVE marks "arrivals have loaded", same as iOS's `case .loaded =
    // store.arrivals[code]` — it is not gated on feed recency (that's what
    // the per-row "~" confidence marker is for).
    final loaded = state != null && state.kind == ArrivalStateKind.loaded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Large stop name
        Text(
          ds.stopName(widget.stopCode),
          style: t.sans(29, weight: FontWeight.w700, color: t.fg),
        ),
        const SizedBox(height: 6),
        // LIVE badge (when loaded) + "code · ROAD · Updated h:mm" — one line,
        // matching iOS's metaline exactly (no separate walk/distance row;
        // not part of the current WhereSia spec).
        Row(
          children: [
            if (loaded)
              Semantics(
                label: 'Live data',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.soon,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: t
                          .mono(10, weight: FontWeight.w700, color: t.soon)
                          .copyWith(letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 9),
                  ],
                ),
              ),
            Flexible(
              child: Text(
                _metaline(),
                style: t.mono(12, color: t.dim).copyWith(letterSpacing: 0.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "{code} · {ROAD} · Updated h:mm" — matches iOS WSBusStopView's
  /// `metaline` exactly (road omitted when unknown).
  String _metaline() {
    final ds = DataStore.shared;
    final road = ds.roadName(widget.stopCode);
    final parts = <String>[widget.stopCode];
    if (road.isNotEmpty) parts.add(road.toUpperCase());
    parts.add(_updatedLabel());
    return parts.join(' · ');
  }

  // ── Arrivals ───────────────────────────────────────────────────────────────

  // No "Arrivals" header/sort-pill row: iOS goes straight from the title
  // block (or interchange card) into the service rows with no section
  // label at all — matches WSBusStopView exactly.
  Widget _arrivalSection(
    BuildContext context,
    ArrivalState? state,
    List<Service> sorted,
    bool isPinned,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state == null || state.kind == ArrivalStateKind.loading)
          _emptyCard(context, 'Loading live arrivals…', loading: true)
        else if (state.kind == ArrivalStateKind.empty)
          _emptyCard(
            context,
            'No live arrivals right now. The last bus may have gone.',
          )
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
        .where(
          (a) => a.kind == AlertKind.arrival && a.stopCode == widget.stopCode,
        )
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
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Bus ${mine[i].busNo}',
                              style: t.sans(
                                14,
                                weight: FontWeight.w700,
                                color: t.fg,
                              ),
                            ),
                            if (mine[i].dest.isNotEmpty)
                              TextSpan(
                                text: '  ·  To ${mine[i].dest}',
                                style: t.sans(13, color: t.dim),
                              ),
                          ],
                        ),
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

  // ── Arrivals list ─────────────────────────────────────────────────────────

  /// The grouped arrivals card: one row per service with hairline dividers,
  /// then a "Show more" expander past [_collapsedCount]. Mirrors iOS
  /// WSBusStopView's number-sorted service board.
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
            _arrivalsCard(
              context,
              shown.sublist(0, shown.length ~/ 2),
              canCollapse: false,
              total: sorted.length,
            ),
            const MediumRectAd(),
            const SizedBox(height: 16),
            _arrivalsCard(
              context,
              shown.sublist(shown.length ~/ 2),
              canCollapse: canCollapse,
              total: sorted.length,
            ),
          ] else
            _arrivalsCard(
              context,
              shown,
              canCollapse: canCollapse,
              total: sorted.length,
            ),
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
  // Neutral route tile · destination + ETA on one line · deck/wheelchair/
  // "then…"/crowd on a second line · trailing chevron. The whole row opens
  // the bus view. No per-row bell (matches iOS WSBusStopView); alert
  // management is a swipe action here (the Material-idiomatic stand-in for
  // iOS's long-press context menu).

  Widget _busRow(BuildContext context, Service bus) {
    final t = context.t;
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed);
    final etas = _arrivalTimes(bus, now);
    final leadSec = etas.first;
    final later = etas.skip(1).map((s) => fmtEta(s).big).toList();
    // The blue "pulling in" mark — reserved for a monitored arrival under a
    // minute out. Matches iOS exactly: gated on `svc.monitored` only, not on
    // feed recency (a monitored bus stays "arriving" even if the stop's feed
    // itself has gone briefly stale). Static (no pulsing — owner-flagged as
    // distracting on iOS; the capsule + row wash carry it instead).
    final arrivingNow = bus.monitored && fmtEta(leadSec).big == 'Arr';

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}',
      hint: arrivingNow
          ? 'Bus ${bus.no} is arriving now'
          : 'Opens bus ${bus.no}',
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
              // Neutral tile — never colour-coded; only MRT line pills and
              // the accent-only ARRIVING capsule carry colour on this screen.
              _routeTile(bus.no, t),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Destination ⟷ ETA share one line (iOS parity): a
                    // stacked "big number over unit" column here would put
                    // the ETA visibly above the destination instead of
                    // beside it.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            bus.dest.isEmpty ? 'Bus ${bus.no}' : bus.dest,
                            style: t.sans(
                              15,
                              weight: FontWeight.w700,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (arrivingNow)
                          _arrivingCapsule(t)
                        else
                          _leadEta(t, leadSec, conf),
                      ],
                    ),
                    _secondLine(t, bus, later),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }

  /// Second line under the destination: deck/wheelchair attrs · "then 12 ·
  /// 24 min" (later arrivals, omitted when there are none) · crowd meter
  /// trailing. Omitted entirely when there's nothing to show, so
  /// schedule-only ghost rows stay single-line.
  Widget _secondLine(LyneTheme t, Service bus, List<String> later) {
    // Deck/wheelchair are static bus attributes, known regardless of live
    // GPS — iOS shows them unconditionally, so no sched/monitored gate here.
    final showAttrs = bus.wab || bus.deck != Deck.sd;
    final showThen = later.isNotEmpty;
    // Crowd only for a confirmed (non-schedule-only) arrival — mirrors iOS
    // WSBusStopView's `!sched` gate on the crowd gauge.
    final showCrowd = bus.monitored;
    if (!showAttrs && !showThen && !showCrowd) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          if (showAttrs) _serviceAttrs(t, bus),
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
          // Short word (Seats/Standing/Limited) matches iOS Load.wsWord —
          // the row is already dense with attrs/"then"/crowd on one line.
          if (showCrowd) CrowdMeter(load: bus.load, compact: true),
        ],
      ),
    );
  }

  /// Solid accent "ARRIVING" capsule — the sanctioned live-accent exception,
  /// shown in place of the ETA when the lead bus is under a minute out and
  /// monitored by GPS.
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

  /// The ETA, inline on the destination's baseline: "~12 min" for a
  /// scheduled/ghost bus, "12 min" for a monitored one, "Arr" alone with no
  /// suffix. The "~" depends only on whether the bus is monitored — never on
  /// feed staleness — and the numeral itself always stays full-ink
  /// (timeliness is the promise — see feedback_timely_over_honest). Matches
  /// iOS's inline `Text(sched ? "~" : "") + eta.big + " min"` exactly.
  Widget _leadEta(LyneTheme t, int sec, ArrivalConfidence conf) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    final sched = conf == ArrivalConfidence.unconfirmed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (sched)
          Text(
            '~',
            style: t.mono(15, weight: FontWeight.w600, color: t.dim),
          ),
        Text(
          eta.big,
          style: t.mono(19, weight: FontWeight.w700, color: t.fg),
        ),
        if (!arriving)
          Text(
            ' min',
            style: t.mono(11, weight: FontWeight.w600, color: t.dim),
          ),
      ],
    );
  }

  /// Small inline row of service attribute chips: deck type when it's not
  /// plain single-deck, then wheelchair (WAB) — iOS's icon order. Colour is
  /// dim/faint so it never competes with the ETA.
  Widget _serviceAttrs(LyneTheme t, Service bus) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bus.deck != Deck.sd)
          Text(
            bus.deck == Deck.dd ? 'Double-deck' : 'Bendy',
            style: t.mono(10, color: t.faint),
          ),
        if (bus.deck != Deck.sd && bus.wab) const SizedBox(width: 5),
        if (bus.wab)
          Semantics(
            label: 'Wheelchair accessible',
            excludeSemantics: true,
            child: Icon(Icons.accessible_rounded, size: 13, color: t.dim),
          ),
      ],
    );
  }

  /// Wrap a bus row so swiping it RIGHT reveals Notify/Stop + Save actions
  /// (replaces the old side bell). Tapping the row still opens the bus; the
  /// swipe arms/removes the arrival alert or favourites the service at this
  /// stop in one gesture, with an Undo snackbar for the alert.
  Widget _swipeNotify(BuildContext context, Service bus, Widget child) {
    final t = context.t;
    final on =
        AppModel.shared.alertFor(
          kind: AlertKind.arrival,
          busNo: bus.no,
          stopCode: widget.stopCode,
        ) !=
        null;
    final favOn = AppModel.shared.isFavService(
      no: bus.no,
      stop: widget.stopCode,
    );
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
            onPressed: (_) => AppModel.shared.toggleFavService(
              no: bus.no,
              stop: widget.stopCode,
            ),
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

  // ── Route tile ─────────────────────────────────────────────────────────────
  // Neutral, bordered, monospaced — matches iOS's `RouteTile(size: .large)`.
  // Bus route numbers are NEVER colour-filled; colour is reserved for MRT
  // line pills and the accent-only ARRIVING capsule.

  Widget _routeTile(String svc, LyneTheme t) {
    return Container(
      width: 46,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Text(
        svc,
        style: t.mono(16, weight: FontWeight.w700, color: t.fg),
        maxLines: 1,
      ),
    );
  }

  // ── Empty / loading / error card ──────────────────────────────────────────
  // One shared presentation for all three non-loaded states, so they read as
  // one system rather than a bare spinner for loading and a bordered card
  // for empty/error. Copy for the empty state matches iOS WSBusStopView's
  // "No live arrivals right now. The last bus may have gone." exactly; the
  // spinner-in-a-card is the Material-idiomatic stand-in for iOS's plain
  // "Loading live arrivals…" text row.
  Widget _emptyCard(
    BuildContext context,
    String message, {
    bool loading = false,
  }) {
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
          if (loading)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: t.dim),
            )
          else
            Icon(Icons.directions_bus_rounded, color: t.dim, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: t.sans(14, color: t.fg)),
          ),
        ],
      ),
    );
  }

  // No footer: the title block's LIVE badge/"Updated h:mm" metaline already
  // carries provenance, and users don't care where the data comes from
  // (owner, 2026-07-02) — matches iOS WSBusStopView, which dropped its
  // legend/disclaimer for the same reason.

  // ── Sort helper ────────────────────────────────────────────────────────────
  //
  // Always number-sorted — matches iOS WSBusStopView, which has no sort
  // control at all: "one glanceable line per service (number-sorted so the
  // board is scannable)". The old ETA/distance sort menu was a dormant-V2
  // holdover and has been removed.

  List<Service> _sortServices(List<Service> services) {
    final out = [...services];
    // Natural order: 2 < 10 < 53 < 53M < 98A < NR7 (letter-prefixed night
    // services last) — a plain digit-strip put "NR7" in the 7s.
    out.sort((a, b) => naturalCompare(a.no, b.no));
    return out;
  }

  // ── Updated-at label ───────────────────────────────────────────────────────

  /// "Updated 9:41" — an absolute clock stamp honouring the 24h preference,
  /// matching iOS's `WSFmt.upd`. Replaces the old relative "Updated Ns ago"
  /// wording, which needed to keep re-rendering to stay accurate.
  String _updatedLabel() {
    final last = DataStore.shared.lastRefresh(widget.stopCode);
    if (last == null) return 'Updated —';
    final hhmm =
        '${last.hour.toString().padLeft(2, '0')}'
        '${last.minute.toString().padLeft(2, '0')}';
    return 'Updated ${fmtClock(hhmm, use24h: AppModel.shared.use24h)}';
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
    final on = AppModel.shared.isTracked(code: widget.stopCode, busNo: busNo);
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
