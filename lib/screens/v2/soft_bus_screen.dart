// SoftBusScreen — Leyne bus tracking (Material 3 Android).
//
// No-scroll glanceable dashboard (Android variant of iOS SoftBusView 2.5.0).
// Android intentionally has NO map — see memory "android-no-map": the map is
// iOS-only (native MapKit); Android shows the route, not a map. Layout:
//   1. Top bar — back · bell (boarding alert) · save · ⋯ (manage alerts/share)
//   2. Title   — "Bus {svc}" + "Towards {dest}" + LIVE
//   3. Hero    — ETA + stops-away + crowd meter, then deck/wheelchair + next two
//   4. Live    — compact route strip (origin→bus→your stop→terminus) filling the
//                screen; tap to open the full-route card.
//   5. Footer  — first / last bus today
//
// "Stops away" / the strip's bus position come from the estimated bus index
// (live GPS snapped to the nearest route stop, else an ETA estimate) — no map
// rendering, so no flutter_map / tiles.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/alert_timing.dart';
import '../../data/bus_progress.dart';
import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';
import '../../theme.dart';
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
  int _dirIndex = 0;

  // Periodic ticker (1.5 s) — keeps this stop's arrivals fresh while the view
  // is open (the global app tick only refreshes pinned / open-card stops).
  Timer? _ticker;

  // ── Transient confirmation toast ─────────────────────────────────────
  // Says what a tapped top-bar button just did, then clears itself.
  ({IconData icon, String text})? _toast;
  Timer? _toastTimer;

  // ── Lifecycle ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.ensureArrivals(widget.stopCode);
      _loadRoute();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      // Self-throttled to the 25 s freshness window; refreshes the ETA + the
      // strip's "stops away" via the DataStore listener.
      DataStore.shared.ensureArrivals(widget.stopCode);
    });
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
              selection: widget.tabSelection!, onSelect: widget.onTab!)
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                      child: _buildTitleBlock(context, t, _liveService()),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildHeroCard(t),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildLiveModule(t),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _buildFirstLastFooter(t),
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

  // ── 1. Top bar ────────────────────────────────────────────────────────
  Widget _buildTopBar(LyneTheme t) {
    final boardingOn = _boardingAlertOn;
    final saved =
        AppModel.shared.isFavService(no: widget.svc, stop: widget.stopCode) ||
            AppModel.shared.isFavService(no: widget.svc, stop: null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _CircleButton(
            onTap: widget.onBack,
            semanticsLabel: 'Back',
            child: Icon(Icons.arrow_back, size: 20, color: t.fg),
          ),
          const Spacer(),
          _CircleButton(
            onTap: _toggleBoardingAlert,
            semanticsLabel: boardingOn
                ? 'Boarding alert on for bus ${widget.svc}. Tap to cancel.'
                : 'Notify me before bus ${widget.svc} reaches this stop',
            child: Icon(
              boardingOn
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
              color: boardingOn ? t.soon : t.fg,
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            onTap: _toggleServiceSaved,
            semanticsLabel: saved
                ? 'Bus ${widget.svc} saved. Tap to remove.'
                : 'Save bus ${widget.svc}',
            child: Icon(
              saved
                  ? Icons.directions_bus_rounded
                  : Icons.directions_bus_outlined,
              size: 20,
              color: saved ? t.soon : t.fg,
            ),
          ),
          const SizedBox(width: 8),
          _buildOverflow(t),
        ],
      ),
    );
  }

  /// "⋯" overflow — manage alerts + share. A single bordered circle (no outer
  /// surface ring, no shadow) so it matches the other top-bar buttons.
  Widget _buildOverflow(LyneTheme t) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: PopupMenuButton<String>(
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
                  Text('Share bus ${widget.svc}',
                      style: t.sans(14, color: t.fg)),
                ],
              ),
            ),
          ],
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(color: t.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.more_horiz, size: 20, color: t.fg),
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

  // ── Boarding-alert + save toggles (with toast feedback) ───────────────
  bool get _boardingAlertOn =>
      AppModel.shared.alertFor(
        kind: AlertKind.arrival,
        busNo: widget.svc,
        stopCode: widget.stopCode,
      ) !=
      null;

  Future<void> _toggleBoardingAlert() async {
    final m = AppModel.shared;
    final existing = m.alertFor(
      kind: AlertKind.arrival,
      busNo: widget.svc,
      stopCode: widget.stopCode,
    );
    if (existing != null) {
      await m.removeAlert(existing.id);
      if (m.isOngoingActive(busNo: widget.svc, stopCode: widget.stopCode)) {
        await m.toggleOngoing(
          busNo: widget.svc,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
        );
      }
      _showToast(Icons.notifications_off_rounded,
          'Boarding alert off for Bus ${widget.svc}');
    } else {
      final live = _liveService();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: widget.svc,
        stopCode: widget.stopCode,
        stopName: DataStore.shared.stopName(widget.stopCode),
        dest: live?.dest ?? '',
        boardStopCode: widget.stopCode,
        leadMinutes: AlertTiming.defaultLead(AlertKind.arrival),
      ));
      if (live != null &&
          m.notificationsEnabled &&
          !m.isOngoingActive(busNo: widget.svc, stopCode: widget.stopCode)) {
        await m.toggleOngoing(
          busNo: widget.svc,
          stopCode: widget.stopCode,
          stopName: DataStore.shared.stopName(widget.stopCode),
        );
      }
      _showToast(Icons.notifications_active_rounded,
          "Boarding alert on — we'll buzz you before Bus ${widget.svc} arrives");
    }
  }

  void _toggleServiceSaved() {
    final m = AppModel.shared;
    final savedHere = m.isFavService(no: widget.svc, stop: widget.stopCode);
    final savedAnywhere = m.isFavService(no: widget.svc, stop: null);
    if (savedHere || savedAnywhere) {
      if (savedHere) m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      if (savedAnywhere) m.toggleFavService(no: widget.svc, stop: null);
      _showToast(Icons.directions_bus_outlined,
          'Bus ${widget.svc} removed from saved');
    } else {
      m.toggleFavService(no: widget.svc, stop: widget.stopCode);
      _showToast(Icons.directions_bus_rounded,
          'Bus ${widget.svc} saved — find it under Saved');
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
                          color: t.soon, shape: BoxShape.circle),
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
                      _approachContext(s != null),
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
      return Text('No live arrival',
          style: t.sans(20, weight: FontWeight.w700, color: t.dim));
    }
    final eta = fmtEta(_liveEtaSec(s, now));
    if (eta.big == 'Arr') {
      return Text('Arriving',
          style: t.sans(30, weight: FontWeight.w700, color: t.soon));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(eta.big, style: t.mono(40, weight: FontWeight.w700, color: t.fg)),
        const SizedBox(width: 5),
        Text(eta.small,
            style: t.sans(16, weight: FontWeight.w600, color: t.dim)),
      ],
    );
  }

  Widget _heroFooter(LyneTheme t, Service s, DateTime now) {
    final next = _nextTwoText(s, now);
    return Row(
      children: [
        Icon(Icons.directions_bus_rounded, size: 13, color: t.dim),
        const SizedBox(width: 6),
        Text(s.deck.word,
            style: t.mono(11, weight: FontWeight.w500, color: t.dim)),
        if (s.wab) ...[
          const SizedBox(width: 6),
          Icon(Icons.accessible_rounded, size: 13, color: t.dim),
        ],
        const Spacer(),
        if (next.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Then ',
                  style: t.sans(11, weight: FontWeight.w600, color: t.faint)),
              Text(next,
                  style: t.mono(12, weight: FontWeight.w600, color: t.dim)),
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

    final parts =
        [mins(s.followingDate), mins(s.thirdDate)].whereType<String>().toList();
    if (parts.isEmpty) return '';
    return '${parts.join(" · ")} min';
  }

  String _approachContext(bool hasService) {
    if (!hasService) return 'Waiting for the next ${widget.svc}';
    final n = _stopsRemaining();
    if (n != null) {
      return n == 0 ? 'At your stop now' : '$n stop${n == 1 ? '' : 's'} away';
    }
    return 'On the way to your stop';
  }

  // ── 4. Live module — the route strip (no map on Android) ───────────────
  Widget _buildLiveModule(LyneTheme t) {
    final dir = _currentDir;
    final hasStrip =
        dir != null && dir.stops.isNotEmpty && _estimatedBusIndex() != null;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openRouteCard,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.line, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: hasStrip
                        ? SizedBox(width: 264, child: _liveRouteStrip(dir))
                        : _routePlaceholder(t),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'VIEW FULL ROUTE',
                    style: t
                        .mono(9, weight: FontWeight.w600, color: t.faint)
                        .copyWith(letterSpacing: 0.8),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_up_rounded,
                      size: 13, color: t.faint),
                ],
              ),
            ],
          ),
        ),
      ),
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

  // ── Compact route strip ───────────────────────────────────────────────
  List<_StripNode> _stripNodes(RouteDirection dir) {
    final stops = dir.stops;
    final busIdx0 = _estimatedBusIndex();
    if (stops.isEmpty || busIdx0 == null) return const [];
    final youIdx = dir.youIndex.clamp(0, stops.length - 1);
    final busIdx = busIdx0.clamp(0, youIdx);
    final n = (youIdx - busIdx).clamp(0, stops.length);

    final nodes = <_StripNode>[];
    if (busIdx > 0) {
      nodes.add(_StripNode(_StripKind.origin, stops.first.name, null));
    }
    final busSub = n == 0 ? 'At your stop' : '$n stop${n == 1 ? '' : 's'} away';
    nodes.add(_StripNode(_StripKind.bus, 'Bus ${widget.svc}', busSub));
    nodes.add(_StripNode(_StripKind.you, 'Your stop',
        DataStore.shared.stopName(widget.stopCode)));
    if (youIdx < stops.length - 1) {
      nodes.add(_StripNode(_StripKind.dest, stops.last.name, null));
    }
    return nodes;
  }

  Widget _liveRouteStrip(RouteDirection dir) {
    final nodes = _stripNodes(dir);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++) _stripRow(nodes, i),
      ],
    );
  }

  Widget _stripRow(List<_StripNode> nodes, int i) {
    final t = context.t;
    final node = nodes[i];
    final isLast = i == nodes.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: isLast ? 24 : 42,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              if (!isLast)
                Positioned(
                  top: 12,
                  child: SizedBox(
                    width: 3,
                    height: 42,
                    child: _stripConnector(node.kind),
                  ),
                ),
              _stripDot(node.kind),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: (node.kind == _StripKind.bus || node.kind == _StripKind.you)
                  ? 0
                  : 3,
            ),
            child: _stripLabel(node, t),
          ),
        ),
      ],
    );
  }

  Widget _stripConnector(_StripKind afterKind) {
    final t = context.t;
    if (afterKind == _StripKind.bus) {
      return Center(child: Container(width: 2.5, color: t.soon));
    }
    return CustomPaint(
      painter: _DashedVLinePainter(color: t.faint, strokeWidth: 1.5),
    );
  }

  Widget _stripDot(_StripKind kind) {
    final t = context.t;
    Widget inner;
    switch (kind) {
      case _StripKind.origin:
        inner = Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.faint, width: 1.5),
          ),
        );
      case _StripKind.bus:
        inner = Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.soon,
            shape: BoxShape.circle,
            border: Border.all(color: t.surface, width: 2),
          ),
          child: Icon(Icons.directions_bus_rounded,
              size: 10, color: t.contrastFg),
        );
      case _StripKind.you:
        inner = Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.soon, width: 3),
          ),
        );
      case _StripKind.dest:
        inner = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: t.dim, shape: BoxShape.circle),
        );
    }
    return SizedBox(width: 24, height: 24, child: Center(child: inner));
  }

  Widget _stripLabel(_StripNode node, LyneTheme t) {
    switch (node.kind) {
      case _StripKind.origin:
      case _StripKind.dest:
        return Text(
          node.title,
          style: t.mono(11, color: t.faint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case _StripKind.bus:
      case _StripKind.you:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              node.title,
              style: t.sans(14, weight: FontWeight.w600, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (node.sub != null)
              Text(
                node.sub!,
                style: t.sans(12,
                    color: node.kind == _StripKind.bus ? t.soon : t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );
    }
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bus ${widget.svc}',
                              style: t.sans(22,
                                  weight: FontWeight.w700, color: t.fg)),
                          if (dest.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text('Towards $dest',
                                style: t.sans(14, color: t.dim)),
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
      LyneTheme t, void Function(void Function()) setSheet) {
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

// ─── Route strip model ────────────────────────────────────────────────────────
enum _StripKind { origin, bus, you, dest }

class _StripNode {
  const _StripNode(this.kind, this.title, this.sub);
  final _StripKind kind;
  final String title;
  final String? sub;
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

// ─── Dashed vertical rail (route strip) ───────────────────────────────────────
/// Paints a vertical dashed line — the inactive rail in the compact route strip.
class _DashedVLinePainter extends CustomPainter {
  _DashedVLinePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    final path = ui.Path()
      ..moveTo(x, 0)
      ..lineTo(x, size.height);
    _drawDashedPath(canvas, path, paint, dash: 2, gap: 4);
  }

  @override
  bool shouldRepaint(_DashedVLinePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

void _drawDashedPath(
  Canvas canvas,
  ui.Path source,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = (distance + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }
}
