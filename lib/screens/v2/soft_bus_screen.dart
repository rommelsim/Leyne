// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// Mirrors iOS WSTrackBusView (ios-native/Leyne/WhereSia/WSTrackBusView.swift)
// structurally AND for content, not just spacing (owner punch-list "Bus
// view", 2026-07-03 — the two platforms had drifted to genuinely different
// screens; this rebuild closes that gap). Layout:
//   1. Top bar — back · "Bus {svc}" title · info. Unchanged from the prior
//      pass (owner punch-list Section F, items 10/12/13) — iOS's bar carries
//      only back + a compact title + info, so there is no overflow menu; see
//      the comment on [_buildTopBar] for where each former menu action
//      landed.
//   2. Hero — the ONE card on this screen (matches iOS's carded `liveCard`
//      exactly): a neutral "165" route tile + "TOWARD / {dest}" on the left,
//      a live/crowd status row below it (or "Waiting for the next bus…"),
//      and a big right-aligned ETA numeral + "MIN TO YOUR STOP" caption.
//      There is NO separate "Towards {dest}" / LIVE row outside the card any
//      more — iOS folds both into the card, so the old `_buildDestRow`
//      section is gone and its content lives in the hero now.
//      Deck type, wheelchair icon, arrival clock time and the "Then N · N
//      min" next-two preview are DROPPED, not relocated: WSTrackBusView
//      doesn't show them and neither does WSServiceInfoView (both checked,
//      2026-07-03) — there is nowhere on iOS this data appears, so Android
//      matching content means dropping it here too.
//   3. Route — "ROUTE ── N stops" header, the direction toggle (only when
//      the service runs >1 way), then a WINDOWED timeline: a collapsed
//      lead-in ("Show N earlier stops · from X") when the bus/your-stop
//      focus is deep into a long route, the stops immediately around the
//      live bus + your stop, a "BUS {svc} is here" node between the two
//      stops it's currently between, your stop rendered as a highlighted
//      card (accent bar + "YOUR STOP" overline + live ETA + MRT
//      interchange), then a collapsed tail ("Show N more stops to Y").
//      Built directly in this file rather than via the shared
//      `widgets/v2/route_timeline.dart` `RouteTimeline` widget — that
//      widget's whole visual language (checkmark-passed dots, an inner
//      "ROUTE · BUS N · stops away" header, an ALIGHT chip) is the OLD
//      pre-WhereSia design and doesn't match WSTrackBusView's structure at
//      all (it also duplicated this screen's own "ROUTE" header — a real
//      double-heading bug). File ownership for this punch-list pass is
//      scoped to this screen only, so rather than editing that shared
//      widget this screen stopped calling it; see the end-of-task report for
//      the resulting dead-code flag (`RouteTimeline` now has zero remaining
//      call sites anywhere in the app — grep-verified).
//      Bare on the screen background — no card — matching iOS's Route
//      section, which is a plain VStack directly on ws.bg.
//   4. CTA — "Alert me 1 stop before" pinned above the ad banner, the one
//      primary action on this screen (iOS parity), unchanged.
//
// First/last bus times live in Service Info (the info button's destination)
// only, matching iOS's WSServiceInfoView — not duplicated here.
//
// "Stops away" / the bus position come from the estimated bus index (live GPS
// snapped to the nearest route stop, else an ETA estimate) — no map rendering
// (see memory "android-no-map": the map is iOS-only).
//
// Type sizes below are ported from WSTrackBusView 1:1 for anything >= 11pt,
// and floored to exactly 11pt for anything iOS renders smaller (9/9.5/10.5pt
// eyebrows and captions) per the design-remake branch's Android type-scale
// floor (owner directive, 2026-07-03) — never render body/meta text below
// 11pt on Android even where iOS goes smaller.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../data/bus_progress.dart';
import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../data/mrt_stations.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_service_info_screen.dart';
import 'soft_stop_screen.dart';

// ─── Screen ─────────────────────────────────────────────────────────────
class SoftBusScreen extends StatefulWidget {
  const SoftBusScreen({
    super.key,
    required this.stopCode,
    required this.svc,
    required this.onBack,
    this.fullRoute = false,
    this.onTab,
    this.tabSelection,
  });
  final String stopCode;
  final String svc;
  final VoidCallback onBack;

  /// When opened from a bus search there's no "your stop" context, so the
  /// route timeline shows the WHOLE route (anchored at the service origin)
  /// instead of the narrow approach window used when arriving at a real stop.
  /// Android-only — WSTrackBusView has no equivalent search entry point, so
  /// this flag (and the flat, un-windowed timeline it selects) has nothing to
  /// mirror on iOS; kept as-is per the "don't change data wiring" brief.
  final bool fullRoute;

  /// Kept for callers that chain further pushes (e.g. [_openStop] re-opening
  /// a [SoftStopScreen]) — this screen's own bottom slot is always the
  /// pushed-detail ad banner (see [SoftDetailBottomBar]), not a tab bar.
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftBusScreen> createState() => _SoftBusScreenState();
}

class _SoftBusScreenState extends State<SoftBusScreen>
    with WidgetsBindingObserver {
  // ── Route data ──────────────────────────────────────────────────────
  RouteInfo? _route;
  ServiceRoute? _serviceRoute;
  // False until the (deferred) route fetch resolves — drives the route
  // section's loading state so we never show "Route unavailable" over data
  // that just hasn't landed yet.
  bool _routeLoaded = false;
  int _dirIndex = 0;

  // ── Timeline windowing (mirrors iOS WSTrackBusView's @State showEarlier /
  // showLater) — whether the collapsed lead-in / tail run of stops is
  // expanded. Not reset on a direction switch, matching iOS.
  bool _showEarlierStops = false;
  bool _showLaterStops = false;

  // Periodic ticker (1.5 s) — keeps this stop's arrivals fresh while the view
  // is open (the global app tick only refreshes pinned / open-card stops).
  Timer? _ticker;

  // ── Lifecycle ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
      // Defer the heavy route-data fetch until the push-transition animation
      // completes so the enter slide runs at full frame-rate. Fall back to an
      // immediate call if ModalRoute or its animation is unavailable (e.g.
      // deep-link on the very first frame before navigation is set up).
      final route = ModalRoute.of(context);
      final animation = route?.animation;
      if (animation != null) {
        animation.addStatusListener(_onRouteAnimationStatus);
      } else {
        _loadRoute();
      }
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      // Skip the network refresh when this screen is covered or transitioning.
      // ModalRoute.isCurrent is false during push/pop of a screen on top of us.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      DataStore.shared.ensureArrivals(widget.stopCode);
    });
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // One-shot: remove immediately so we don't accumulate listeners on
      // repeat navigations to this screen within the same state lifecycle.
      ModalRoute.of(
        context,
      )?.animation?.removeStatusListener(_onRouteAnimationStatus);
      _loadRoute();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from background: the ticker was suspended along with the
    // isolate, so arrivals can be minutes old by the time the user is back
    // looking at this screen — refetch immediately instead of waiting for
    // the next tick or a manual pull-to-refresh (iOS WSTrackBusView parity:
    // onChange(of: scenePhase) forces the same refetch, commit 5c52c74).
    if (state == AppLifecycleState.resumed) {
      DataStore.shared.ensureArrivals(widget.stopCode, force: true);
    }
  }

  // ── Route loading ────────────────────────────────────────────────────
  Future<void> _loadRoute() async {
    final sr = await DataStore.shared.serviceRoute(
      serviceNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (mounted) {
      setState(() {
        _serviceRoute = sr;
        _routeLoaded = true;
        if (sr != null) {
          _dirIndex = sr.initialIndex;
          _route = _routeFromDir(sr.directions[_dirIndex]);
        }
      });
    }
  }

  RouteInfo _routeFromDir(RouteDirection dir) =>
      RouteInfo(stops: dir.stops, youIndex: dir.youIndex);

  RouteDirection? get _currentDir {
    final sr = _serviceRoute;
    if (sr == null || _dirIndex >= sr.directions.length) return null;
    return sr.directions[_dirIndex];
  }

  /// The direction that actually serves the tracked stop, regardless of
  /// which one is currently being browsed — mirrors iOS's `anchorDirection`.
  /// The hero card's destination text is grounded here (not the currently
  /// browsed direction) so switching the Route toggle never misrepresents
  /// which bus is actually being tracked.
  RouteDirection? get _anchorDir {
    final sr = _serviceRoute;
    if (sr == null || sr.directions.isEmpty) return null;
    for (final d in sr.directions) {
      if (d.anchorPresent) return d;
    }
    return sr.directions.first;
  }

  // ── Data helpers ─────────────────────────────────────────────────────
  Service? _liveService() {
    final a = DataStore.shared.arrivals[widget.stopCode];
    if (a == null || a.kind != ArrivalStateKind.loaded) return null;
    try {
      return a.services.firstWhere((s) => s.no == widget.svc);
    } on StateError {
      return null;
    }
  }

  /// The bus's actual position when LTA shares a GPS fix; null otherwise.
  ({double lat, double lon})? _liveBusCoord() {
    final svc = _liveService();
    final lat = svc?.busLat;
    final lon = svc?.busLon;
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      return (lat: lat, lon: lon);
    }
    return null;
  }

  /// Where the bus is along the route, as a stop index — grounded in the GPS
  /// fix (nearest route stop) when present, else the ETA estimate. Null
  /// without anchor context. Mirrors iOS's `displayBusIndex` (the same
  /// null-without-anchor-context gate), but recomputed every tick from the
  /// live ETA instead of iOS's fetch-time-only snapshot — a smoother,
  /// already-existing Android enrichment kept as-is (not a layout change).
  int? _estimatedBusIndex() {
    if (widget.fullRoute) return null;
    final dir = _currentDir;
    if (dir == null || !dir.anchorPresent || dir.stops.isEmpty) return null;
    final svc = _liveService();
    if (svc == null) return null;
    final you = dir.youIndex.clamp(0, dir.stops.length - 1);

    final c = _liveBusCoord();
    final gpsNearest = c == null
        ? null
        : BusProgress.nearestIndex([
            for (final s in dir.stops) (lat: s.lat, lon: s.lon),
          ], c);
    final lastRefresh = DataStore.shared.lastRefresh(widget.stopCode);
    final elapsed = lastRefresh != null
        ? DateTime.now().difference(lastRefresh).inSeconds.toDouble()
        : 0.0;
    return BusProgress.busIndex(
      youIndex: you,
      gpsNearest: gpsNearest,
      etaSec: svc.etaSec,
      elapsedSec: elapsed,
    );
  }

  /// Live ETA seconds, recomputed from arrivalDate for a smooth countdown.
  int _liveEtaSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.t.bg,
      // Pushed detail screen: ad banner only, no tab bar — iOS hides its
      // floating tab bar on pushed routes (WSRoot.swift) because it covered
      // Track Bus's pinned CTA; Android mirrors that here.
      bottomNavigationBar: const SoftDetailBottomBar(),
      // OUTER listener: DataStore only — rebuilds only when arrivals data
      // changes from a network fetch. The route-progress/timeline subtree
      // lives here and is therefore NOT rebuilt every second.
      body: ListenableBuilder(
        listenable: DataStore.shared,
        builder: (context, _) {
          final t = context.t;
          return SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(t),
                // Fill-or-scroll: content hugs its natural height when
                // short; a long route makes the whole area scroll
                // instead of overflowing. Pull-to-refresh re-fetches
                // arrivals AND the route (iOS WSTrackBusView parity:
                // .refreshable does both).
                Expanded(
                  child: RefreshIndicator(
                    color: t.accent,
                    onRefresh: () async {
                      await DataStore.shared.refreshArrivals(widget.stopCode);
                      await _loadRoute();
                    },
                    child: LayoutBuilder(
                      builder: (ctx, c) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                // INNER listener: AppModel only —
                                // rebuilds every second so the ETA
                                // countdown ticks. Only _buildHeroCard
                                // (which reads DateTime.now()) is inside
                                // it; everything else stays in the outer
                                // DataStore scope.
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: ListenableBuilder(
                                    listenable: AppModel.shared,
                                    builder: (context, _) => _buildHeroCard(t),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Bare on the screen background — NOT a
                                // card. iOS's Route section (WSSectionHeader
                                // + timeline) sits directly on ws.bg inside a
                                // plain ScrollView; only the hero card above
                                // is carded.
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: _buildRouteSection(t),
                                ),
                                const SizedBox(height: 16),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The one primary action on this screen (iOS
                // WSTrackBusView parity) — its own AppModel listener so
                // the label/icon flips the instant the alert toggles.
                ListenableBuilder(
                  listenable: AppModel.shared,
                  builder: (context, _) => _buildAlertCta(t),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Top bar — back · "Bus {svc}" title · info. No overflow button
  //    (owner item 13, 2026-07-03): iOS's bar carries only back + the
  //    compact title + info, so the former save/manage-alerts/share menu is
  //    gone rather than folded in wholesale —
  //      • Save service   → already lives on SoftServiceInfoScreen's own
  //        bookmark toggle (opened by the info button right next to this
  //        title), which bookmarks the same (serviceNo, stop) pair. Nothing
  //        to add — it was already a fully equivalent, reachable action.
  //      • Manage alerts  → DROPPED. Its only remaining job (pause/resume,
  //        delete, reorder) is already done inline on the Alerts tab
  //        (SoftAlertsScreen — see its 2026-07-02 owner decision doc
  //        comment), which superseded routing to ManageAlertsScreen from
  //        everywhere except this one menu. Removing this entry leaves
  //        ManageAlertsScreen with zero call sites (grep-verified) — flagged
  //        to the owner, same as the already-accepted SoftSettingsScreen gap
  //        noted in soft_alerts_screen.dart.
  //      • Share bus      → DROPPED. WSTrackBusView has no share affordance
  //        at all on this screen, and no other Android screen offers "share
  //        a bus" either (grep-verified) — nothing to fold in, this was an
  //        Android-only addition with no iOS equivalent to mirror.
  //    The boarding-alert toggle lives at the bottom as the single primary
  //    CTA (iOS WSTrackBusView parity: the header carries only back + title
  //    + info). ─────────────────────────────────────────────────────────
  Widget _buildTopBar(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _CircleButton(
            onTap: widget.onBack,
            semanticsLabel: 'Back',
            child: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bus ${widget.svc}',
              style: t.sans(24, weight: FontWeight.w700, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            onTap: _openServiceInfo,
            semanticsLabel: 'Bus ${widget.svc} service info',
            child: Icon(Icons.info_outline_rounded, size: 20, color: t.fg),
          ),
        ],
      ),
    );
  }

  /// Route badge + destination + operator/category, first/last-bus and
  /// frequency-band cards — the info circle-button opens this alongside the
  /// live tracking view (iOS parity: WSTrackBusView's bar info button).
  void _openServiceInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftServiceInfoScreen(
          serviceNo: widget.svc,
          fromStop: widget.stopCode,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  // ── Boarding-alert toggle ───────────────────────────────────────────────
  bool get _boardingAlertOn =>
      AppModel.shared.alertFor(
        kind: AlertKind.arrival,
        busNo: widget.svc,
        stopCode: widget.stopCode,
      ) !=
      null;

  Future<void> _toggleBoardingAlert() async {
    // One-tap toggle + Undo snackbar (shared with Home/Stop). Adding enables
    // notifications on first use; the lock-screen live view is automatic.
    await toggleArrivalAlert(
      busNo: widget.svc,
      stopCode: widget.stopCode,
      stopName: DataStore.shared.stopName(widget.stopCode),
      dest: _liveService()?.dest ?? '',
    );
    if (mounted) setState(() {});
  }

  // ── Hero card ────────────────────────────────────────────────────────
  // Content + hierarchy ported 1:1 from WSTrackBusView's `liveCard`: a
  // neutral route tile + "TOWARD / {dest}" leading, a LIVE/crowd status row
  // beneath it (or a waiting message), and a big trailing ETA numeral with
  // its unit caption. This is the one card on the whole screen.
  Widget _buildHeroCard(LyneTheme t) {
    final s = _liveService();
    final now = DateTime.now();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        // 14 matches iOS's explicit card-radius choice for this screen
        // (WSTrackBusView comment: matches the app's card-radius family —
        // a larger radius curved the corner so far "ROUTE" below read as
        // misaligned against the card edge).
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _heroRouteTile(t),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'TOWARD',
                            style: t
                                .sans(11, weight: FontWeight.w800, color: t.dim)
                                .copyWith(letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _destText(s),
                            style: t.sans(
                              15.5,
                              weight: FontWeight.w800,
                              color: t.fg,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _heroStatusRow(t, s),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _heroEtaColumn(t, s, now),
        ],
      ),
    );
  }

  /// The neutral "165" route tile — mirrors iOS's `RouteTile(size: .large)`:
  /// a flat panel (not the accent-filled `ServiceBadge` used elsewhere in
  /// the app), 46×40, mono bold.
  Widget _heroRouteTile(LyneTheme t) {
    return Container(
      // minWidth (not a fixed width) so a 4-char service like "961M" grows
      // the tile instead of wrapping/clipping inside it.
      constraints: const BoxConstraints(minWidth: 46),
      height: 40,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Text(
        widget.svc,
        maxLines: 1,
        softWrap: false,
        style: t.mono(16, weight: FontWeight.w700, color: t.fg),
      ),
    );
  }

  /// Destination text: the live service's own `dest` when a bus is tracked,
  /// else the anchor direction's terminus name (so the card still names a
  /// real destination before any bus has reported in) — mirrors iOS's
  /// `service?.dest ?? destName` fallback chain. "—" only when neither is
  /// known yet.
  String _destText(Service? s) {
    final live = s?.dest ?? '';
    final dest = live.isNotEmpty ? live : (_anchorDir?.destinationName ?? '');
    return dest.isEmpty ? '—' : dest;
  }

  /// "● LIVE · [crowd] Seats" or, when no bus is tracked yet, "Waiting for
  /// the next bus…" — mirrors iOS's `service?.load` gate exactly (in
  /// practice equivalent to "is a live bus tracked", since Android's
  /// `Service.load` is non-nullable once a live [Service] exists).
  Widget _heroStatusRow(LyneTheme t, Service? s) {
    if (s == null) {
      return Text(
        'Waiting for the next bus…',
        style: t.sans(12, weight: FontWeight.w600, color: t.dim),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // t.live — the Material You dynamic-colour equivalent of
        // WSTheme's fixed `accentSoft` blue (see LyneTheme.withAccent).
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.live, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          'LIVE',
          style: t
              .mono(11, weight: FontWeight.w700, color: t.live)
              .copyWith(letterSpacing: 1.1),
        ),
        const SizedBox(width: 7),
        Text('·', style: t.mono(11, color: t.faint)),
        const SizedBox(width: 7),
        // The app's established crowd idiom (person-glyph triplet + word),
        // already used on Home/Saved/Stop — kept here rather than
        // introducing a one-off bar-style gauge to match iOS's CrowdGauge
        // pixel-for-pixel; that would need a new shared widget in
        // widgets/v2/confidence.dart, which is out of this file's ownership
        // for this pass (flagged in the task report).
        CrowdMeter(load: s.load, compact: true),
      ],
    );
  }

  /// Big trailing ETA numeral + unit caption, or a bare "—" placeholder —
  /// mirrors iOS's trailing VStack exactly, including literally showing
  /// "Arr" (not a separate "Arriving" word) at the smaller 30pt size when
  /// the bus is at the stop.
  Widget _heroEtaColumn(LyneTheme t, Service? s, DateTime now) {
    if (s == null) {
      return Text(
        '—',
        style: t.mono(34, weight: FontWeight.w700, color: t.faint),
      );
    }
    final eta = fmtEta(_liveEtaSec(s, now));
    final arriving = eta.big == 'Arr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eta.big,
          style: t.mono(
            arriving ? 30 : 40,
            weight: FontWeight.w700,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          arriving ? 'AT YOUR STOP' : 'MIN TO YOUR STOP',
          style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.7),
        ),
      ],
    );
  }

  // ── Route — header · direction toggle · windowed timeline ──────────────
  Widget _buildRouteSection(LyneTheme t) {
    final hasRoute =
        _routeLoaded &&
        _serviceRoute != null &&
        (_route?.stops.isNotEmpty ?? false);
    final dirs = _serviceRoute?.directions.length ?? 0;

    final Widget body;
    if (!_routeLoaded) {
      // Still fetching the route — a loading state, not an empty timeline.
      body = _routeLoadingState(t);
    } else if (!hasRoute) {
      // Fetch finished but returned no route (unavailable for this service).
      body = _routeUnavailableState(t);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _routeSectionHeader(t, _route!.stops.length),
          // Loop / single-direction services stay silent here; most
          // services run both ways. Sits directly under the ROUTE header and
          // above the timeline, exactly where WSTrackBusView places its
          // WSSegmented toggle (owner item 5, 2026-07-03) — the OLD Android
          // layout only looked displaced because RouteTimeline's own inner
          // "ROUTE · BUS N" header used to render a second heading between
          // this toggle and the actual stop rows; that inner header is gone
          // now that this screen builds its timeline directly.
          if (dirs > 1) ...[
            const SizedBox(height: 10),
            _routeDirectionToggle(t),
          ],
          const SizedBox(height: 12),
          _buildTimeline(t),
        ],
      );
    }

    // SizedBox, not Container — no fill/border/radius. Bare on t.bg, matching
    // iOS; width:double.infinity only keeps the loading/unavailable states
    // (Column(mainAxisSize: min) centred inside) full-width as before.
    return SizedBox(width: double.infinity, child: body);
  }

  /// "ROUTE ───── N stops" — mirrors iOS's WSSectionHeader recipe (uppercase
  /// heavy label · hairline rule · mono meta), directly on the screen
  /// background rather than inside a card.
  Widget _routeSectionHeader(LyneTheme t, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'ROUTE',
          style: t
              .sans(11, weight: FontWeight.w800, color: t.dim)
              .copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: t.line)),
        const SizedBox(width: 10),
        Text(
          '$count stop${count == 1 ? '' : 's'}',
          style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.5),
        ),
      ],
    );
  }

  /// Shown while the route fetch is in flight.
  Widget _routeLoadingState(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: t.dim),
          ),
          const SizedBox(height: 12),
          Text('Loading route…', style: t.sans(14, color: t.dim)),
        ],
      ),
    );
  }

  /// Shown when the fetch resolves with no route for this service.
  Widget _routeUnavailableState(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_rounded, size: 30, color: t.faint),
          const SizedBox(height: 10),
          Text('Route unavailable', style: t.sans(14, color: t.dim)),
        ],
      ),
    );
  }

  /// Opens another stop's own arrivals from a tapped route-timeline row (iOS
  /// parity: every non-"your stop" row pushes that stop). `onOpenBus`
  /// re-enters this same screen for whichever bus the user picks there,
  /// mirroring the self-referential push SoftStopScreen already does for its
  /// own "nearby station's bus stop" rows.
  void _openStop(String code) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftStopScreen(
          stopCode: code,
          onBack: () => Navigator.of(context).pop(),
          onOpenBus: (svc) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SoftBusScreen(
                stopCode: code,
                svc: svc,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          onSeeAll: () {},
          onTab: widget.onTab,
          tabSelection: widget.tabSelection,
        ),
      ),
    );
  }

  Widget _routeDirectionToggle(LyneTheme t) {
    final sr = _serviceRoute!;
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: t.liveBg,
        foregroundColor: t.dim,
        selectedForegroundColor: t.contrastFg,
        selectedBackgroundColor: t.contrast,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LyneRadius.full),
        ),
        textStyle: t.sans(13, weight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      segments: [
        for (var i = 0; i < sr.directions.length; i++)
          ButtonSegment<int>(
            value: i,
            label: Text(
              'To ${_shortDest(sr.directions[i].destinationName)}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
      selected: {_dirIndex},
      onSelectionChanged: (selection) {
        final newIdx = selection.first;
        if (newIdx == _dirIndex) return;
        setState(() {
          _dirIndex = newIdx;
          _route = _routeFromDir(sr.directions[newIdx]);
        });
      },
    );
  }

  /// Keeps direction-switcher labels tight — mirrors iOS's `shortDest`
  /// exactly (strip " Int"/" Stn", cap at 12 chars) so the two platforms'
  /// toggles read consistently.
  static String _shortDest(String s) {
    final trimmed = s.replaceAll(' Int', '').replaceAll(' Stn', '');
    return trimmed.length > 12 ? '${trimmed.substring(0, 12)}…' : trimmed;
  }

  // ── Timeline ─────────────────────────────────────────────────────────
  // Windowed stop list built directly against `_route`/`_estimatedBusIndex`
  // — mirrors WSTrackBusView's `timeline` computed property line-for-line
  // (see the file-header comment for why this no longer goes through the
  // shared RouteTimeline widget).
  Widget _buildTimeline(LyneTheme t) {
    final route = _route;
    if (route == null || route.stops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Text(
          'Loading route…',
          style: t.sans(13, weight: FontWeight.w500, color: t.dim),
        ),
      );
    }
    final dir = _currentDir;
    // Browsing the OTHER direction (the one that doesn't serve this stop)
    // shows its full, plain route instead of guessing where a bus that
    // isn't running that way would be — mirrors iOS's `anchorHere` gate,
    // which also backs `_estimatedBusIndex()`'s own null-without-anchor
    // rule above.
    final anchorHere = !widget.fullRoute && (dir?.anchorPresent ?? true);
    final stops = route.stops;
    final you = anchorHere ? route.youIndex.clamp(0, stops.length - 1) : -1;
    final busIdx = anchorHere ? _estimatedBusIndex() : null;
    final baseStart = !anchorHere
        ? 0
        : (busIdx != null
              ? busIdx.clamp(0, you)
              : (you - 6).clamp(0, stops.length - 1));
    final baseEnd = anchorHere
        ? (you + 1).clamp(0, stops.length - 1)
        : stops.length - 1;
    final start = _showEarlierStops ? 0 : baseStart;
    final end = _showLaterStops ? stops.length - 1 : baseEnd;
    final liveService = _liveService();

    final children = <Widget>[];
    if (baseStart > 0) {
      children.add(
        _collapseChip(
          t,
          expanded: _showEarlierStops,
          collapsedLabel:
              'Show $baseStart earlier stop${baseStart == 1 ? '' : 's'} · '
              'from ${stops.first.name}',
          expandedLabel: 'Hide earlier stops',
          onTap: () => setState(() => _showEarlierStops = !_showEarlierStops),
        ),
      );
    }
    for (var i = start; i <= end; i++) {
      children.add(
        _timelineStepRow(
          t,
          stop: stops[i],
          passed: busIdx != null && i < busIdx,
          isYou: i == you,
          liveService: liveService,
        ),
      );
      if (busIdx != null && i == busIdx && i < end) {
        children.add(_timelineVehicleRow(t, liveService: liveService));
      }
    }
    final more = (stops.length - 1) - baseEnd;
    if (more > 0) {
      children.add(
        _collapseChip(
          t,
          expanded: _showLaterStops,
          collapsedLabel:
              'Show $more more stop${more == 1 ? '' : 's'} to ${stops.last.name}',
          expandedLabel: 'Hide later stops',
          onTap: () => setState(() => _showLaterStops = !_showLaterStops),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// One route stop: rail (dot + downward connector) + either the plain
  /// tappable stop body or, for `isYou`, the highlighted "your stop" card.
  Widget _timelineStepRow(
    LyneTheme t, {
    required RouteStopLive stop,
    required bool passed,
    required bool isYou,
    required Service? liveService,
  }) {
    final ic = resolveMrtStation(stop.name);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _timelineDot(t, isYou: isYou, passed: passed),
                ),
                Expanded(
                  child: Center(
                    child: Container(width: 3, color: passed ? t.fg : t.line),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: isYou
                ? _yourStopBody(t, stop, ic, liveService)
                : _regularStopBody(t, stop, ic, passed: passed),
          ),
        ],
      ),
    );
  }

  /// The rail dot — filled accent (isYou), a faint-filled solid ring
  /// (passed), or a hollow faint ring (upcoming). Mirrors WSTrackBusView's
  /// `stepRow` circle exactly (fill/stroke/size per state).
  Widget _timelineDot(
    LyneTheme t, {
    required bool isYou,
    required bool passed,
  }) {
    final size = isYou ? 15.0 : 13.0;
    final strokeWidth = isYou ? 3.0 : 2.5;
    final fill = isYou ? t.live : (passed ? t.faint : t.bg);
    final stroke = isYou ? t.live : (passed ? t.fg : t.faint);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: stroke, width: strokeWidth),
      ),
    );
  }

  /// A plain, tappable route stop — name, stop code, and an MRT-interchange
  /// flag when it sits at a rail station. Opens that stop's own arrivals.
  Widget _regularStopBody(
    LyneTheme t,
    RouteStopLive stop,
    MrtStation? ic, {
    required bool passed,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openStop(stop.code),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stop.name,
              style: t.sans(
                14.5,
                weight: FontWeight.w700,
                color: passed ? t.dim : t.fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stop.code,
              style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.3),
            ),
            if (ic != null) ...[
              const SizedBox(height: 2),
              _interchangeFlag(t, 'MRT', ic.codes),
            ],
          ],
        ),
      ),
    );
  }

  /// The highlighted "your stop" card — blue leading bar, "YOUR STOP" (or
  /// "YOUR STOP · MRT INTERCHANGE") overline, stop name, the live ETA
  /// (the SAME number the hero card shows — no invented per-stop minute
  /// times, matching WSTrackBusView's header comment), and a "CHANGE FOR"
  /// interchange flag when applicable. Not tappable (matches iOS: no push
  /// action on your own stop).
  Widget _yourStopBody(
    LyneTheme t,
    RouteStopLive stop,
    MrtStation? ic,
    Service? liveService,
  ) {
    String? etaText;
    if (liveService != null) {
      final eta = fmtEta(_liveEtaSec(liveService, DateTime.now()));
      etaText = eta.big == 'Arr' ? 'Arriving now' : '~${eta.big} min';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line, width: 1),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // t.live — the dynamic-colour equivalent of WSTheme's fixed
                // accent blue (owner item 4, 2026-07-03).
                Container(width: 3, color: t.live),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ic != null
                              ? 'YOUR STOP · MRT INTERCHANGE'
                              : 'YOUR STOP',
                          style: t
                              .sans(11, weight: FontWeight.w800, color: t.dim)
                              .copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stop.name,
                          style: t.sans(
                            14.5,
                            weight: FontWeight.w700,
                            color: t.fg,
                          ),
                        ),
                        if (etaText != null) ...[
                          const SizedBox(height: 2),
                          Text(etaText, style: t.mono(11.5, color: t.dim)),
                        ],
                        if (ic != null) ...[
                          const SizedBox(height: 4),
                          _interchangeFlag(t, 'CHANGE FOR', ic.codes),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Train glyph + label + up to 3 colour-coded line-code chips — mirrors
  /// WSTrackBusView's `interchangeFlag`.
  Widget _interchangeFlag(LyneTheme t, String label, List<MrtCode> codes) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.train_rounded, size: 15, color: t.dim),
          const SizedBox(width: 7),
          Text(
            label,
            style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.5),
          ),
          const SizedBox(width: 6),
          for (final code in codes.take(3)) ...[
            _lineCodeChip(code),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// A single station-code roundel — white code on the line's brand colour.
  /// Mirrors WSTrackBusView's `LineBullet` (small size).
  Widget _lineCodeChip(MrtCode code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: code.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        code.code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// The live bus's node between two stops — "165" tile + "Bus 165 is
  /// here" + "between these stops" + the onboard crowd. Mirrors
  /// WSTrackBusView's `vehicleRow`. The WSPing pulsing-halo micro-animation
  /// is intentionally not replicated (a static tile is a faithful-enough
  /// Material rendition of the same information; adding a second animation
  /// controller to a screen that already runs a periodic arrivals ticker
  /// wasn't worth the risk for a structural punch-list pass).
  Widget _timelineVehicleRow(LyneTheme t, {required Service? liveService}) {
    final load = liveService?.load;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                // The rail column is 24dp wide but the tile is wider — an
                // OverflowBox lets it take its intrinsic width centred over
                // the rail (like iOS, where the chip overhangs the line)
                // instead of being clamped to 24dp, which word-wrapped the
                // service number (owner-reported on 4-char services).
                SizedBox(
                  width: 24,
                  height: 30,
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 34),
                      height: 30,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: t.surfaceHi,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.live, width: 1.5),
                      ),
                      child: Text(
                        widget.svc,
                        maxLines: 1,
                        softWrap: false,
                        style: t.mono(12, weight: FontWeight.w700, color: t.fg),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(child: Container(width: 3, color: t.line)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bus ${widget.svc} is here',
                    style: t.sans(12, weight: FontWeight.w700, color: t.fg),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'between these stops',
                        style: t.mono(11, color: t.dim),
                      ),
                      if (load != null) ...[
                        const SizedBox(width: 6),
                        Text('·', style: t.mono(11, color: t.faint)),
                        const SizedBox(width: 6),
                        CrowdMeter(load: load, compact: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tappable expand/collapse node standing in for a run of hidden stops —
  /// dotted rail + chevron + underlined label. Mirrors WSTrackBusView's
  /// shared `collapseChip` (used for both the leading and trailing run).
  Widget _collapseChip(
    LyneTheme t, {
    required bool expanded,
    required String collapsedLabel,
    required String expandedLabel,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 24, child: _DottedRail(color: t.faint)),
              const SizedBox(width: 15),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          expanded ? expandedLabel : collapsedLabel,
                          style: t
                              .mono(11, color: t.dim)
                              .copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CTA — the single primary action, pinned above the ad banner (iOS
  //    WSTrackBusView parity: "Alert me 1 stop before" is the one button on
  //    this screen). ────────────────────────────────────────────────────
  Widget _buildAlertCta(LyneTheme t) {
    final alerted = _boardingAlertOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Semantics(
        button: true,
        label: alerted
            ? 'Arrival tracking on for bus ${widget.svc}. Tap to cancel.'
            : 'Track arrival of bus ${widget.svc}',
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.contrast,
              foregroundColor: t.contrastFg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _toggleBoardingAlert,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  alerted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_outlined,
                  size: 19,
                  color: t.contrastFg,
                ),
                const SizedBox(width: 9),
                Text(
                  alerted
                      ? 'Alert set · tap to cancel'
                      : 'Alert me 1 stop before',
                  style: t.sans(
                    15,
                    weight: FontWeight.w800,
                    color: t.contrastFg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Circle icon button (top bar) ─────────────────────────────────────────────
/// A flat circular icon button — surface fill + 1px border, no drop shadow
/// (the shadow read as a grey smudge in light mode). 48×48 tap target around a
/// 40×40 visual circle, with a circle-clipped ripple.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.child,
    required this.onTap,
    this.semanticsLabel,
  });
  final Widget child;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Material(
            color: t.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line, width: 1),
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dotted vertical line filling its box — the collapsed-stops rail glyph.
/// Mirrors WSTrackBusView's `collapseChip` mask trick (a stack of short
/// rectangles) with a `CustomPainter` dash instead, so it stretches to fit
/// however tall the chip's label wraps rather than a hardcoded dash count.
class _DottedRail extends StatelessWidget {
  const _DottedRail({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DottedRailPainter(color));
}

class _DottedRailPainter extends CustomPainter {
  _DottedRailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 3.0;
    const gap = 3.0;
    final x = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      final yEnd = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRailPainter oldDelegate) =>
      oldDelegate.color != color;
}
