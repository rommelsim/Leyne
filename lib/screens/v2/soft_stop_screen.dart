// SoftStopScreen — Leyne Stop detail (Material 3 Android variant).
//
// Layout mirrors the current iOS WhereSia spec, ios-native/Leyne/WhereSia/
// WSBusStopView.swift (NOT the dormant V2/SoftStopView.swift predecessor
// this screen used to track):
//   • Top bar: circular back + bookmark (save/pin) — no sort menu. WhereSia
//     has no per-stop sort control; the board is always number-sorted.
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

  /// null = default (the soonest service). Set when an ALL SERVICES row is
  /// tapped, promoting that service into the hero card. Mirrors iOS
  /// WSBusStopView's `featuredNo`.
  String? _featuredNo;

  /// Inline "Route · N stops to `<dest>`" disclosure under the hero.
  bool _routeExpanded = false;

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
            final featured = _featuredService(sorted);
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
                  // ── Hero (featured service — soonest by default, or the
                  // ALL SERVICES row last tapped) ─────────────────────────
                  // Mirrors iOS WSBusStopView.heroCard: a gradient card with
                  // that ONE service's own 3-slot NEXT/2ND/3RD departure
                  // board (each slot its own crowd word) plus an inline
                  // route-timeline disclosure below it. No ring on this
                  // screen — the countdown ring is Nearby-exclusive.
                  if (loaded && featured != null) ...[
                    _heroCard(context, featured),
                    const SizedBox(height: 10),
                    _routeCard(context, featured),
                    const SizedBox(height: 20),
                  ],
                  // ── Arrivals section ────────────────────────────────────
                  _arrivalSection(context, state, sorted, featured),
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

  // ── Hero ────────────────────────────────────────────────────────────────
  // ONE gradient hero per screen (soft-blue-design.md §4), rebuilt 2026-07-25
  // to match iOS WSBusStopView.heroCard exactly: a single FEATURED service —
  // soonest by default, or whichever ALL SERVICES row was last tapped
  // (`_featuredNo`) — with row 1 (number tile · "to <dest>" · "via <road>" ·
  // Alert-me pill) and row 2 (that service's OWN next 3 arrivals as a
  // NEXT/2ND/3RD board, each slot its own crowd word). Deliberately NOT the
  // old "first 3 distinct services" board — that discarded the per-bus 2nd/
  // 3rd arrival data the LTA feed already gives us. No ring here (spec item
  // 4b: the countdown ring is Nearby-exclusive).

  /// Soonest-by-default, or the row last promoted via `_featuredNo`. Mirrors
  /// iOS `featured`.
  Service? _featuredService(List<Service> sorted) {
    if (sorted.isEmpty) return null;
    if (_featuredNo != null) {
      final hit = sorted.where((s) => s.no == _featuredNo).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    return _soonest(sorted) ?? sorted.first;
  }

  /// The service with the lowest live ETA — mirrors iOS `wsSoonest`.
  Service? _soonest(List<Service> sorted) {
    if (sorted.isEmpty) return null;
    final now = DateTime.now();
    var best = sorted.first;
    var bestSec = _liveSec(best, now);
    for (final s in sorted.skip(1)) {
      final sec = _liveSec(s, now);
      if (sec < bestSec) {
        best = s;
        bestSec = sec;
      }
    }
    return best;
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

  Widget _heroCard(BuildContext context, Service featured) {
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
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 14),
          // Row 2: the departure board — NEXT / 2ND / 3RD, each slot this
          // service's own time + crowd word.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      width: 1,
                      height: 48,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 14),
                    child: i < entries.length
                        ? _boardSlot(entries[i], i)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static const _ordinalLabels = ['NEXT', '2ND', '3RD'];

  Widget _boardSlot(({int sec, Load? load}) entry, int index) {
    final eta = fmtEta(entry.sec);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _ordinalLabels[index],
          style: SoftBlue.sans(10, weight: FontWeight.bold, color: Colors.white)
              .copyWith(letterSpacing: 0.6)
              .copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: eta.big,
                style: SoftBlue.mono(
                  index == 0 ? 30 : 23,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (eta.big != 'Arr')
                TextSpan(
                  text: ' min',
                  style: SoftBlue.sans(
                    index == 0 ? 12 : 11,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
        Text(
          _crowdShort(entry.load),
          style: SoftBlue.sans(
            11,
            weight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  /// Per-slot crowd word (spec item 1): "Seats"/"Stand"/"Full", or "—" when
  /// unknown for that specific bus — mirrors iOS `Load.wsShort` exactly
  /// (deliberately not `CrowdMeter`'s "Limited"/"Standing" — those are tuned
  /// for row contexts, not the 3-across board).
  String _crowdShort(Load? load) {
    return switch (load) {
      Load.sea => 'Seats',
      Load.sda => 'Stand',
      Load.lsd => 'Full',
      null => '—',
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

  // ── Inline route timeline (spec item 3) ─────────────────────────────────
  // A toggle card under the hero — "Route · N stops to <dest> / View route"
  // — that expands into a compact timeline: the bus's live position (when
  // known and before your stop, with a "N stops" gap), then every stop from
  // yours to the terminus. Reuses SoftBusScreen's data model (RouteInfo /
  // RouteStopLive / BusProgress) rather than the deleted RouteTimeline
  // widget. Mirrors iOS WSBusStopView's `routeCard`/`routeTimeline`.

  Widget _routeCard(BuildContext context, Service featured) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleRoute(featured),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _routeToggleTitle(featured),
                    style: t.sans(13, weight: FontWeight.w600, color: t.fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _routeExpanded ? 'Hide route ▴' : 'View route ▾',
                  style: t.sans(12, weight: FontWeight.w600, color: t.accent),
                ),
              ],
            ),
          ),
          if (_routeExpanded) ...[
            const SizedBox(height: 10),
            _routeTimelineBody(context, featured),
          ],
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

  void _toggleRoute(Service featured) {
    final expand = !_routeExpanded;
    setState(() {
      _routeExpanded = expand;
      if (!expand) _showPreviousStops = false;
    });
    if (expand) {
      // Pin the hero on this service while the route is open — matches iOS
      // (the auto "soonest" swap used to flip services mid-scroll while the
      // route was open).
      setState(() => _featuredNo = featured.no);
      _loadRoute(featured.no);
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
    setState(() {
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
      constraints: const BoxConstraints(maxHeight: 260),
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
      onTap: () => setState(() => _showPreviousStops = !_showPreviousStops),
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
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            Text(
              _metaline(),
              style: SoftBlue.mono(11.5, color: SoftBlue.sub),
            ),
            if (interchange != null) ...[
              Text(' · ', style: SoftBlue.mono(11.5, color: SoftBlue.sub)),
              _interchangeFragment(context, interchange),
            ],
          ],
        ),
      ],
    );
  }

  /// "`<stopCode> · <distance>`" — distance omitted when there's no GPS fix,
  /// or the reading is under 50m (too close to be meaningful) or over 50km
  /// (a stale/bad fix, not worth showing) per spec item 4a.
  String _metaline() {
    final ds = DataStore.shared;
    final code = widget.stopCode;
    final loc = LocationService.shared.lastLocation;
    final latLon = ds.stopLatLon(code);
    String? distance;
    if (loc != null && latLon != null) {
      final metres = haversine(loc.lat, loc.lon, latLon.lat, latLon.lon);
      if (metres >= 50 && metres <= 50000) {
        distance = '${fmtDistance(metres.round())} away';
      }
    }
    return distance == null ? code : '$code · $distance';
  }

  /// Tappable "[line bullets] Station Name" fragment appended to the meta
  /// line when this stop is at/near an MRT interchange — opens that
  /// station's detail screen (spec item 4a; replaces the old standalone
  /// interchange card).
  Widget _interchangeFragment(
    BuildContext context,
    ({MrtStation resolved, MrtGeoStation station}) interchange,
  ) {
    final resolved = interchange.resolved;
    return Semantics(
      button: true,
      label: '${resolved.name} MRT station',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openInterchangeStation(context, interchange.station),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in resolved.codes.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.color,
                    borderRadius: BorderRadius.circular(LyneRadius.full),
                  ),
                  child: Text(
                    c.code,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 2),
            Text(
              resolved.name,
              style: SoftBlue.mono(11.5, weight: FontWeight.w600, color: SoftBlue.sub),
            ),
          ],
        ),
      ),
    );
  }

  // ── Arrivals ───────────────────────────────────────────────────────────────

  // No "Arrivals" header/sort-pill row: iOS goes straight from the title
  // block (or interchange card) into the service rows with no section
  // label at all — matches WSBusStopView exactly.
  Widget _arrivalSection(
    BuildContext context,
    ArrivalState? state,
    List<Service> sorted,
    Service? featured,
  ) {
    // The featured service is promoted into the hero — it's excluded from
    // ALL SERVICES below rather than shown twice (spec item 2, differs from
    // the pre-2026-07-25 Android behaviour that duplicated it in both
    // places).
    final rest = featured == null
        ? sorted
        : sorted.where((s) => s.no != featured.no).toList();
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
          if (rest.isNotEmpty) _arrivalsList(context, rest),
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

    // No mid-list MREC any more — this screen's single ad is the anchored
    // banner in [SoftDetailBottomBar] (owner placement redesign 2026-07-07).

    // SlidableAutoCloseBehavior: opening one row's Notify action closes any
    // other open one (shared 'arrivals' group tag).
    return SlidableAutoCloseBehavior(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
  // Neutral route tile (with a blue bell badge when armed) · destination
  // secondary · ETA primary in a fixed-width trailing column · deck/
  // wheelchair/"then…"/crowd (ALWAYS rendered, "—" when unknown) on a second
  // line. Tapping the row PROMOTES that service into the hero (spec item 2)
  // rather than navigating away; a separate trailing "Track" chevron still
  // opens the full SoftBusScreen so the richer tracking view stays
  // reachable. Per-bus alert/favourite management is a swipe action (the
  // Material-idiomatic stand-in for iOS's long-press context menu).

  Widget _busRow(BuildContext context, Service bus) {
    final t = context.t;
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed);
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
    // The blue "pulling in" mark — reserved for a monitored arrival under a
    // minute out. Matches iOS exactly: gated on `svc.monitored` only, not on
    // feed recency (a monitored bus stays "arriving" even if the stop's feed
    // itself has gone briefly stale). Static (no pulsing — owner-flagged as
    // distracting on iOS; the capsule + row wash carry it instead).
    final arrivingNow = bus.monitored && fmtEta(leadSec).big == 'Arr';

    return Semantics(
      label: 'Bus ${bus.no} to ${bus.dest}',
      hint: arrivingNow
          ? 'Bus ${bus.no} is arriving now. Tap to feature; use Track to open.'
          : 'Tap to feature bus ${bus.no}; use Track to open',
      button: true,
      child: InkWell(
        onTap: () => setState(() => _featuredNo = bus.no),
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
              // A solid blue bell badge overlays it when this service has an
              // armed arrival alert (spec item 4).
              _routeTileWithAlertBadge(bus.no, t, alerted: alerted),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ETA primary (fixed-width trailing column so it aligns
                    // down the card) · destination secondary (spec item 4).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            bus.dest.isEmpty ? 'Bus ${bus.no}' : bus.dest,
                            style: t.sans(
                              14,
                              weight: FontWeight.w500,
                              color: t.dim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: arrivingNow
                                ? _arrivingCapsule(t)
                                : _leadEta(t, leadSec, conf),
                          ),
                        ),
                      ],
                    ),
                    _secondLine(t, bus, later),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // "Track" — opens the full SoftBusScreen (spec item 2's
              // "separate affordance"). The row body itself just promotes.
              Semantics(
                button: true,
                label: 'Track bus ${bus.no}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => widget.onOpenBus(bus.no),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: t.faint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [_routeTile] plus a small solid-blue bell overlay when this service has
  /// an armed arrival alert at this stop (spec item 4).
  Widget _routeTileWithAlertBadge(
    String svc,
    LyneTheme t, {
    required bool alerted,
  }) {
    if (!alerted) return _routeTile(svc, t);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _routeTile(svc, t),
        Positioned(
          top: -5,
          right: -5,
          child: Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
            child: Icon(
              Icons.notifications_rounded,
              size: 10,
              color: t.contrastFg,
            ),
          ),
        ),
      ],
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
    // Crowd word is ALWAYS rendered ("—" when unknown) — spec item 4,
    // 2026-07-25 field-test decision; no longer gated on `bus.monitored`
    // (a schedule-only ghost row used to hide the word entirely, which read
    // as the row having nothing to say rather than an honest "—").
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
          _rowCrowdWord(t, bus.load),
        ],
      ),
    );
  }

  /// ALL SERVICES row crowd word — ALWAYS rendered, "—" when unknown (spec
  /// item 4, 2026-07-25 field-test decision). Deliberately NOT the shared
  /// [CrowdMeter] (which keeps crowd colour-neutral everywhere else per an
  /// earlier 2026-07-03 decision): this row's word tints amber for standing
  /// room and RED (not amber) for a full/limited bus, matching iOS
  /// WSBusStopView's row-level `load == .sda ? amber : load == .lsd ? red :
  /// sub` exactly.
  Widget _rowCrowdWord(LyneTheme t, Load? load) {
    return Text(
      switch (load) {
        Load.sea => 'Seats',
        Load.sda => 'Standing',
        Load.lsd => 'Full',
        null => '—',
      },
      style: t.mono(
        10.5,
        weight: load == Load.sea || load == null
            ? FontWeight.w500
            : FontWeight.w600,
        color: switch (load) {
          Load.sda => t.warn,
          Load.lsd => t.crit,
          _ => t.dim,
        },
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
