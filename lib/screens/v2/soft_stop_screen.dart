// SoftStopScreen — Leyne Stop detail (Material 3 Android variant).
//
// Layout mirrors the current iOS WhereSia spec, ios-native/Leyne/WhereSia/
// WSBusStopView.swift (Wave 2 restyle, 2026-07-11 — supersedes the earlier
// hand-rolled board that tracked a pre-restyle version of the same file):
//   • Top bar: circular back + bookmark (save/pin) — no sort menu. WhereSia
//     has no per-stop sort control; the board is always number-sorted.
//   • ONE rounded board card: large stop name, "● LIVE" (when loaded) +
//     code · ROAD · Updated h:mm meta head, a hairline divider, then the
//     departure rows — same card grammar as Home's BusStopCard. No section
//     header text before the rows (iOS goes straight from the meta head
//     into the service rows).
//   • No "MRT at this stop" interchange card any more — it duplicated the
//     interchange visible on Home/the map and read as a stray row under the
//     board (owner call, matches WSBusStopView.swift 2026-07-09 removal).
//   • Service rows reuse the shared [SoftDepartureRow] primitive
//     (showsVehicleIcons: true) — the neutral "Now" plate + edge tick
//     replaces the old blue "ARRIVING" capsule; Android stays monochrome
//     (colour only on the seat/crowd dot).
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
import '../../services/analytics_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/soft_departure_board.dart';
import '../../widgets/v2/soft_tab_bar.dart';

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
                  // ── "Watching" alerts (Android-only addition; sits above
                  //    the board, matching where it already lived) ────────
                  ..._activeAlertRows(context),
                  // ── One rounded board card: name + LIVE meta head +
                  //    departure rows — mirrors WSBusStopView's single
                  //    panel exactly (no separate title block, no
                  //    interchange card any more). ──────────────────────
                  SoftEntrance(child: _boardCard(context, state, sorted)),
                  // No inline MREC any more — the Stop screen's single ad is
                  // the anchored banner in [SoftDetailBottomBar], mirroring
                  // iOS's wsDetailAdBanner (owner placement redesign
                  // 2026-07-07: banner on high-dwell detail screens).
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────
  // Back · (spacer) · bookmark  — 44×44 circular icon buttons. Mirrors iOS
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
        // popup; a plain toggle). The bookmark fills when the stop is saved.
        _bookmarkButton(context, isPinned),
      ],
    );
  }

  /// Pin/unpin toggle. The bookmark fills when the stop is saved. Mirrors
  /// iOS WSBusStopView's trailing bookmark button (`togglePin`), which uses
  /// WSIcons' `.bookmark` / `.bookmarkFilled` glyph pair (not the star used
  /// elsewhere for per-bus favourites — see `_swipeNotify`).
  Widget _bookmarkButton(BuildContext context, bool isPinned) {
    final t = context.t;
    final name = DataStore.shared.stopName(widget.stopCode);
    // Save toggle — pins/unpins this stop. A bookmark glyph fills when
    // saved; to save a specific bus instead, open the bus and toggle its
    // (star-glyph) save there.
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
              isPinned
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
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

  // ── Board card ───────────────────────────────────────────────────────────
  //
  // One rounded panel — name + LIVE meta head, a hairline divider, then the
  // departure rows. Same card grammar as Home's BusStopCard, matching
  // WSBusStopView.swift's single `VStack` panel exactly (no separate title
  // block, no interchange card, no section header before the rows).

  Widget _boardCard(
    BuildContext context,
    ArrivalState? state,
    List<Service> sorted,
  ) {
    final t = context.t;
    final ds = DataStore.shared;
    // LIVE marks "arrivals have loaded", same as iOS's `case .loaded =
    // store.arrivals[code]` — it is not gated on feed recency (that's what
    // the per-row "~" confidence marker is for).
    final loaded = state != null && state.kind == ArrivalStateKind.loaded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large stop name
          Text(
            ds.stopName(widget.stopCode),
            style: t.sans(25, weight: FontWeight.w800, color: t.fg),
          ),
          const SizedBox(height: 8),
          // LIVE badge (when loaded) + "code · ROAD · Updated h:mm" — one
          // line, matching iOS's metaline exactly (no separate walk/distance
          // row; not part of the current WhereSia spec).
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
          const SizedBox(height: 16),
          const SoftRowDivider(),
          const SizedBox(height: 4),
          // No "Arrivals" header/sort-pill row: iOS goes straight from the
          // meta head into the service rows with no section label at all —
          // matches WSBusStopView exactly.
          if (state == null || state.kind == ArrivalStateKind.loading)
            _boardStateCard(context, 'Loading live arrivals…', loading: true)
          else if (state.kind == ArrivalStateKind.empty)
            _boardStateCard(
              context,
              'No live arrivals right now. The last bus may have gone.',
            )
          else if (state.kind == ArrivalStateKind.error)
            _boardStateCard(context, state.errorMessage ?? "Couldn't reach LTA")
          else
            _arrivalsList(context, sorted),
        ],
      ),
    );
  }

  /// The board content's loading/empty/error presentation — inline (no card
  /// chrome of its own; it already sits inside [_boardCard]'s panel).
  Widget _boardStateCard(
    BuildContext context,
    String message, {
    bool loading = false,
  }) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          if (loading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: t.dim),
            )
          else
            Icon(Icons.directions_bus_rounded, color: t.dim, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: t.sans(13, weight: FontWeight.w500, color: t.dim),
            ),
          ),
        ],
      ),
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

  /// The service rows: one [SoftDepartureRow] per bus (showsVehicleIcons:
  /// true — deck/wheelchair glyphs, mirrors iOS's `showsVehicleIcons`),
  /// split by hairline dividers, then a "Show more" expander past
  /// [_collapsedCount]. Mirrors iOS WSBusStopView's number-sorted service
  /// board, reusing the shared Wave 1 primitive instead of a hand-rolled
  /// row — its neutral "Now" plate + edge tick replaces the old blue
  /// "ARRIVING" capsule (Android stays monochrome).
  Widget _arrivalsList(BuildContext context, List<Service> sorted) {
    final canCollapse = sorted.length > _collapsedCount;
    final shown = (_expanded || !canCollapse)
        ? sorted
        : sorted.take(_collapsedCount).toList();

    // No mid-list MREC any more — this screen's single ad is the anchored
    // banner in [SoftDetailBottomBar] (owner placement redesign 2026-07-07).

    // SlidableAutoCloseBehavior: opening one row's Notify action closes any
    // other open one (shared 'arrivals' group tag).
    return SlidableAutoCloseBehavior(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SoftRowDivider(),
            _swipeNotify(
              context,
              shown[i],
              SoftDepartureRow(
                key: ValueKey(shown[i].no),
                service: shown[i],
                onTap: () => widget.onOpenBus(shown[i].no),
                showsVehicleIcons: true,
              ),
            ),
          ],
          if (canCollapse) ...[
            const SoftRowDivider(),
            _showMoreRow(context, sorted.length),
          ],
        ],
      ),
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
