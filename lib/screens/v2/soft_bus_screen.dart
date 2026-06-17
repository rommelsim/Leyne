// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// No-scroll glanceable dashboard (Android variant of iOS SoftBusView 2.5.0).
// Android intentionally has NO map — see memory "android-no-map": the map is
// iOS-only (native MapKit); Android shows the route, not a map. Layout:
//   1. Top bar — back · bell (boarding alert) · save · ⋯ (manage alerts/share)
//   2. Title   — "Bus {svc}" + "Towards {dest}" + LIVE
//   3. Hero    — ETA + stops-away + crowd meter, then deck/wheelchair + next two
//   4. Live    — compact vertical mini-timeline (origin → bus → upcoming stops
//                → your stop → terminus) inside the card. Connector line is
//                t.soon up to the bus, t.line after. Tap to open the full-
//                route card (RouteTimeline sheet).
//   5. Footer  — first / last bus today
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

  /// When provided, the tab bar (with its ad banner) stays visible on this
  /// pushed detail page. [tabSelection] is the tab it was opened from. Null for
  /// deep-link contexts.
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftBusScreen> createState() => _SoftBusScreenState();
}

class _SoftBusScreenState extends State<SoftBusScreen> {
  // ── Route data ──────────────────────────────────────────────────────
  RouteInfo? _route;
  ServiceRoute? _serviceRoute;
  // False until the (deferred) route fetch resolves — drives the live module's
  // loading state so we never show the "see the full route" hint over a blank
  // route, or open an empty route sheet, before the data lands.
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
    super.dispose();
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
    return seg.map((stop) {
      final idx = r.stops.indexWhere((s) => s.code == stop.code);
      final state = BusProgress.stopState(
        idx: idx,
        busIndex: busSeq,
        youIndex: youSeq,
        canMarkBoard: canMarkBoard,
      );
      return SoftRouteStop(id: stop.code, name: stop.name, state: state);
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
      bottomNavigationBar: (widget.onTab != null && widget.tabSelection != null)
          ? SoftBottomBar(
              selection: widget.tabSelection!,
              onSelect: widget.onTab!,
            )
          : null,
      // OUTER listener: DataStore only — rebuilds only when arrivals data
      // changes from a network fetch. The heavy route-progress/timeline
      // subtree lives here and is therefore NOT rebuilt every second.
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
                    // Fill-or-scroll: content hugs its natural height and the
                    // first/last footer pins to the bottom when there's room;
                    // when the mini-timeline is taller than the viewport the
                    // whole area scrolls instead of overflowing.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (ctx, c) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: c.maxHeight),
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
                                  // First/last bus rides directly under the
                                  // title — "have I missed the last bus?" at a
                                  // glance, matching iOS SoftBusView.
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      0,
                                    ),
                                    child: _buildFirstLastFooter(t),
                                  ),
                                  const SizedBox(height: 14),
                                  // Labeled action row (Track arrival · Save
                                  // service · More) — mirrors iOS SoftBusView.
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: ListenableBuilder(
                                      listenable: AppModel.shared,
                                      builder: (context, _) =>
                                          _buildActionButtons(t),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // INNER listener: AppModel only — rebuilds
                                  // every second so the ETA countdown ticks.
                                  // Only _buildHeroCard (which reads
                                  // DateTime.now()) is inside it; everything
                                  // else stays in the outer DataStore scope.
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
                                    child: _buildLiveModule(t),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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

  // ── 1. Top bar — back only (the toggles live in the labeled action row
  //    below the title, matching iOS SoftBusView). ─────────────────────────
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
        ],
      ),
    );
  }

  // ── Action row — three labeled buttons (Track arrival · Save service ·
  //    More), mirroring iOS. Self-describing labels + larger tap targets
  //    replace the old cryptic icon-only top-bar toggles. ──────────────────
  Widget _buildActionButtons(LyneTheme t) {
    final boardingOn = _boardingAlertOn;
    final saved =
        AppModel.shared.isFavService(no: widget.svc, stop: widget.stopCode) ||
        AppModel.shared.isFavService(no: widget.svc, stop: null);
    return Row(
      children: [
        Expanded(
          child: _actionPill(
            t,
            icon: boardingOn
                ? Icons.notifications_active_rounded
                : Icons.notifications_outlined,
            label: 'Track arrival',
            active: boardingOn,
            onTap: _toggleBoardingAlert,
            semantics: boardingOn
                ? 'Arrival tracking on for bus ${widget.svc}. Tap to cancel.'
                : 'Track arrival of bus ${widget.svc}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionPill(
            t,
            icon: saved ? Icons.star_rounded : Icons.star_outline_rounded,
            label: 'Save service',
            active: saved,
            onTap: _toggleServiceSaved,
            semantics: saved
                ? 'Bus ${widget.svc} saved. Tap to remove.'
                : 'Save bus ${widget.svc}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _moreActionPill(t)),
      ],
    );
  }

  /// A single labeled action pill (icon + label) used in the action row.
  Widget _actionPill(
    LyneTheme t, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    required String semantics,
  }) {
    final fg = active ? t.soon : t.fg;
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? t.soon : t.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.sans(13, weight: FontWeight.w600, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The "More" action pill — manage alerts + share, via a popup menu.
  Widget _moreActionPill(LyneTheme t) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      padding: EdgeInsets.zero,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      onSelected: (v) {
        if (v == 'manage') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ManageAlertsScreen()),
          );
        } else if (v == 'share') {
          _shareBus();
        }
      },
      itemBuilder: (_) => [
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
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line, width: 1),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz, size: 18, color: t.fg),
            const SizedBox(width: 6),
            Text(
              'More',
              style: t.sans(13, weight: FontWeight.w600, color: t.fg),
            ),
          ],
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

  // ── Boarding-alert + save toggles (with toast feedback) ───────────────
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
    // Show a faint "~" whisper when we have a service but the position /
    // arrival isn't a fresh live fix — mirrors iOS SoftBusView.showWhisper:
    //   confidence != .none && (confidence != .live)
    // Android has no `plot.tier` concept so the condition simplifies to
    // "any confidence that isn't fully live".
    final showWhisper =
        conf != ArrivalConfidence.none && conf != ArrivalConfidence.live;
    final dest = live?.dest ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Bus ${widget.svc}',
              style: t.sans(28, weight: FontWeight.w700, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showWhisper) ...[
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0.7,
                  child: Text('~', style: t.mono(14, color: t.faint)),
                ),
              ),
            ],
          ],
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
                CrowdMeter(load: s.load),
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
      return Text(
        'No live arrival',
        style: t.sans(20, weight: FontWeight.w700, color: t.dim),
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

  // ── 4. Live module — compact vertical mini-timeline (no map on Android) ─
  Widget _buildLiveModule(LyneTheme t) {
    final dir = _currentDir;
    final remaining = _stopsRemaining();

    // Resolve timeline content only when live bus position is available.
    final resolvedDir =
        (dir != null && _estimatedBusIndex() != null && dir.stops.isNotEmpty)
        ? dir
        : null;
    final upcoming = resolvedDir != null
        ? _upcomingStops(resolvedDir)
        : const <String>[];
    final between = resolvedDir != null ? _betweenCaption(resolvedDir) : null;

    // The route data is ready once _routeLoaded is true AND a route came back.
    final hasRoute = _routeLoaded && _serviceRoute != null;
    // Only let the user open the full-route sheet once there's actually a route
    // to show — otherwise the sheet opens empty while the fetch is in flight.
    final tappable = hasRoute;

    final Widget body;
    if (resolvedDir != null) {
      // Loaded + live bus position resolved → the rich mini-timeline.
      body = _buildMiniTimeline(t, resolvedDir, upcoming, between, remaining);
    } else if (!_routeLoaded) {
      // Still fetching the route — show a loading state, not the (misleading)
      // "see the full route" hint over a blank route.
      body = _routeLoadingState(t);
    } else if (hasRoute) {
      // Route is ready but we can't place the live bus yet — the static route
      // is still viewable, so keep the tappable placeholder.
      body = _routePlaceholder(t);
    } else {
      // Fetch finished but returned no route (unavailable for this service).
      body = _routeUnavailableState(t);
    }

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tappable ? _openRouteCard : null,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.line, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              body,
              // The "VIEW FULL ROUTE" affordance only makes sense once a route
              // is actually available to open.
              if (hasRoute) ...[
                const SizedBox(height: 10),
                _viewFullRouteHint(t),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shown while the route fetch is in flight — a spinner + label instead of
  /// the "see the full route" hint sitting over an empty route.
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

  // Maximum upcoming stops shown inline before collapsing to "+N more".
  static const int _maxInlineStops = 4;

  /// Compact vertical mini-timeline: origin → bus → [upcoming stops] →
  /// your stop → terminus, all inline in a single Column.
  Widget _buildMiniTimeline(
    LyneTheme t,
    RouteDirection dir,
    List<String> upcoming,
    String? between,
    int? remaining,
  ) {
    final stops = dir.stops;
    final busIdx0 = _estimatedBusIndex()!;
    final youIdx = dir.youIndex.clamp(0, stops.length - 1);
    final busIdx = busIdx0.clamp(0, youIdx);

    final showOrigin = busIdx > 0;
    final showDest = youIdx < stops.length - 1;

    // Bus subtitle: prefer "between A–B" when available, else "now here".
    final busSub = between != null
        ? between.replaceFirst('Between ', '').replaceFirst(' and ', ' – ')
        : 'now here';

    // Upcoming stops: cap at _maxInlineStops, show overflow as "+N more".
    final shownUpcoming = upcoming.take(_maxInlineStops).toList();
    final extraUpcoming = upcoming.length - shownUpcoming.length;

    // Remaining label for your-stop node.
    final youSub = remaining == null
        ? null
        : remaining == 0
        ? 'Arriving'
        : '$remaining stop${remaining == 1 ? '' : 's'} away';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Origin ──────────────────────────────────────────────────────
        if (showOrigin) ...[
          _timelineRow(
            t,
            dot: _dotOrigin(t),
            lineAbove: false,
            lineBelow: true,
            lineAboveColor: t.soon,
            lineBelowColor: t.soon,
            child: Text(
              stops.first.name,
              style: t.sans(12, color: t.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],

        // ── Bus node ─────────────────────────────────────────────────────
        _timelineRow(
          t,
          dot: _dotBus(t),
          lineAbove: showOrigin,
          lineBelow: true,
          lineAboveColor: t.soon,
          lineBelowColor: t.line,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bus ${widget.svc}',
                style: t.sans(13, weight: FontWeight.w600, color: t.soon),
              ),
              Text(busSub, style: t.sans(11, color: t.dim)),
            ],
          ),
        ),

        // ── Upcoming stops (inline) ───────────────────────────────────────
        for (final s in shownUpcoming)
          _timelineRow(
            t,
            dot: _dotIntermediate(t),
            lineAbove: true,
            lineBelow: true,
            lineAboveColor: t.line,
            lineBelowColor: t.line,
            child: Text(
              s,
              style: t.sans(12, color: t.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // "+N more stops" overflow row
        if (extraUpcoming > 0)
          _timelineRow(
            t,
            dot: _dotIntermediate(t),
            lineAbove: true,
            lineBelow: true,
            lineAboveColor: t.line,
            lineBelowColor: t.line,
            child: Text(
              '+$extraUpcoming more stop${extraUpcoming == 1 ? '' : 's'}',
              style: t.sans(12, color: t.faint),
            ),
          ),

        // ── Your stop ────────────────────────────────────────────────────
        _timelineRow(
          t,
          dot: _dotYou(t),
          lineAbove: true,
          lineBelow: showDest,
          lineAboveColor: t.line,
          lineBelowColor: t.line,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your stop',
                style: t.sans(13, weight: FontWeight.w600, color: t.fg),
              ),
              if (youSub != null)
                Text(youSub, style: t.sans(11, color: t.soon)),
            ],
          ),
        ),

        // ── Terminus ─────────────────────────────────────────────────────
        if (showDest)
          _timelineRow(
            t,
            dot: _dotDest(t),
            lineAbove: true,
            lineBelow: false,
            lineAboveColor: t.line,
            lineBelowColor: t.line,
            child: Text(
              stops.last.name,
              style: t.sans(12, color: t.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// A single row in the vertical mini-timeline. The connector lines are drawn
  /// as thin containers that sit in the fixed-width dot column, above/below the
  /// dot itself, so they form a continuous vertical bar across nodes.
  Widget _timelineRow(
    LyneTheme t, {
    required Widget dot,
    required bool lineAbove,
    required bool lineBelow,
    required Color lineAboveColor,
    required Color lineBelowColor,
    required Widget child,
  }) {
    const dotColW = 32.0; // fixed width for the dot + connector column
    const connW = 2.0; // connector bar width
    const dotRowH = 28.0; // height of the dot zone
    const connSegH = 8.0; // connector segment above/below dot zone

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: dotColW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Connector above dot
                SizedBox(
                  height: connSegH,
                  child: Center(
                    child: Container(
                      width: connW,
                      color: lineAbove ? lineAboveColor : Colors.transparent,
                    ),
                  ),
                ),
                // Dot zone
                SizedBox(
                  height: dotRowH,
                  child: Center(child: dot),
                ),
                // Connector below dot
                SizedBox(
                  height: connSegH,
                  child: Center(
                    child: Container(
                      width: connW,
                      color: lineBelow ? lineBelowColor : Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  // ── Node dot builders ─────────────────────────────────────────────────

  /// Origin: filled `t.soon` circle with a check icon (bus has passed).
  Widget _dotOrigin(LyneTheme t) => Container(
    width: 16,
    height: 16,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
    child: Icon(Icons.check_rounded, size: 10, color: t.contrastFg),
  );

  /// Bus: filled `t.soon` circle with a halo ring and bus icon.
  Widget _dotBus(LyneTheme t) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: t.soon.withValues(alpha: 0.22),
          shape: BoxShape.circle,
        ),
      ),
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.soon,
          shape: BoxShape.circle,
          border: Border.all(color: t.surface, width: 2),
        ),
        child: Icon(
          Icons.directions_bus_rounded,
          size: 11,
          color: t.contrastFg,
        ),
      ),
    ],
  );

  /// Intermediate upcoming stop: small grey-filled dot.
  Widget _dotIntermediate(LyneTheme t) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: t.line, shape: BoxShape.circle),
  );

  /// Your stop: hollow ring with `t.soon` border.
  Widget _dotYou(LyneTheme t) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: t.surface,
      shape: BoxShape.circle,
      border: Border.all(color: t.soon, width: 3),
    ),
  );

  /// Terminus: small dim hollow ring.
  Widget _dotDest(LyneTheme t) => Container(
    width: 13,
    height: 13,
    decoration: BoxDecoration(
      color: t.surface,
      shape: BoxShape.circle,
      border: Border.all(color: t.dim, width: 1.5),
    ),
  );

  Widget _viewFullRouteHint(LyneTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'VIEW FULL ROUTE',
          style: t
              .mono(9, weight: FontWeight.w600, color: t.faint)
              .copyWith(letterSpacing: 0.8),
        ),
        const SizedBox(width: 3),
        Icon(Icons.keyboard_arrow_up_rounded, size: 13, color: t.faint),
      ],
    );
  }

  Widget _routePlaceholder(LyneTheme t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route_rounded, size: 30, color: t.faint),
        const SizedBox(height: 10),
        Text('See the full route', style: t.sans(14, color: t.dim)),
      ],
    );
  }

  // ── Data helpers (used by mini-timeline) ─────────────────────────────

  /// Stops the bus still passes before reaching yours (in order).
  List<String> _upcomingStops(RouteDirection dir) {
    final busIdx0 = _estimatedBusIndex();
    if (busIdx0 == null) return const [];
    final youIdx = dir.youIndex.clamp(0, dir.stops.length - 1);
    final busIdx = busIdx0.clamp(0, youIdx);
    final out = <String>[];
    for (var i = busIdx + 1; i < youIdx; i++) {
      out.add(dir.stops[i].name);
    }
    return out;
  }

  String? _betweenCaption(RouteDirection dir) {
    final busIdx0 = _estimatedBusIndex();
    if (busIdx0 == null || dir.stops.isEmpty) return null;
    final busIdx = busIdx0.clamp(0, dir.stops.length - 1);
    final nextIdx = (busIdx + 1).clamp(0, dir.stops.length - 1);
    if (nextIdx == busIdx) return null;
    return 'Between ${dir.stops[busIdx].name} and ${dir.stops[nextIdx].name}';
  }

  // ── Route card (bottom sheet — full route) ─────────────────────────────
  void _openRouteCard() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final t = ctx.t;
            final dest =
                _liveService()?.dest ?? _currentDir?.destinationName ?? '';
            final stops = _timelineStops();
            final dirs = _serviceRoute?.directions.length ?? 0;
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      // Pad the bottom by the system navigation-bar inset so the
                      // last route rows (esp. once "show all stops" is expanded)
                      // clear the OS nav bar instead of rendering under it. The
                      // sheet itself stays edge-to-edge (bg fills to the screen
                      // bottom); only the scrollable content is inset. `ctx`
                      // carries the device viewPadding inside the modal route.
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, 28 + MediaQuery.viewPaddingOf(ctx).bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bus ${widget.svc}',
                            style: t.sans(
                              22,
                              weight: FontWeight.w700,
                              color: t.fg,
                            ),
                          ),
                          if (dest.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Towards $dest',
                              style: t.sans(14, color: t.dim),
                            ),
                          ],
                          if (dirs > 1) ...[
                            const SizedBox(height: 14),
                            _routeCardDirectionToggle(t, setSheet),
                          ],
                          const SizedBox(height: 14),
                          RouteTimeline(
                            svc: widget.svc,
                            stops: stops,
                            alightId: null,
                            onAlight: (_) {},
                            selectable: false,
                            embedded: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _routeCardDirectionToggle(
    LyneTheme t,
    void Function(void Function()) setSheet,
  ) {
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
        setSheet(() {});
      },
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  // ── 5. First / last bus footer ─────────────────────────────────────────
  Widget _buildFirstLastFooter(LyneTheme t) {
    final tt = DataStore.shared.busTimings(
      serviceNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (tt == null) return const SizedBox.shrink();
    final use24 = AppModel.shared.use24h;
    final first = fmtClock(tt.first, use24h: use24);
    final last = fmtClock(tt.last, use24h: use24);
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: t.faint),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'First $first  ·  Last $last',
            style: t.sans(12, weight: FontWeight.w500, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
