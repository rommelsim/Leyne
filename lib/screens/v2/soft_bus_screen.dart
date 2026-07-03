// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// Mirrors iOS WSTrackBusView (ios-native/Leyne/WhereSia/WSTrackBusView.swift)
// structurally: a live card, then the route, then a single pinned CTA.
// Android intentionally has NO map — see memory "android-no-map": the map is
// iOS-only (native MapKit); the route timeline is the substitute, not a
// secondary affordance behind a tap. Layout:
//   1. Top bar — back · info · more (save/manage alerts/share — an
//      Android-only overflow; WSTrackBusView itself carries neither, since
//      this screen is reached only after the user already picked a service).
//   2. Title   — "Bus {svc}" + "Towards {dest}" + LIVE
//   3. Hero    — ETA (a bare "—" when there's no live bus yet) + approach
//      context + crowd, then deck/wheelchair + next two (Android-only
//      enrichment — WSTrackBusView doesn't surface these on this screen).
//   4. Route   — "ROUTE · N stops" header + the full collapsible route
//      timeline (shared RouteTimeline widget), inline in the scroll — no
//      "tap to see the full route" modal step, matching iOS's single-scroll
//      structure.
//   5. CTA     — "Alert me 1 stop before" pinned above the ad banner, the
//      one primary action on this screen (iOS parity).
//
// First/last bus times live in Service Info (the info button's destination)
// only, matching iOS's WSServiceInfoView — not duplicated here.
//
// "Stops away" / the bus position come from the estimated bus index (live GPS
// snapped to the nearest route stop, else an ETA estimate) — no map rendering.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/alert_timing.dart';
import '../../data/bus_progress.dart';
import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/route_timeline.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'manage_alerts_screen.dart';
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

  // Periodic ticker (1.5 s) — keeps this stop's arrivals fresh while the view
  // is open (the global app tick only refreshes pinned / open-card stops).
  Timer? _ticker;

  // ── Transient confirmation toast ─────────────────────────────────────
  ({IconData icon, String text})? _toast;
  Timer? _toastTimer;

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
    _toastTimer?.cancel();
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

  List<SoftRouteStop> _timelineStops() {
    final r = _route;
    if (r == null) return const [];
    final dir = _currentDir;
    final youSeq = r.youIndex;
    final busSeq = _estimatedBusIndex();
    final showFull = widget.fullRoute || (dir != null && !dir.anchorPresent);
    final lead = BusProgress.timelineLead(
      busIndex: busSeq,
      youIndex: youSeq,
      stopsCount: r.stops.length,
    );
    final seg = showFull ? r.stops : r.stops.sublist(lead);
    final canMarkBoard =
        !widget.fullRoute && (dir == null || dir.anchorPresent);
    // The tracked bus's onboard crowd, attached only to the stop it's
    // currently snapped to (state == here) — mirrors iOS WSTrackBusView's
    // vehicle-row crowd gauge (RouteTimeline renders it next to "BUS HERE
    // NOW").
    final liveLoad = _liveService()?.load;
    return seg.map((stop) {
      final idx = r.stops.indexWhere((s) => s.code == stop.code);
      final state = BusProgress.stopState(
        idx: idx,
        busIndex: busSeq,
        youIndex: youSeq,
        canMarkBoard: canMarkBoard,
      );
      return SoftRouteStop(
        id: stop.code,
        name: stop.name,
        state: state,
        load: state == SoftRouteStopState.here ? liveLoad : null,
      );
    }).toList();
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
  /// fix (nearest route stop) when present, else the ETA estimate. Null without
  /// anchor context.
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

  /// Stops between the bus and your stop. Null without anchor context.
  int? _stopsRemaining() {
    final dir = _currentDir;
    final busIdx = _estimatedBusIndex();
    if (dir == null || busIdx == null || dir.stops.isEmpty) return null;
    final youIdx = dir.youIndex.clamp(0, dir.stops.length - 1);
    return (youIdx - busIdx).clamp(0, dir.stops.length);
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
          return Stack(
            children: [
              SafeArea(
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
                          await DataStore.shared.refreshArrivals(
                            widget.stopCode,
                          );
                          await _loadRoute();
                        },
                        child: LayoutBuilder(
                          builder: (ctx, c) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: c.maxHeight,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        0,
                                      ),
                                      child: _buildTitleBlock(
                                        context,
                                        t,
                                        _liveService(),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
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
                                        builder: (context, _) =>
                                            _buildHeroCard(t),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: _buildRouteSection(t),
                                    ),
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
              ),
              if (_toast != null) _buildToast(context, t),
            ],
          );
        },
      ),
    );
  }

  // ── 1. Top bar — back · info · more (save/manage alerts/share). The
  //    boarding-alert toggle lives at the bottom as the single primary CTA
  //    (iOS WSTrackBusView parity: the header carries only back + info). ───
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
          const Spacer(),
          _CircleButton(
            onTap: _openServiceInfo,
            semanticsLabel: 'Bus ${widget.svc} service info',
            child: Icon(Icons.info_outline_rounded, size: 20, color: t.fg),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: AppModel.shared,
            builder: (context, _) => _moreButton(t),
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

  /// Save service · manage alerts · share, folded into one overflow button so
  /// the header stays a clean back + info + more — matching iOS's minimal bar
  /// while keeping the save/share affordances the Android app already offers.
  /// (WSTrackBusView itself has no save/share on this screen — this is a
  /// deliberate Android addition, not something being mirrored from iOS.)
  Widget _moreButton(LyneTheme t) {
    final saved =
        AppModel.shared.isFavService(no: widget.svc, stop: widget.stopCode) ||
        AppModel.shared.isFavService(no: widget.svc, stop: null);
    return PopupMenuButton<String>(
      tooltip: 'More options',
      padding: EdgeInsets.zero,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      onSelected: (v) {
        if (v == 'save') {
          _toggleServiceSaved();
        } else if (v == 'manage') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ManageAlertsScreen()));
        } else if (v == 'share') {
          _shareBus();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              Icon(
                saved ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: t.dim,
              ),
              const SizedBox(width: 10),
              Text(
                saved ? 'Remove from saved' : 'Save bus ${widget.svc}',
                style: t.sans(14, color: t.fg),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manage',
          child: Row(
            children: [
              Icon(Icons.notifications_rounded, size: 18, color: t.dim),
              const SizedBox(width: 10),
              Text('Manage alerts', style: t.sans(14, color: t.fg)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.ios_share_rounded, size: 18, color: t.dim),
              const SizedBox(width: 10),
              Text('Share bus ${widget.svc}', style: t.sans(14, color: t.fg)),
            ],
          ),
        ),
      ],
      child: Semantics(
        button: true,
        label: 'More options for bus ${widget.svc}',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.line, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.more_vert_rounded, size: 20, color: t.fg),
            ),
          ),
        ),
      ),
    );
  }

  void _shareBus() {
    final text =
        'Bus ${widget.svc} from Stop ${widget.stopCode} — tracked on Leyne';
    Clipboard.setData(ClipboardData(text: text));
    _showToast(Icons.check_rounded, 'Bus ${widget.svc} link copied');
  }

  // ── Boarding-alert + save toggles (with toast/snackbar feedback) ───────
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

  void _toggleServiceSaved() {
    final m = AppModel.shared;
    final savedHere = m.isFavService(no: widget.svc, stop: widget.stopCode);
    final savedAnywhere = m.isFavService(no: widget.svc, stop: null);
    if (savedHere || savedAnywhere) {
      if (savedHere) m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      if (savedAnywhere) m.toggleFavService(no: widget.svc, stop: null);
      _showToast(
        Icons.directions_bus_outlined,
        'Bus ${widget.svc} removed from saved',
      );
    } else {
      m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      _showToast(
        Icons.directions_bus_rounded,
        'Bus ${widget.svc} saved — find it under Saved',
      );
    }
  }

  // ── Toast ─────────────────────────────────────────────────────────────
  void _showToast(IconData icon, String text) {
    setState(() => _toast = (icon: icon, text: text));
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Widget _buildToast(BuildContext context, LyneTheme t) {
    final toast = _toast!;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.isDark ? 0.34 : 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(toast.icon, size: 16, color: t.soon),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    toast.text,
                    style: t.sans(13, weight: FontWeight.w500, color: t.fg),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 2. Title block ────────────────────────────────────────────────────
  Widget _buildTitleBlock(BuildContext context, LyneTheme t, Service? live) {
    final feed = Freshness.from(DataStore.shared.lastRefresh(widget.stopCode));
    final conf = live != null
        ? ArrivalConfidence.of(monitored: live.monitored, feed: feed)
        : ArrivalConfidence.none;
    final isLive = conf != ArrivalConfidence.none;
    final dest = live?.dest ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bus ${widget.svc}',
          style: t.sans(28, weight: FontWeight.w700, color: t.fg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                dest.isEmpty ? 'Loading route…' : 'Towards $dest',
                style: t.sans(15, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLive) ...[
              const SizedBox(width: 8),
              Semantics(
                label: 'Live tracking',
                excludeSemantics: true,
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
                          .copyWith(letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── 3. Hero — ETA · stops-away · crowd · deck · next two ───────────────
  Widget _buildHeroCard(LyneTheme t) {
    final s = _liveService();
    final now = DateTime.now();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroEtaRow(t, s, now),
                    const SizedBox(height: 2),
                    Text(
                      _approachContext(s),
                      style: t.sans(13, color: t.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (s != null) ...[
                const SizedBox(width: 12),
                // Compact word (Seats/Standing/Limited) — matches iOS
                // WSTrackBusView's live-card crowd word (`Load.wsWord`)
                // rather than the fuller "Seats available" phrasing used
                // elsewhere in the app.
                CrowdMeter(load: s.load, compact: true),
              ],
            ],
          ),
          if (s != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: t.line),
            const SizedBox(height: 12),
            _heroFooter(t, s, now),
          ],
        ],
      ),
    );
  }

  Widget _heroEtaRow(LyneTheme t, Service? s, DateTime now) {
    if (s == null) {
      // No live bus yet — an honest dash, not a decorated headline; the
      // caption below ("Waiting for the next N") carries the message (iOS
      // WSTrackBusView parity: the liveCard's ETA slot is a bare "—").
      return Text(
        '—',
        style: t.mono(34, weight: FontWeight.w700, color: t.faint),
      );
    }
    final eta = fmtEta(_liveEtaSec(s, now));
    if (eta.big == 'Arr') {
      return Text(
        'Arriving',
        style: t.sans(30, weight: FontWeight.w700, color: t.soon),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eta.big,
          style: t.mono(40, weight: FontWeight.w700, color: t.fg),
        ),
        const SizedBox(width: 5),
        Text(
          eta.small,
          style: t.sans(16, weight: FontWeight.w600, color: t.dim),
        ),
      ],
    );
  }

  Widget _heroFooter(LyneTheme t, Service s, DateTime now) {
    final next = _nextTwoText(s, now);
    return Row(
      children: [
        Icon(Icons.directions_bus_rounded, size: 13, color: t.dim),
        const SizedBox(width: 6),
        Text(
          s.deck.word,
          style: t.mono(11, weight: FontWeight.w500, color: t.dim),
        ),
        if (s.wab) ...[
          const SizedBox(width: 6),
          Icon(Icons.accessible_rounded, size: 13, color: t.dim),
        ],
        const Spacer(),
        if (next.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Then ',
                style: t.sans(11, weight: FontWeight.w600, color: t.faint),
              ),
              Text(
                next,
                style: t.mono(12, weight: FontWeight.w600, color: t.dim),
              ),
            ],
          ),
      ],
    );
  }

  String _nextTwoText(Service s, DateTime now) {
    String? mins(DateTime? d) {
      if (d == null) return null;
      final e = fmtEta(d.difference(now).inSeconds.clamp(0, 1 << 30));
      return e.big == 'Arr' ? 'now' : e.big;
    }

    final parts = [
      mins(s.followingDate),
      mins(s.thirdDate),
    ].whereType<String>().toList();
    if (parts.isEmpty) return '';
    return '${parts.join(" · ")} min';
  }

  /// Formats [s.arrivalDate] as a display clock (e.g. "7:39 PM" / "19:39"),
  /// honouring the app-wide 24h preference via [fmtClock]. Returns null when
  /// the arrival date is absent or the bus is fewer than 30 seconds out
  /// (mirrors iOS arrivalClock nil rule).
  String? _arrivalClock(Service s) {
    final d = s.arrivalDate;
    if (d == null) return null;
    if (d.difference(DateTime.now()).inSeconds < 30) return null;
    final hhmm =
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    return fmtClock(hhmm, use24h: AppModel.shared.use24h);
  }

  String _approachContext(Service? s) {
    if (s == null) return 'Waiting for the next ${widget.svc}';
    final n = _stopsRemaining();
    final stopsPart = n != null
        ? (n == 0 ? 'At your stop now' : '$n stop${n == 1 ? '' : 's'} away')
        : 'On the way to your stop';
    final clock = _arrivalClock(s);
    if (clock != null) return 'Arrives $clock · $stopsPart';
    return stopsPart;
  }

  // ── 4. Route — full-route timeline (no map on Android; this timeline IS
  //    the route-progress affordance). Always inline, matching iOS
  //    WSTrackBusView's single-scroll structure — no "tap to see the full
  //    route" modal step. ───────────────────────────────────────────────
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
          if (dirs > 1) ...[
            const SizedBox(height: 10),
            _routeDirectionToggle(t),
          ],
          const SizedBox(height: 12),
          RouteTimeline(
            svc: widget.svc,
            stops: _timelineStops(),
            alightId: null,
            onAlight: (_) {},
            selectable: false,
            embedded: true,
            // Every stop row opens that stop's own arrivals (iOS
            // RouteTimeline parity: any row, not just the upcoming ones).
            onOpenStop: _openStop,
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line, width: 1),
      ),
      child: body,
    );
  }

  /// "ROUTE ───── N stops" — mirrors iOS's WSSectionHeader recipe (uppercase
  /// heavy label · hairline rule · mono meta) inside Android's own card
  /// chrome.
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
    return Column(
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
    );
  }

  /// Shown when the fetch resolves with no route for this service.
  Widget _routeUnavailableState(LyneTheme t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route_rounded, size: 30, color: t.faint),
        const SizedBox(height: 10),
        Text('Route unavailable', style: t.sans(14, color: t.dim)),
      ],
    );
  }

  /// Opens another stop's own arrivals from a tapped route-timeline row (iOS
  /// RouteTimeline parity: every non-"your stop" row pushes that stop).
  /// `onOpenBus` re-enters this same screen for whichever bus the user picks
  /// there, mirroring the self-referential push SoftStopScreen already does
  /// for its own "nearby station's bus stop" rows.
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
              _truncate('To ${sr.directions[i].destinationName}', 22),
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

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  // ── 5. CTA — the single primary action, pinned above the ad banner (iOS
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
