// SoftStopScreen — Leyne Stop detail (Material 3 Android variant).
//
// Layout mirrors the current iOS WhereSia spec, ios-native/Leyne/WhereSia/
// WSBusStopView.swift (NOT the dormant V2/SoftStopView.swift predecessor
// this screen used to track):
//   • Top bar: circular back + bookmark (save/pin) — no sort menu. WhereSia
//     has no per-stop sort control; the board is always number-sorted.
//   • Title block: large stop name, "● LIVE" (when loaded) + code · ROAD ·
//     Updated h:mm on one line. No walk/distance row (not in the iOS spec).
//   • "All services" section header, then EVERY service (including the
//     soonest) as one row each — no hero card, no "Show more" collapse.
//   • Service rows: 58pt service tile · "to <dest>" + crowd word · a
//     right-aligned ETA column ("12 min", or "Now" in chipInk when the bus is
//     pulling in). Tapping a row opens that bus's BOTTOM SHEET — the old
//     always-visible hero card, moved (iOS 2026-07-26): the departure board
//     was good, it just shouldn't have sat at the top permanently promoting
//     one service.
//
// All existing logic preserved: data loading, pin toggle, per-bus alerts
// (swipe action — the Material-idiomatic equivalent of iOS's row swipe),
// route timeline, refresh.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../../theme/soft_blue.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_mrt_station_screen.dart';

class SoftStopScreen extends StatefulWidget {
  const SoftStopScreen({
    super.key,
    required this.stopCode,
    required this.onBack,
    this.initialService,
    this.onTab,
    this.tabSelection,
  });
  final String stopCode;
  final VoidCallback onBack;

  /// Vestigial. The list shows EVERY service now (iOS 2026-07-26 — the
  /// "Show more" collapse and the separate see-all screen are both gone), so
  /// neither of these does anything; they're kept on the constructor only so
  /// the existing call sites (main.dart, soft_root.dart, deep_link_service)
  /// keep compiling. Delete them there first, then here.

  /// Opens this service's detail sheet as soon as the first load lands.
  /// Mirrors iOS `WSBusStopView.initialService`: notification / widget deep
  /// links and saved LINES land on the stop with their own bus already open,
  /// rather than a separate Track Bus screen (retired on both platforms).
  final String? initialService;

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
  /// "View route" disclosure inside the open service sheet.
  bool _routeExpanded = false;

  /// Rebuilds the OPEN service sheet. `showModalBottomSheet` builds its
  /// content in its own element tree, so this screen's `setState` never
  /// reaches it — route loads and route-toggle state have to poke it
  /// directly. Null whenever no sheet is open.
  VoidCallback? _sheetRebuild;

  /// [SoftStopScreen.initialService] is honoured once, on the first loaded
  /// frame — mirrors iOS `seededInitial`.
  bool _seededInitial = false;

  /// Reveals every stop back to the route's origin, not just the segment
  /// from the bus's live position — mirrors iOS `showPreviousStops`.
  bool _showPreviousStops = false;
  RouteInfo? _routeInfo;
  String? _routeLoadedFor;

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
            if (loaded) _seedInitialService(context, sorted);
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
                  // ── Arrivals section ────────────────────────────────────
                  // No hero card here any more (iOS 2026-07-26): the gradient
                  // "featured bus" board moved into the sheet a row tap
                  // opens, so the screen goes header → All services, and the
                  // soonest bus is a row like every other one.
                  _arrivalSection(context, state, sorted),
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

  // ── Service sheet ───────────────────────────────────────────────────────
  // ONE bus, in depth — the sheet a row tap opens. This is the old hero
  // card's departure board, MOVED rather than lost (iOS 2026-07-26): the
  // board itself was good, it just shouldn't have been sitting at the top of
  // the screen permanently promoting one service. As a bottom sheet it
  // appears only when asked for, keeps the list underneath in place, and is
  // dismissed by the drag every user already knows.

  /// Mutates screen state AND rebuilds the open sheet. The sheet lives in the
  /// modal route's own element tree, so plain `setState` leaves it stale.
  void _setStateEverywhere(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
    _sheetRebuild?.call();
  }

  /// Deep links / widget + notification taps land on the stop with their bus
  /// already open (mirrors iOS `seededInitial`). Runs once, on the first
  /// frame where the arrivals are loaded — the service has to exist in the
  /// feed before there's a sheet to show for it.
  void _seedInitialService(BuildContext context, List<Service> sorted) {
    if (_seededInitial) return;
    _seededInitial = true;
    final no = widget.initialService;
    if (no == null || !sorted.any((s) => s.no == no)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openServiceSheet(context, no);
    });
  }

  /// Opens [no]'s detail sheet. Starts a little over half height — the board
  /// answers the question without hiding the list it came from — and grows
  /// toward full when the route timeline is opened.
  void _openServiceSheet(BuildContext context, String no) {
    _setStateEverywhere(() {
      _routeExpanded = false;
      _showPreviousStops = false;
    });
    final drag = DraggableScrollableController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SoftBlue.bg,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        controller: drag,
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) {
            _sheetRebuild = () => setSheetState(() {});
            // The board's numbers are live, so the sheet listens to the same
            // stores the screen does rather than freezing at open time.
            return ListenableBuilder(
              listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
              builder: (context, _) =>
                  _serviceSheet(context, no, scrollController, drag),
            );
          },
        ),
      ),
    ).whenComplete(() {
      _sheetRebuild = null;
      // Dismissing resets the disclosure, so the next sheet opens on the
      // board rather than mid-timeline.
      _setStateEverywhere(() {
        _routeExpanded = false;
        _showPreviousStops = false;
      });
    });
  }

  Widget _serviceSheet(
    BuildContext context,
    String no,
    ScrollController scrollController,
    DraggableScrollableController drag,
  ) {
    final state = DataStore.shared.arrivals[widget.stopCode];
    final all = state != null && state.kind == ArrivalStateKind.loaded
        ? state.services.where((s) => s.no == no).toList()
        : <Service>[];
    // The service can vanish between refreshes (last bus of the night); the
    // sheet stays up but empty rather than throwing.
    if (all.isEmpty) {
      return ListView(controller: scrollController, children: const []);
    }
    final svc = all.first;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      children: [
        _sheetHero(context, svc),
        const SizedBox(height: 14),
        _sheetActionsCard(context, svc, drag),
      ],
    );
  }

  /// Up to 3 (seconds, load) pairs for ONE service — its own next/2nd/3rd
  /// arrival, each with that specific bus's crowd. Mirrors iOS
  /// `pillEntries`.
  List<({int sec, Load? load})> _pillEntries(Service svc, DateTime now) {
    final out = <({int sec, Load? load})>[];
    out.add((sec: _liveSec(svc, now), load: svc.load));
    if (svc.followingDate != null) {
      out.add((
        sec: svc.followingDate!.difference(now).inSeconds.clamp(0, 1 << 30),
        load: null,
      ));
    } else if (svc.followingSec > 0) {
      out.add((sec: svc.followingSec, load: null));
    }
    if (svc.thirdDate != null) {
      out.add((
        sec: svc.thirdDate!.difference(now).inSeconds.clamp(0, 1 << 30),
        load: null,
      ));
    }
    return out.take(3).toList();
  }

  /// The sheet's gradient identity + departure board. Breathing room
  /// throughout (iOS 2026-07-26): 18pt card padding and 20pt between the two
  /// rows — one step up from the in-page cards, because a sheet is read with
  /// nothing else on screen.
  Widget _sheetHero(BuildContext context, Service featured) {
    final now = DateTime.now();
    final entries = _pillEntries(featured, now);
    final alerted =
        AppModel.shared.alertFor(
          kind: AlertKind.arrival,
          busNo: featured.no,
          stopCode: widget.stopCode,
        ) !=
        null;
    final road = DataStore.shared.roadName(widget.stopCode);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: SoftBlue.heroGradient,
        borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
        boxShadow: SoftBlue.heroShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: number tile · destination/road · Alert-me pill.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  featured.no,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SoftBlue.sans(
                    19,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'to ${featured.dest}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoftBlue.sans(
                        14,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (road.isNotEmpty)
                      Text(
                        'via $road',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SoftBlue.sans(
                          11,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _alertPill(alerted: alerted, svc: featured),
            ],
          ),
          const SizedBox(height: 20),
          // Row 2: the departure board — NEXT / THEN / LATER, each slot this
          // service's own time + crowd gauge. Every slot uses the same type
          // sizes so labels, times and chips sit on one line across the
          // board; NEXT is emphasised by opacity, not by being a size bigger.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) _boardDivider(),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 16,
                      right: i == entries.length - 1 ? 0 : 10,
                    ),
                    child: _boardSlot(entries[i], i),
                  ),
                ),
              ],
              // Only ONE bus timed: say so rather than leaving two dead
              // columns of gradient. LTA simply has nothing more.
              if (entries.length == 1) ...[
                _boardDivider(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      'No later bus timed yet',
                      style: SoftBlue.sans(
                        12,
                        weight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Hairline between board slots.
  Widget _boardDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Container(
      width: 1,
      height: 78,
      color: Colors.white.withValues(alpha: 0.28),
    ),
  );

  static const _ordinalLabels = ['NEXT', 'THEN', 'LATER'];

  Widget _boardSlot(({int sec, Load? load}) entry, int index) {
    final eta = fmtEta(entry.sec);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _ordinalLabels[index],
          style: SoftBlue.sans(
            10,
            weight: FontWeight.bold,
            color: Colors.white.withValues(alpha: index == 0 ? 0.85 : 0.6),
          ).copyWith(letterSpacing: 0.6),
        ),
        const SizedBox(height: 9),
        // "Now", not the "Arr" abbreviation — in a stacked slot "Arr" read as
        // a word in a column of words, not as a time. ONE size for every slot
        // so the three times share a baseline; later slots step back on
        // opacity instead.
        Opacity(
          opacity: index == 0 ? 1 : 0.88,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: eta.big == 'Arr' ? 'Now' : eta.big,
                  style: SoftBlue.mono(
                    27,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (eta.big != 'Arr')
                  TextSpan(
                    text: ' min',
                    style: SoftBlue.sans(
                      12,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        _crowdChip(entry.load),
      ],
    );
  }

  /// Crowd for one board slot: a 3-segment gauge plus the short word, on a
  /// tinted capsule. Mirrors iOS `crowdChip`.
  ///
  /// The segments count ROOM LEFT, not occupancy (owner 2026-07-26): three
  /// lit ⟹ seats, one lit ⟹ almost full. Inverted from the original filling
  /// meter, where the most packed bus lit the most segments and so looked
  /// like the best option at a glance.
  ///
  /// With no occupancy from LTA the segments are dropped entirely and the
  /// chip just says "No data". They can't merely go dark: under this reading
  /// an unlit gauge asserts "no room", which is a claim, not the absence of
  /// one.
  Widget _crowdChip(Load? load) {
    final fill = switch (load) {
      Load.sea => 3,
      Load.sda => 2,
      Load.lsd => 1,
      null => 0,
    };
    return Semantics(
      label: load == null ? 'Crowd unknown' : 'Crowd: ${_crowdWord(load)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (load != null)
              for (var seg = 0; seg < 3; seg++)
                Padding(
                  padding: EdgeInsets.only(left: seg == 0 ? 0 : 2),
                  child: Container(
                    width: 4,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: seg < fill ? 0.95 : 0.30,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            if (load != null) const SizedBox(width: 5),
            Flexible(
              child: Text(
                _crowdShort(load),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SoftBlue.sans(
                  10,
                  weight: FontWeight.w600,
                  color: Colors.white.withValues(
                    alpha: load == null ? 0.7 : 0.95,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Per-slot crowd word: "Seats"/"Stand"/"Full", or "No data" when LTA sent
  /// no occupancy for that specific bus — mirrors iOS `Load.wsShort`.
  String _crowdShort(Load? load) {
    return switch (load) {
      Load.sea => 'Seats',
      Load.sda => 'Stand',
      Load.lsd => 'Full',
      null => 'No data',
    };
  }

  /// Full crowd phrasing for the service rows — mirrors iOS `Load.wsWord`. A
  /// bare "Seats"/"Standing" left people asking what the word was even about
  /// (owner 2026-07-26); nothing next to it says the line is about the crowd
  /// on board, so the label has to carry its own meaning.
  String _crowdWord(Load? load) {
    return switch (load) {
      Load.sea => 'Seats available',
      Load.sda => 'Standing only',
      Load.lsd => 'Almost full',
      null => 'Crowd unknown',
    };
  }

  /// Sits ON the gradient hero: armed = solid white capsule with blue text,
  /// resting = translucent white outline. One tap arms/disarms — no confirm
  /// sheet, matching iOS.
  Widget _alertPill({required bool alerted, required Service svc}) {
    return Semantics(
      button: true,
      label: alerted ? 'Alert on for bus ${svc.no}' : 'Alert me for bus ${svc.no}',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => toggleArrivalAlert(
          busNo: svc.no,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
          dest: svc.dest,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: alerted ? Colors.white : Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: alerted
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                alerted
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 13,
                color: alerted ? SoftBlue.blue : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                alerted ? 'Alert on' : 'Alert me',
                style: SoftBlue.sans(
                  11.5,
                  weight: FontWeight.bold,
                  color: alerted ? SoftBlue.blue : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet actions card (route timeline + favourite) ─────────────────────
  // The two things you can do with THIS bus, in one white card under the
  // board: expand its route, or favourite it. The route used to be a card on
  // the stop screen itself, answering a question nobody asks at that point —
  // you look for A BUS first — so it moved in here with the bus it belongs
  // to (iOS 2026-07-26). Favourite lives here now that the row swipe tray is
  // down to its one action.

  Widget _sheetActionsCard(
    BuildContext context,
    Service svc,
    DraggableScrollableController drag,
  ) {
    final fav = AppModel.shared.isFavService(no: svc.no, stop: widget.stopCode);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "View route" collapsed, "Route · N stops to <dest>" open.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleRoute(svc, drag),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.map_outlined, size: 15, color: SoftBlue.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _routeExpanded ? _routeToggleTitle(svc) : 'View route',
                        style: SoftBlue.sans(
                          14,
                          weight: FontWeight.w600,
                          color: SoftBlue.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _routeExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: SoftBlue.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_routeExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _routeTimelineBody(context, svc),
            ),
          // Divider inset past the leading icon, not full-bleed.
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(height: 1, color: SoftBlue.hairline),
          ),
          Semantics(
            button: true,
            label: fav
                ? 'Bus ${svc.no} saved to Favourites. Tap to remove.'
                : 'Favourite bus ${svc.no} at this stop',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _setStateEverywhere(
                  () => AppModel.shared.toggleFavService(
                    no: svc.no,
                    stop: widget.stopCode,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        fav
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 15,
                        color: SoftBlue.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fav
                              ? 'Saved to Favourites'
                              : 'Favourite bus ${svc.no}',
                          style: SoftBlue.sans(
                            14,
                            weight: FontWeight.w600,
                            color: SoftBlue.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _routeToggleTitle(Service svc) {
    if (_routeLoadedFor == svc.no &&
        _routeInfo != null &&
        _routeInfo!.stops.isNotEmpty) {
      final r = _routeInfo!;
      final you = r.youIndex.clamp(0, r.stops.length - 1);
      final remaining = (r.stops.length - 1 - you).clamp(0, r.stops.length);
      return 'Route · $remaining stop${remaining == 1 ? '' : 's'} to ${svc.dest}';
    }
    return 'Route · to ${svc.dest}';
  }

  void _toggleRoute(Service svc, DraggableScrollableController drag) {
    final expand = !_routeExpanded;
    _setStateEverywhere(() {
      _routeExpanded = expand;
      if (!expand) _showPreviousStops = false;
    });
    if (expand) {
      // The timeline needs the room — grow the sheet toward full rather than
      // leaving the route to scroll inside a half-height sheet (iOS raises
      // its detent to `.large` at the same moment).
      if (drag.isAttached) {
        drag.animateTo(
          0.95,
          duration: SoftMotion.flowDuration,
          curve: SoftMotion.flowCurve,
        );
      }
      _loadRoute(svc.no);
    }
  }

  Future<void> _loadRoute(String no) async {
    final r = await DataStore.shared.route(
      serviceNo: no,
      stopCode: widget.stopCode,
    );
    if (r == null || !mounted) return;
    var busIndex = r.busIndex;
    final coord = await DataStore.shared.liveBus(
      serviceNo: no,
      stopCode: widget.stopCode,
    );
    if (coord != null && r.stops.isNotEmpty) {
      final you = r.youIndex.clamp(0, r.stops.length - 1);
      int? bestIdx;
      var bestD = double.infinity;
      for (var i = 0; i <= you; i++) {
        final s = r.stops[i];
        final d = haversine(coord.lat, coord.lon, s.lat, s.lon);
        if (d < bestD) {
          bestD = d;
          bestIdx = i;
        }
      }
      busIndex = bestIdx;
    }
    if (!mounted) return;
    // The timeline is drawn INSIDE the sheet, so the plain setState the route
    // used to do left it stuck on "Loading route…" forever.
    _setStateEverywhere(() {
      _routeInfo = RouteInfo(
        stops: r.stops,
        youIndex: r.youIndex,
        busIndex: busIndex,
        busCoord: coord,
      );
      _routeLoadedFor = no;
    });
  }

  Widget _routeTimelineBody(BuildContext context, Service featured) {
    final t = context.t;
    if (_routeLoadedFor != featured.no ||
        _routeInfo == null ||
        _routeInfo!.stops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Loading route…',
          style: t.sans(12, weight: FontWeight.w500, color: t.dim),
        ),
      );
    }
    final r = _routeInfo!;
    final you = r.youIndex.clamp(0, r.stops.length - 1);
    final lines = _routeLines(r, you);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 230),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (you > 0) _earlierStopsRow(you),
            for (var i = 0; i < lines.length; i++)
              _routeLineRow(context, lines[i], isLast: i == lines.length - 1),
          ],
        ),
      ),
    );
  }

  /// One display row of the compact route skeleton. Mirrors iOS
  /// WSBusStopView's `RouteLine`.
  List<_RouteLine> _routeLines(RouteInfo r, int you) {
    final lines = <_RouteLine>[];
    if (_showPreviousStops) {
      for (var i = 0; i < you; i++) {
        lines.add(
          r.busIndex == i
              ? _RouteLine.bus(r.stops[i])
              : _RouteLine.past(r.stops[i]),
        );
      }
    } else if (r.busIndex != null && r.busIndex! < you) {
      lines.add(_RouteLine.bus(r.stops[r.busIndex!]));
      final gap = you - r.busIndex! - 1;
      if (gap > 0) lines.add(_RouteLine.gap(gap));
    }
    lines.add(_RouteLine.you(r.stops[you]));
    final onward = r.stops.sublist(you + 1);
    for (var i = 0; i < onward.length - 1; i++) {
      lines.add(_RouteLine.stop(onward[i]));
    }
    if (onward.isNotEmpty) lines.add(_RouteLine.finalStop(onward.last));
    return lines;
  }

  Widget _earlierStopsRow(int count) {
    final t = context.t;
    return InkWell(
      onTap: () =>
          _setStateEverywhere(() => _showPreviousStops = !_showPreviousStops),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Container(
                        width: 2.5,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _showPreviousStops
                    ? 'Hide earlier stops'
                    : '$count earlier stop${count == 1 ? '' : 's'} · show',
                style: t.sans(11.5, weight: FontWeight.w600, color: t.accent),
              ),
            ),
            Icon(
              _showPreviousStops
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: t.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeLineRow(BuildContext context, _RouteLine line, {required bool isLast}) {
    final t = context.t;
    switch (line.kind) {
      case _RouteLineKind.gap:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Container(
                          width: 2.5,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: t.dim.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${line.gapCount} stop${line.gapCount == 1 ? '' : 's'}',
                style: t.sans(10.5, color: t.dim),
              ),
            ],
          ),
        );
      case _RouteLineKind.bus:
      case _RouteLineKind.you:
      case _RouteLineKind.stop:
      case _RouteLineKind.past:
      case _RouteLineKind.finalStop:
        final stop = line.stop!;
        final (dot, nameWeight, nameColor, tag, tagColor) = switch (line.kind) {
          _RouteLineKind.bus => (
            _busDot(t),
            FontWeight.w400,
            t.dim,
            'Bus is here',
            t.accent,
          ),
          _RouteLineKind.you => (
            _plainDot(t.accent, filled: true),
            FontWeight.w600,
            t.fg,
            'You are here',
            t.dim,
          ),
          _RouteLineKind.past => (
            _plainDot(t.dim.withValues(alpha: 0.3), filled: false),
            FontWeight.w400,
            t.dim.withValues(alpha: 0.7),
            null,
            t.dim,
          ),
          _RouteLineKind.finalStop => (
            _plainDot(t.accent.withValues(alpha: 0.7), filled: false),
            FontWeight.w600,
            t.fg,
            'Final stop',
            t.dim,
          ),
          _ => (
            _plainDot(t.dim.withValues(alpha: 0.35), filled: false),
            FontWeight.w400,
            t.dim,
            null,
            t.dim,
          ),
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  dot,
                  if (!isLast)
                    Container(width: 2, height: 16, color: t.line),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        stop.name,
                        style: t.sans(12.5, weight: nameWeight, color: nameColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag != null)
                      Text(
                        tag,
                        style: t.sans(11, color: tagColor),
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _busDot(LyneTheme t) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.accent.withValues(alpha: 0.5)),
      ),
      child: Icon(Icons.directions_bus_rounded, size: 9, color: t.accent),
    );
  }

  Widget _plainDot(Color color, {required bool filled}) {
    return Container(
      width: filled ? 10 : 8,
      height: filled ? 10 : 8,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : null,
        shape: BoxShape.circle,
        border: filled ? null : Border.all(color: color, width: 2),
      ),
    );
  }

  // ── MRT interchange resolution ──────────────────────────────────────────
  // When the stop's name resolves to an MRT station ("Farrer Rd Stn Exit A"
  // → Farrer Road), the header's meta line (spec item 4a) carries a tappable
  // fragment straight into that station's detail (crowd, forecast,
  // disruptions all live there — this screen no longer duplicates a crowd
  // preview inline; the owner's complaint was "messy at the top", so the
  // header collapses to one line and the full interchange card that used to
  // sit below it is gone. Its extra info (live crowd) stays reachable — it's
  // exactly what the station screen already opens to).

  /// Resolves this stop to an MRT interchange, if any, pairing the name
  /// match ([MrtStation], for line codes/display name) with its geo record
  /// ([MrtGeoStation], for the pushed station screen's own lat/lon-driven
  /// sections). Null when this stop isn't at/near a station.
  ({MrtStation resolved, MrtGeoStation station})? _resolvedInterchange() {
    final stopName = DataStore.shared.stopName(widget.stopCode);
    final resolved = resolveMrtStation(stopName);
    if (resolved == null) return null;
    final geoMatches = MrtGeo.all.where(
      (s) => s.name.toLowerCase() == resolved.name.toLowerCase(),
    );
    if (geoMatches.isEmpty) return null;
    return (resolved: resolved, station: geoMatches.first);
  }

  void _openInterchangeStation(BuildContext context, MrtGeoStation station) {
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
                  onTab: widget.onTab,
                  tabSelection: widget.tabSelection,
                ),
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
        // Pin/unpin this stop — matches iOS's star toggle exactly (no popup;
        // a plain toggle). The star fills when the stop is saved.
        _starButton(context, isPinned),
      ],
    );
  }

  /// Pin/unpin toggle. The star fills when the stop is saved. Mirrors iOS
  /// WSBusStopView's trailing star button (`togglePin`, `star`/`star.fill` —
  /// bookmark is iOS's glyph for *other* contexts, e.g. WSSavedView's
  /// context menus; this screen and WSMrtStationView both use star, so this
  /// button was corrected 2026-07-25 from a bookmark glyph, which was a
  /// parity mismatch, not an intentional Android divergence).
  Widget _starButton(BuildContext context, bool isPinned) {
    final t = context.t;
    final name = DataStore.shared.stopName(widget.stopCode);
    return Semantics(
      label: isPinned ? '$name saved. Tap to remove.' : 'Save stop $name',
      button: true,
      child: _softCircleButton(
        onTap: () => AppModel.shared.togglePin(widget.stopCode),
        iconWidget: Icon(
          isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 20,
          color: isPinned ? t.soon : SoftBlue.ink,
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
    assert(icon != null || iconWidget != null);
    return _softCircleButton(
      onTap: onTap,
      iconWidget: iconWidget ?? Icon(icon!, size: 20, color: SoftBlue.ink),
    );
  }

  /// A 44×44 circular icon button in the SoftBlue chrome (anti-rule #5 fix):
  /// white fill, NO border, the shared icon-button shadow — a sibling of
  /// [SoftIconButton] (which is 40×40 square) for this screen's two circular
  /// header actions.
  Widget _softCircleButton({
    required Widget iconWidget,
    required VoidCallback onTap,
  }) {
    return Material(
      color: SoftBlue.card,
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
            boxShadow: SoftBlue.iconButtonShadow,
          ),
          alignment: Alignment.center,
          child: iconWidget,
        ),
      ),
    );
  }

  // ── Title block ──────────────────────────────────────────────────────────

  /// Header rows 2–3 (spec item 4a, 2026-07-25): big stop name, then ONE
  /// quiet meta line — "`<stopCode> · <distance>`" plus a tappable
  /// interchange fragment when this stop is at/near an MRT station.
  /// Supersedes the old LIVE-badge + ROAD + "Updated h:mm" line — the
  /// owner's complaint was "messy at the top; simplify", and the separate
  /// interchange card below this block is gone (folded into this line).
  Widget _titleBlock(BuildContext context) {
    final ds = DataStore.shared;
    final interchange = _resolvedInterchange();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Large stop name — capped at 2 lines (spec).
        Text(
          ds.stopName(widget.stopCode),
          style: SoftBlue.sans(22, weight: FontWeight.w800, color: SoftBlue.ink),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        _identityCard(context, interchange),
      ],
    );
  }

  /// The stop's facts in ONE card, not a scatter of loose text (iOS parity,
  /// owner 2026-07-26). They used to be a single 11.5pt grey sentence stranded
  /// under the title; free-floating capsules read as unrelated objects, and a
  /// bare value needs its label ("68m" alone doesn't say what it measures).
  /// Hairlines divide the three facts, and the MRT interchange — the only
  /// tappable item — gets its own full-width row underneath, where a chevron
  /// actually means "go here" (ui-checklist §2).
  Widget _identityCard(
    BuildContext context,
    ({MrtStation resolved, MrtGeoStation station})? interchange,
  ) {
    final metres = _distanceM();
    return Container(
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _factCell(Icons.tag_rounded, 'Stop', widget.stopCode),
                  _factDivider(),
                  _factCell(
                    Icons.directions_walk_rounded,
                    'Walk',
                    metres == null ? '—' : '${walkMinutesFor(metres)} min',
                  ),
                  _factDivider(),
                  _factCell(
                    Icons.my_location_rounded,
                    'Away',
                    metres == null ? '—' : fmtDistance(metres.round()),
                  ),
                ],
              ),
            ),
          ),
          // Directions. This action used to exist ONLY inside the arrivals
          // empty state, so on a normal stop — the 99% case — there was no
          // way to navigate to it at all (owner 2026-07-26). It belongs here:
          // the card already answers "how far", and this is the action that
          // follows from that answer.
          _walkHereButton(metres),
          if (interchange != null) ...[
            Container(height: 1, color: SoftBlue.hairline),
            _interchangeRow(context, interchange),
          ],
        ],
      ),
    );
  }

  /// A real BUTTON, not a sentence with a chevron (owner 2026-07-26: "don't
  /// put a string of text and call it a day"). Filled blue capsule, white
  /// ink, the turn arrow in its own translucent tile, and the walk time
  /// carried inside the button so the action states its own cost. This is the
  /// identity card's one action, so it gets the card's one piece of solid
  /// colour.
  Widget _walkHereButton(double? metres) {
    final mins = metres == null ? null : walkMinutesFor(metres);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Semantics(
        button: true,
        label: 'Walk here — directions to this stop in your maps app',
        excludeSemantics: true,
        child: Material(
          color: SoftBlue.blue,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openDirections,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.directions_walk_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Walk here',
                          style: SoftBlue.sans(
                            14,
                            weight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          mins == null ? 'Maps' : '$mins min · Maps',
                          style: SoftBlue.sans(
                            11,
                            weight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.turn_slight_right_rounded,
                    size: 17,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One fact: icon + the word that says what the value IS, then the value.
  Widget _factCell(IconData icon, String label, String value) {
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: SoftBlue.blue),
                const SizedBox(width: 4),
                Text(
                  label.toUpperCase(),
                  style: SoftBlue.sans(
                    10,
                    weight: FontWeight.w700,
                    color: SoftBlue.sub,
                  ).copyWith(letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: SoftBlue.sans(
                14,
                weight: FontWeight.w700,
                color: SoftBlue.ink,
                tabular: true,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _factDivider() =>
      Container(width: 1, color: SoftBlue.hairline, margin: const EdgeInsets.symmetric(vertical: 2));

  /// Straight-line metres to this stop. Null only when we genuinely can't say
  /// — no fix, or beyond ~50 km, where "away" stops being navigation
  /// information.
  ///
  /// The old <50 m cut-off is gone (owner 2026-07-26, ported from iOS): near
  /// the stop is when the metres matter MOST, and a card built to hold three
  /// facts shouldn't blank two of them at the moment they're most relevant.
  /// "—" now means one thing only: we don't know.
  double? _distanceM() {
    final loc = LocationService.shared.lastLocation;
    final latLon = DataStore.shared.stopLatLon(widget.stopCode);
    if (loc == null || latLon == null) return null;
    final m = haversine(loc.lat, loc.lon, latLon.lat, latLon.lon);
    return m <= 50000 ? m : null;
  }

  /// The MRT interchange as its own full-width row at the foot of the identity
  /// card — line pills, station name, chevron. It used to be a fragment glued
  /// onto the end of the meta sentence, where nothing said it was tappable; a
  /// chevron means "this navigates" (ui-checklist §2), so the only tappable
  /// fact on this card is the only one that gets one.
  Widget _interchangeRow(
    BuildContext context,
    ({MrtStation resolved, MrtGeoStation station}) interchange,
  ) {
    final resolved = interchange.resolved;
    return Semantics(
      button: true,
      label: '${resolved.name} MRT station',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openInterchangeStation(context, interchange.station),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                for (final c in resolved.codes.take(2))
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
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
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    resolved.name,
                    style: SoftBlue.sans(
                      13.5,
                      weight: FontWeight.w600,
                      color: SoftBlue.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SoftBlue.sub,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Arrivals ───────────────────────────────────────────────────────────────

  /// "All services" — EVERY service at this stop, including the soonest. The
  /// soonest used to be filtered out because the hero card was already
  /// showing it; with the hero gone that filter silently hid the most useful
  /// bus at the stop (iOS 2026-07-26).
  Widget _arrivalSection(
    BuildContext context,
    ArrivalState? state,
    List<Service> sorted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state == null || state.kind == ArrivalStateKind.loading)
          _closedStateCard(context, error: null, loading: true)
        else if (state.kind == ArrivalStateKind.empty)
          _closedStateCard(context, error: null)
        else if (state.kind == ArrivalStateKind.error)
          _closedStateCard(
            context,
            error: state.errorMessage ?? "Couldn't reach LTA",
          )
        // "Loaded, but nothing in it" is the same fact as `empty` — iOS
        // folds them together (`arrivalsAreEmpty`) so a stop that answers
        // with a zero-length list still gets the closed-stop card rather
        // than a blank space under the header.
        else if (sorted.isEmpty)
          _closedStateCard(context, error: null)
        else ...[
          // 22pt inset overall: the page's ListView already pads 16.
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              'All services',
              style: SoftBlue.sans(
                16,
                weight: FontWeight.bold,
                color: SoftBlue.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _arrivalsList(context, sorted),
        ],
      ],
    );
  }

  // The "WATCHING" block that used to sit above the list is GONE (iOS
  // 2026-07-26): it restated what the row's own bell badge and the sheet's
  // "Alert on" pill already say. Armed state now lives only where the control
  // that armed it lives.

  // ── Arrivals list ─────────────────────────────────────────────────────────

  /// The grouped arrivals card: one row per service, split by dividers inset
  /// past the service tile. EVERY service, always — the "Show more" collapse
  /// is gone (iOS shows the whole board; a stop with 14 services is a stop
  /// with 14 rows).
  Widget _arrivalsList(BuildContext context, List<Service> sorted) {
    // No mid-list MREC any more — this screen's single ad is the anchored
    // banner in [SoftDetailBottomBar] (owner placement redesign 2026-07-07).

    // SlidableAutoCloseBehavior: opening one row's Notify action closes any
    // other open one (shared 'arrivals' group tag).
    return SlidableAutoCloseBehavior(
      child: Material(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: SoftBlue.cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 64),
                    child: Container(height: 1, color: SoftBlue.hairline),
                  ),
                _swipeNotify(context, sorted[i], _busRow(context, sorted[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Service row (inside the grouped card) ─────────────────────────────────
  //
  // Hierarchy: fixed-width service tile (with a blue bell badge when armed) ·
  // "to <dest>" + the crowd word · a right-aligned ETA column. At a known
  // stop the ETA is the ANSWER, so it's the row's primary element and the
  // destination drops to secondary. No "ARRIVING" capsule and no accent row
  // wash — a busy stop lit up in three places at once; the arriving row says
  // "Now" in chipInk and that's the whole tell. No "~" prefix either: iOS
  // doesn't qualify ETAs on this screen.
  //
  // Tapping the row opens that bus's SHEET. It used to promote the service
  // into the hero card — with the hero removed the tap changed something
  // above the fold and read as doing nothing at all (owner 2026-07-26).

  Widget _busRow(BuildContext context, Service bus) {
    final now = DateTime.now();
    final etas = _arrivalTimes(bus, now);
    final leadSec = etas.first;
    final later = etas.skip(1).map((s) => fmtEta(s).big).toList();
    final alerted =
        AppModel.shared.alertFor(
          kind: AlertKind.arrival,
          busNo: bus.no,
          stopCode: widget.stopCode,
        ) !=
        null;
    // Gated on `bus.monitored` only, not on feed recency — a monitored bus
    // stays "arriving" even if the stop's feed itself has gone briefly stale
    // (matches iOS).
    final arrivingNow = bus.monitored && fmtEta(leadSec).big == 'Arr';

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}',
      hint: arrivingNow
          ? "Bus ${bus.no} is arriving now. Tap to open its departures."
          : "Tap to open bus ${bus.no}'s departures",
      button: true,
      child: Material(
        color: SoftBlue.card,
        child: InkWell(
          onTap: () => _openServiceSheet(context, bus.no),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            child: Row(
              children: [
                // Fixed width, so the destination and crowd word below it
                // start on one line down the whole list.
                _serviceTileWithAlertBadge(bus.no, alerted: alerted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bus.dest.isEmpty ? 'Bus ${bus.no}' : 'to ${bus.dest}',
                        style: SoftBlue.sans(12.5, color: SoftBlue.sub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _rowCrowdWord(bus.load),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _rowEtaColumn(leadSec, later, arriving: arrivingNow),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The row's trailing answer column: the lead ETA, then the following two
  /// as "then 12, 24 min". Right-aligned in a min-width box so every row's
  /// numerals sit on the same vertical line.
  Widget _rowEtaColumn(
    int leadSec,
    List<String> later, {
    required bool arriving,
  }) {
    final big = fmtEta(leadSec).big;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Now", not "Arr" — the same word the sheet's board uses, so one
          // state has one name app-wide.
          Text(
            arriving ? 'Now' : '$big min',
            textAlign: TextAlign.right,
            style: SoftBlue.mono(
              17,
              weight: arriving ? FontWeight.w800 : FontWeight.bold,
              color: arriving ? SoftBlue.chipInk : SoftBlue.ink,
            ),
          ),
          if (later.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'then ${later.join(', ')} min',
              textAlign: TextAlign.right,
              style: SoftBlue.mono(10.5, color: SoftBlue.sub),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// Fixed-width service pill. Sized to its content, "961M" makes a visibly
  /// wider pill than "93", and because the tile is the row's leading element
  /// every following column would start at a different x on every row (owner
  /// 2026-07-26) — 58pt makes them identical. Mirrors iOS `SoftServiceTile`.
  Widget _serviceTile(String svc) {
    return Container(
      width: 58,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: SoftBlue.chipBg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        svc,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SoftBlue.sans(
          14,
          weight: FontWeight.w800,
          color: SoftBlue.chipInk,
          tabular: true,
        ),
      ),
    );
  }

  /// [_serviceTile] plus a small solid-blue bell overlay when this service
  /// has an armed arrival alert at this stop.
  Widget _serviceTileWithAlertBadge(String svc, {required bool alerted}) {
    if (!alerted) return _serviceTile(svc);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _serviceTile(svc),
        Positioned(
          top: -5,
          right: -5,
          child: Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: SoftBlue.blue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_rounded,
              size: 9,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// The row's crowd line, in FULL phrasing ("Seats available", not "Seats"
  /// — owner 2026-07-26: nothing next to it says the line is about the crowd
  /// on board, so the label has to carry its own meaning). Deliberately NOT
  /// the shared [CrowdMeter], which keeps crowd colour-neutral everywhere
  /// else: this row's word tints amber for standing room and RED for a
  /// full/limited bus, matching iOS WSBusStopView's row-level
  /// `load == .sda ? amber : load == .lsd ? red : sub` exactly.
  Widget _rowCrowdWord(Load? load) {
    return Text(
      _crowdWord(load),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SoftBlue.sans(
        10.5,
        weight: load == Load.sea || load == null
            ? FontWeight.w400
            : FontWeight.w600,
        color: switch (load) {
          Load.sda => SoftBlue.amber,
          Load.lsd => SoftBlue.red,
          _ => SoftBlue.sub,
        },
      ),
    );
  }

  /// Wrap a bus row so swiping it reveals its ONE action: arm/disarm the
  /// arrival alert (with an Undo snackbar). Favouriting used to live here
  /// too; it moved into the row's sheet (iOS 2026-07-26), so the tray is a
  /// single 88pt-wide chip rather than a two-colour drawer.
  Widget _swipeNotify(BuildContext context, Service bus, Widget child) {
    final on =
        AppModel.shared.alertFor(
          kind: AlertKind.arrival,
          busNo: bus.no,
          stopCode: widget.stopCode,
        ) !=
        null;
    // extentRatio is a fraction of the row, so back out the 88pt iOS uses.
    final width = MediaQuery.sizeOf(context).width;
    return Slidable(
      key: ValueKey('notify-${bus.no}'),
      groupTag: 'arrivals',
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: width <= 0 ? 0.25 : (88 / width).clamp(0.15, 0.5),
        children: [
          SlidableAction(
            onPressed: (_) => toggleArrivalAlert(
              busNo: bus.no,
              stopCode: widget.stopCode,
              stopName: DataStore.shared.stopName(widget.stopCode),
              dest: bus.dest,
            ),
            backgroundColor: SoftBlue.chipBg,
            foregroundColor: SoftBlue.chipInk,
            icon: on
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            label: on ? 'On ✓' : 'Notify',
          ),
        ],
      ),
      child: child,
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
  // Neutral, bordered, monospaced. Only the first/last-bus timetable inside
  // the closed-stop card still uses it — the live service rows carry the
  // SoftBlue [_serviceTile] instead.

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
  /// ONE composed empty state for the whole screen (ui-checklist §3): a
  /// headline, TODAY's first & last bus per service, and the things you can
  /// still DO here. Ported from iOS `WSBusStopView.heroPlaceholder`.
  ///
  /// "No live arrivals" on its own is a dead end. When the feed says the stop
  /// is shut, the useful fact is when the buses come back — so the timetable
  /// is loaded lazily HERE (a full route-table scan, wasted on the 99% of
  /// visits that have live arrivals) rather than on every open.
  ///
  /// [error] non-null means the fetch FAILED rather than returned empty: the
  /// timetable is meaningless then (we don't know the stop is closed), and a
  /// retry is offered because the data really might be one tap away. A closed
  /// stop gets no "check again" — the stop is shut, so inviting a refresh only
  /// promises something the next poll can't deliver (owner 2026-07-26).
  Widget _closedStateCard(
    BuildContext context, {
    required String? error,
    bool loading = false,
  }) {
    final isPinned = AppModel.shared.pinForCode(widget.stopCode) != null;
    final closed = error == null && !loading;
    final windows = closed
        ? DataStore.shared.firstLastAtStop(widget.stopCode)
        : const <({String service, String first, String last})>[];
    // Kick the route dataset if it hasn't loaded — the list fills in on the
    // next rebuild rather than staying permanently blank.
    if (closed && windows.isEmpty) DataStore.shared.ensureRoutes();

    // All three states share ONE shape — icon tile, headline, detail line —
    // so they read as one system rather than a bare spinner for loading and a
    // card for empty/error (iOS `heroPlaceholder`).
    final (icon, headline, detail) = loading
        ? (
            Icons.refresh_rounded,
            'Getting live arrivals…',
            "Fetching this stop's departures from LTA.",
          )
        : error != null
        ? (Icons.wifi_tethering_error_rounded, "Can't reach live arrivals", error)
        : (
            Icons.nights_stay_rounded,
            'No buses running',
            'Nothing is timed at this stop right now — the last bus has gone.',
          );

    final use24h = AppModel.shared.use24h;
    return Container(
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: SoftBlue.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: SoftBlue.blue),
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: SoftBlue.sans(
                    17,
                    weight: FontWeight.bold,
                    color: SoftBlue.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: SoftBlue.sans(
                    13,
                    weight: FontWeight.w500,
                    color: SoftBlue.sub,
                  ),
                ),
              ],
            ),
          ),
          if (windows.isNotEmpty) ...[
            Container(height: 1, color: SoftBlue.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'FIRST & LAST BUS · ${_dayTypeLabel().toUpperCase()}',
                style: SoftBlue.sans(
                  10.5,
                  weight: FontWeight.w700,
                  color: SoftBlue.sub,
                ).copyWith(letterSpacing: 0.8),
              ),
            ),
            for (var i = 0; i < windows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(height: 1, color: SoftBlue.hairline),
                ),
              Semantics(
                label:
                    'Bus ${windows[i].service}, first '
                    '${fmtClock(windows[i].first, use24h: use24h)}, last '
                    '${fmtClock(windows[i].last, use24h: use24h)}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _routeTile(windows[i].service, context.t),
                      const Spacer(),
                      // Fixed-width columns so the times line up down the list
                      // rather than drifting with each service number (§3).
                      SizedBox(
                        width: 58,
                        child: Text(
                          fmtClock(windows[i].first, use24h: use24h),
                          textAlign: TextAlign.right,
                          style: SoftBlue.mono(
                            13,
                            weight: FontWeight.w700,
                            color: SoftBlue.ink,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '–',
                          style: SoftBlue.sans(12, color: SoftBlue.sub),
                        ),
                      ),
                      SizedBox(
                        width: 58,
                        child: Text(
                          fmtClock(windows[i].last, use24h: use24h),
                          textAlign: TextAlign.right,
                          style: SoftBlue.mono(
                            13,
                            weight: FontWeight.w700,
                            color: SoftBlue.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ],
          // Nothing to DO while the fetch is still in flight — the actions
          // appear with the answer (iOS gates them on `!isLoading`).
          if (!loading) ...[
            Container(height: 1, color: SoftBlue.hairline),
            if (error != null)
              _emptyAction(
                icon: Icons.refresh_rounded,
                title: 'Try again',
                subtitle: "Re-fetch this stop's arrivals",
                onTap: () => DataStore.shared.refreshArrivals(widget.stopCode),
                divider: true,
              ),
            // The platform escape hatch (ui-checklist §7). Android has no
            // in-app map, so this hands the stop to whatever maps app the
            // user has, as a WALKING destination — the same job iOS's
            // "Directions in Apple Maps" does.
            _emptyAction(
              icon: Icons.directions_walk_rounded,
              title: 'Walk here',
              subtitle: 'Directions in your maps app',
              onTap: _openDirections,
              divider: true,
            ),
            _emptyAction(
              icon: isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
              title: isPinned ? 'Saved' : 'Save this stop',
              subtitle: isPinned
                  ? "It's in your Favourites"
                  : 'Find it fast in the morning',
              onTap: () => AppModel.shared.togglePin(widget.stopCode),
              divider: false,
            ),
          ],
        ],
      ),
    );
  }

  /// One action row inside the empty state.
  Widget _emptyAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool divider,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SoftBlue.chipBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 16, color: SoftBlue.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: SoftBlue.sans(
                            14,
                            weight: FontWeight.w600,
                            color: SoftBlue.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: SoftBlue.sans(11.5, color: SoftBlue.sub),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: SoftBlue.sub,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (divider)
          Padding(
            padding: const EdgeInsets.only(left: 62),
            child: Container(height: 1, color: SoftBlue.hairline),
          ),
      ],
    );
  }

  /// Which set of LTA times applies today. Public holidays aren't in the feed,
  /// so Sunday's column is labelled to cover them — the same wording the
  /// Service Info screen uses.
  String _dayTypeLabel() => switch (DateTime.now().weekday) {
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sun / P.H.',
    _ => 'Weekdays',
  };

  /// Hand this stop to the user's maps app as a walking destination. `geo:`
  /// first (any installed maps app answers it), falling back to a Google Maps
  /// walking-directions URL when nothing handles the scheme.
  Future<void> _openDirections() async {
    final latLon = DataStore.shared.stopLatLon(widget.stopCode);
    if (latLon == null) return;
    final name = Uri.encodeComponent(
      DataStore.shared.stopName(widget.stopCode),
    );
    final geo = Uri.parse(
      'geo:${latLon.lat},${latLon.lon}?q=${latLon.lat},${latLon.lon}($name)',
    );
    if (await canLaunchUrl(geo)) {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    }
    await launchUrl(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${latLon.lat},${latLon.lon}&travelmode=walking',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  // The separate spinner-in-a-card loading state is gone — loading is now
  // one of [_closedStateCard]'s three faces, so the screen never swaps card
  // shapes between "waiting" and "answered".

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

// ── Inline route timeline row model ─────────────────────────────────────
// Mirrors iOS WSBusStopView's private `RouteLine` enum: one display row of
// the compact route skeleton under the hero (spec item 3).

enum _RouteLineKind { bus, gap, you, stop, past, finalStop }

class _RouteLine {
  const _RouteLine._(this.kind, {this.stop, this.gapCount = 0});

  factory _RouteLine.bus(RouteStopLive s) => _RouteLine._(_RouteLineKind.bus, stop: s);
  factory _RouteLine.gap(int n) => _RouteLine._(_RouteLineKind.gap, gapCount: n);
  factory _RouteLine.you(RouteStopLive s) => _RouteLine._(_RouteLineKind.you, stop: s);
  factory _RouteLine.stop(RouteStopLive s) => _RouteLine._(_RouteLineKind.stop, stop: s);
  factory _RouteLine.past(RouteStopLive s) => _RouteLine._(_RouteLineKind.past, stop: s);
  factory _RouteLine.finalStop(RouteStopLive s) =>
      _RouteLine._(_RouteLineKind.finalStop, stop: s);

  final _RouteLineKind kind;
  final RouteStopLive? stop;
  final int gapCount;
}
