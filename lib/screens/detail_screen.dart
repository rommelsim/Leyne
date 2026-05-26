// Detail — stop overview → drill into a service for a live map + journey
// timeline.
//
// Two modes:
//   • Stop overview: header + service list with per-bus track toggles for
//     adding/removing buses from the Home pinned card.
//   • Service drill-in: hero with capacity meter, split RouteMap (Apple iOS
//     / OSM Android), RouteProgress with tap-to-alight.
//
// Entered with `initialSelectedNo` to land directly in service drill-in
// (e.g. tapping a specific bus row on a Home card).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
import '../widgets/route_map.dart';
import '../widgets/route_progress.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.stopCode,
    this.initialSelectedNo,
  });

  final String stopCode;
  final String? initialSelectedNo;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  String? _selectedNo;
  RouteInfo? _routeInfo;
  bool _routeLoading = false;

  /// Picked alight stop for the currently selected service. Reads from
  /// `AppModel.activeAlight` (single ride at a time, persisted) and
  /// filters to this bus so the picker doesn't light up for a different
  /// DetailScreen.
  String? get _alightCode {
    final a = AppModel.shared.activeAlight;
    if (a == null || a.busNo != _selectedNo) return null;
    return a.stopCode;
  }

  /// Handles a tap on a stop in `RouteProgress`. If the user picked a
  /// stop, computes the predicted "2 stops before alight" fire time
  /// from RouteInfo (90 s × (stopsToAlight − 2), with `busIndex` →
  /// `youIndex` as the starting reference) and arms the alert via
  /// `AppModel.setActiveAlight`. Untap clears the ride.
  Future<void> _onAlightChanged(String? code) async {
    final busNo = _selectedNo;
    final route = _routeInfo;
    if (busNo == null || route == null) return;
    if (code == null) {
      await AppModel.shared.clearActiveAlight();
      if (mounted) setState(() {});
      return;
    }
    final alightIdx = route.stops.indexWhere((s) => s.code == code);
    if (alightIdx < 0) return;
    final stop = route.stops[alightIdx];
    final base = route.busIndex ?? route.youIndex;
    final stopsToAlight = (alightIdx - base).clamp(0, 1 << 30);
    final stopsToWait = (stopsToAlight - 2).clamp(0, 1 << 30);
    final fireAt = DateTime.now().add(Duration(seconds: stopsToWait * 90));
    await AppModel.shared.setActiveAlight(
      busNo: busNo, stopCode: code, stopName: stop.name, fireAt: fireAt);
    if (mounted) setState(() {});
  }

  // Drives the live auto-refresh — re-polls arrivals + bus position so the
  // screen stays current without the user pulling to refresh. LTA publishes
  // a new bus fix roughly every 20s; 15s polling keeps the marker close to
  // real time while staying well within DataMall rate limits.
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _selectedNo = widget.initialSelectedNo;
    DataStore.shared.ensureArrivals(widget.stopCode, force: true);
    // Warm the BusRoutes dataset so first/last bus timings can render even
    // before the user drills into a service's live map.
    DataStore.shared.ensureRoutes();
    if (_selectedNo != null) _loadRoute();
    _liveTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _refreshLive());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  bool get _enteredViaService => widget.initialSelectedNo != null;

  Service? _liveSelected(AppModel m) {
    final no = _selectedNo;
    if (no == null) return null;
    final svcs = m.liveServices(widget.stopCode);
    for (final s in svcs) {
      if (s.no == no) return s;
    }
    return null;
  }

  Future<void> _loadRoute() async {
    final no = _selectedNo;
    if (no == null) {
      if (mounted) setState(() => _routeInfo = null);
      return;
    }
    if (mounted) setState(() => _routeLoading = true);
    final info =
        await DataStore.shared.route(serviceNo: no, stopCode: widget.stopCode);
    final bus = await DataStore.shared
        .liveBus(serviceNo: no, stopCode: widget.stopCode);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _routeInfo = null;
        _routeLoading = false;
      });
      return;
    }
    int? busIdx;
    if (bus != null && info.stops.isNotEmpty) {
      double best = double.infinity;
      for (var i = 0; i < info.stops.length; i++) {
        final s = info.stops[i];
        final d = haversine(s.lat, s.lon, bus.lat, bus.lon);
        if (d < best) {
          best = d;
          busIdx = i;
        }
      }
    }
    setState(() {
      _routeInfo = RouteInfo(
        stops: info.stops,
        youIndex: info.youIndex,
        busIndex: busIdx,
        busCoord: bus,
      );
      _routeLoading = false;
    });
  }

  void _selectService(String no) {
    setState(() => _selectedNo = no);
    _loadRoute();
  }

  /// Silent live refresh — keeps arrivals fresh and nudges the bus marker to
  /// its latest GPS fix without flashing the map's loading state. Called by
  /// `_liveTimer`; the route stop-list itself is static, so only the bus
  /// position is re-fetched.
  Future<void> _refreshLive() async {
    // ensureArrivals self-throttles to LtaConfig.arrivalRefresh, so calling
    // it every tick just keeps arrivalDate fresh enough that the countdown
    // doesn't drift.
    DataStore.shared.ensureArrivals(widget.stopCode);
    final no = _selectedNo;
    if (no == null || _routeInfo == null) return;
    final bus = await DataStore.shared
        .liveBus(serviceNo: no, stopCode: widget.stopCode);
    if (!mounted) return;
    // Re-read after the await — the user may have switched services or
    // backed out to the stop overview while the fetch was in flight.
    final info = _routeInfo;
    if (info == null || _selectedNo != no) return;
    int? busIdx;
    if (bus != null && info.stops.isNotEmpty) {
      double best = double.infinity;
      for (var i = 0; i < info.stops.length; i++) {
        final s = info.stops[i];
        final d = haversine(s.lat, s.lon, bus.lat, bus.lon);
        if (d < best) {
          best = d;
          busIdx = i;
        }
      }
    }
    setState(() {
      _routeInfo = RouteInfo(
        stops: info.stops,
        youIndex: info.youIndex,
        busIndex: busIdx,
        busCoord: bus,
      );
    });
  }

  void _backOrPop() {
    if (_selectedNo != null && !_enteredViaService) {
      setState(() {
        _selectedNo = null;
        _routeInfo = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) {
            final m = AppModel.shared;
            final stopName = DataStore.shared.stopName(widget.stopCode);
            final selected = _liveSelected(m);
            final pinned = m.isPinned(widget.stopCode);
            final services = m.liveServices(widget.stopCode);
            return Column(
              children: [
                _topBar(t, m, pinned, selected),
                Expanded(
                  // No pull-to-refresh — the screen is live, auto-refreshing
                  // arrivals + bus position on `_liveTimer`.
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: [
                      if (selected == null)
                        ..._stopOverview(t, m, stopName, services)
                      else
                        ..._serviceDetail(t, m, stopName, selected),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── Top bar ───────────────────────────────────────────────────────

  Widget _topBar(LyneTheme t, AppModel m, bool pinned, Service? selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _backOrPop,
            icon: const Icon(Icons.chevron_left),
            color: t.fg,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          if (selected != null) Pill('LIVE', color: t.accent),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => m.togglePin(widget.stopCode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: pinned
                    ? t.accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                border: Border.all(
                  color: pinned ? t.accent.withValues(alpha: 0.4) : t.line,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pinned ? Icons.bookmark : Icons.bookmark_outline,
                    size: 13,
                    color: pinned ? t.accent : t.fg,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pinned ? 'Pinned stop' : 'Pin stop',
                    style: t.sans(12, weight: FontWeight.w500,
                        color: pinned ? t.accent : t.fg),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mode A: Stop overview ─────────────────────────────────────────

  List<Widget> _stopOverview(
      LyneTheme t, AppModel m, String stopName, List<Service> services) {
    final freshness = _freshnessText();
    return [
      _stopHeading(t, m, stopName),
      if (freshness != null) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                width: 5, height: 5,
                decoration:
                    BoxDecoration(color: t.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(freshness,
                  style: t.mono(10, color: t.faint)
                      .copyWith(letterSpacing: 0.4)),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      if (services.isEmpty)
        _arrivalsPlaceholder(t, DataStore.shared.arrivals[widget.stopCode])
      else
        _servicesCard(t, m, services),
      const SizedBox(height: 14),
      Text(
        'Tap a bus to drill in. Use the checkmark to add or remove it from Home.',
        style: t.mono(11, color: t.faint).copyWith(letterSpacing: 0.4),
      ),
    ];
  }

  Widget _stopHeading(LyneTheme t, AppModel m, String stopName) {
    final pin = m.pinForCode(widget.stopCode);
    final label =
        pin?.nickname.isNotEmpty == true ? pin!.nickname : stopName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: t.accent.withValues(alpha: 0.3)),
                ),
                child: Text(label,
                    style: t.sans(11, weight: FontWeight.w600, color: t.accent)),
              ),
              const SizedBox(width: 8),
              Text('STOP ${widget.stopCode}',
                  style: t.mono(10, weight: FontWeight.w600, color: t.dim)
                      .copyWith(letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(stopName,
              style: t.sans(24, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.3)),
        ],
      ),
    );
  }

  Widget _servicesCard(LyneTheme t, AppModel m, List<Service> services) {
    final allNos = services.map((s) => s.no).toList();
    final tracked = allNos
        .where((no) => m.isTracked(code: widget.stopCode, busNo: no))
        .length;
    final allOn = m.allTracked(widget.stopCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              MicroLabel('Services at this stop'),
              const Spacer(),
              Text('tap a bus to drill in',
                  style: t.mono(10, color: t.faint)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
                onTap: () => m.setAllTracked(
                  code: widget.stopCode,
                  allNos: allNos,
                  tracked: !allOn,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Text(allOn ? 'Untrack all' : 'Track all',
                          style: t.sans(13,
                              weight: FontWeight.w600, color: t.accent)),
                      const Spacer(),
                      Text('$tracked/${allNos.length}',
                          style: t.mono(11, color: t.dim)),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < services.length; i++) ...[
                Divider(height: 1, color: t.line),
                _serviceTapRow(t, m, services[i], allNos),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _serviceTapRow(
      LyneTheme t, AppModel m, Service s, List<String> allNos) {
    final tracked = m.isTracked(code: widget.stopCode, busNo: s.no);
    final arriving = s.etaSec <= 60;
    final etaMin = (s.etaSec / 60).floor();
    final estimate = !s.monitored;
    final etaPrefix = estimate && etaMin > 0 ? '~' : '';
    final big = etaMin <= 0 ? 'Arr' : '$etaPrefix$etaMin';
    final unit = etaMin <= 0 ? 'now' : 'min';
    final etaColor = arriving ? t.accent : t.fg;
    final loadColor = switch (s.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };

    return InkWell(
      onTap: () => _selectService(s.no),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color: arriving
            ? t.accent.withValues(alpha: 0.05)
            : Colors.transparent,
        child: Opacity(
          opacity: tracked ? 1 : 0.55,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  tracked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: tracked ? t.accent : t.faint,
                  size: 22,
                ),
                onPressed: () => m.toggleTracked(
                  code: widget.stopCode,
                  busNo: s.no,
                  allNos: allNos,
                ),
              ),
              const SizedBox(width: 2),
              BusChip(no: s.no, size: ChipSize.sm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.dest,
                        style: t.sans(14, weight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                              color: loadColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(s.load.label.toLowerCase(),
                            style: t.mono(10, color: t.dim)),
                        if (s.wab) ...[
                          const SizedBox(width: 8),
                          Text('WAB',
                              style: t.mono(10, color: t.dim)
                                  .copyWith(letterSpacing: 0.4)),
                        ],
                        if (estimate) ...[
                          const SizedBox(width: 8),
                          Text('~ scheduled',
                              style: t.mono(10, color: t.warn)
                                  .copyWith(letterSpacing: 0.3)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(big,
                      style: t.mono(20, weight: FontWeight.w600, color: etaColor)),
                  const SizedBox(width: 3),
                  Text(unit, style: t.mono(11, color: t.dim)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrivalsPlaceholder(LyneTheme t, ArrivalState? state) {
    final kind = state?.kind;
    final msg = state?.errorMessage;
    Widget body;
    if (kind == ArrivalStateKind.loading || kind == null) {
      body = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: t.dim)),
          const SizedBox(width: 8),
          Text('Loading live arrivals…',
              style: t.sans(12, color: t.dim)),
        ],
      );
    } else if (kind == ArrivalStateKind.error) {
      body = Column(
        children: [
          Text('Couldn’t load arrivals',
              style: t.sans(13, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(msg ?? '', style: t.sans(11, color: t.dim)),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.contrastFg,
            ),
            onPressed: () =>
                DataStore.shared.ensureArrivals(widget.stopCode, force: true),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      body = Text('No buses running here right now',
          style: t.sans(13, color: t.dim));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: body),
    );
  }

  // ─── Mode B: Service drill-in ──────────────────────────────────────

  List<Widget> _serviceDetail(
      LyneTheme t, AppModel m, String stopName, Service s) {
    final hours = _operatingHoursCard(t, m, s);
    return [
      _serviceHeading(t, s, stopName),
      const SizedBox(height: 16),
      _heroCapacityCard(t, s),
      const SizedBox(height: 18),
      if (hours != null) ...[
        hours,
        const SizedBox(height: 18),
      ],
      // Apple Maps fits the design on iOS; the Android OpenStreetMap
      // fallback doesn't, so the live map is iOS-only.
      if (Platform.isIOS) ...[
        _sectionLabel(t, 'Live map',
            hint: _routeInfo?.busCoord == null ? 'bus gps unavailable' : null),
        RouteMap(route: _routeInfo, busNo: s.no, loading: _routeLoading),
        const SizedBox(height: 18),
      ],
      if (_routeInfo != null) ...[
        _sectionLabel(t, 'Journey',
            hint: _stopsAwayLabel(_routeInfo!)),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Walk to the BOARD HERE stop to catch this bus. '
            'Tap any stop ahead to mark where you’ll alight.',
            style: t.mono(11, color: t.faint)
                .copyWith(height: 1.5, letterSpacing: 0.3),
          ),
        ),
        RouteProgress(
          busNo: s.no,
          route: _routeInfo!,
          alightCode: _alightCode,
          onAlightChanged: _onAlightChanged,
        ),
        const SizedBox(height: 12),
        _onBusAlertCard(t, _routeInfo!, s),
      ] else if (_routeLoading) ...[
        _sectionLabel(t, 'Journey'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.dim)),
              const SizedBox(width: 8),
              Text('Loading route…',
                  style: t.sans(12, color: t.dim)),
            ],
          ),
        ),
      ],
    ];
  }

  String? _stopsAwayLabel(RouteInfo r) {
    final b = r.busIndex;
    if (b == null) return null;
    return '${(r.youIndex - b).abs()} STOPS AWAY';
  }

  /// "Buzz me 2 stops before X" card — mirrors the iOS native onBusAlertCard.
  /// Inactive state prompts the user to pick a stop in RouteProgress;
  /// active state shows the alight name + how many stops remain. Tapping
  /// the active card disarms the alert (parallel to tapping the stop
  /// again in RouteProgress).
  Widget _onBusAlertCard(LyneTheme t, RouteInfo ri, Service s) {
    final alightIdx = _alightCode == null
        ? -1
        : ri.stops.indexWhere((x) => x.code == _alightCode);
    final enabled = alightIdx >= 0;
    final alightName = enabled ? ri.stops[alightIdx].name : null;
    final base = ri.busIndex ?? ri.youIndex;
    final stopsToAlight = enabled ? (alightIdx - base).clamp(0, 1 << 30) : 0;

    return InkWell(
      onTap: enabled ? () => _onAlightChanged(null) : null,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Opacity(
          opacity: enabled ? 1 : 0.65,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.directions_walk,
                    size: 16, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled
                          ? 'Buzz me 2 stops before $alightName'
                          : 'Riding this bus? Pick where to alight',
                      style: t.sans(13, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? '$stopsToAlight stop${stopsToAlight == 1 ? "" : "s"} until arrival · tap to cancel'
                          : 'Tap a stop in the journey below to set as your destination',
                      style: t.sans(11, color: t.dim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36, height: 22,
                decoration: BoxDecoration(
                  color: enabled ? t.accent : t.line,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment:
                      enabled ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 18, height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
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

  Widget _serviceHeading(LyneTheme t, Service s, String stopName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BusChip(no: s.no, size: ChipSize.lg),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // s.dest is this run's terminus — the "To " prefix makes the
              // "heading towards" relationship explicit so it can't be
              // misread as the stop you're at.
              Text('To ${s.dest}',
                  style: t.sans(22, weight: FontWeight.w600)
                      .copyWith(letterSpacing: -0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              // Names the stop this screen is tracking — matches the hero
              // card's "arriving at your stop" line below.
              Text(
                'YOUR STOP · ${stopName.toUpperCase()}',
                style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.6),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroCapacityCard(LyneTheme t, Service s) {
    final etaMin = (s.etaSec / 60).floor();
    final estimate = !s.monitored;
    final big = etaMin <= 0
        ? 'Arr'
        : '${estimate ? '~' : ''}$etaMin';
    final unit = etaMin <= 0 ? 'now' : 'min';
    // LTA's Load field has exactly 3 levels — SEA (seats), SDA (standing
    // only), LSD (limited standing / packed). The meter has 3 segments and
    // fills up as the bus gets MORE crowded, so a full red meter reads as
    // "this bus is packed", not "lots of room".
    final crowding = switch (s.load) {
      Load.sea => 1,
      Load.sda => 2,
      Load.lsd => 3,
    };
    final loadColor = switch (s.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };
    final loadText = switch (s.load) {
      Load.sea => 'Seats free',
      Load.sda => 'Standing only',
      Load.lsd => 'Crowded',
    };

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.lineHi),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MicroLabel('Arriving at your stop'),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(big,
                        style: t.mono(36, weight: FontWeight.w600, color: t.accent)
                            .copyWith(letterSpacing: -0.6)),
                    const SizedBox(width: 4),
                    Text(unit, style: t.mono(13, color: t.accent)),
                  ],
                ),
                if (estimate) ...[
                  const SizedBox(height: 4),
                  Text('~ timetable estimate · no live GPS',
                      style: t.mono(10, color: t.warn)
                          .copyWith(letterSpacing: 0.3)),
                ],
              ],
            ),
          ),
          Container(width: 1, height: 44, color: t.line),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MicroLabel('Crowding'),
              const SizedBox(height: 7),
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Container(
                      width: 11, height: 14,
                      decoration: BoxDecoration(
                        color: i < crowding
                            ? loadColor
                            : t.fg.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              Text(loadText,
                  style: t.sans(11, weight: FontWeight.w600, color: loadColor)),
            ],
          ),
        ],
      ),
    );
  }

  /// "live · updated Ns ago" — recomputed every AppModel tick (1s) so the
  /// commuter can see at a glance how stale the arrivals are. Directly
  /// answers the most common gripe with SG bus apps: not knowing whether a
  /// shown time is fresh or a frozen reading.
  String? _freshnessText() {
    final at = DataStore.shared.lastFetchedAt(widget.stopCode);
    if (at == null) return null;
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs < 8) return 'live · updated just now';
    if (secs < 60) return 'live · updated ${secs}s ago';
    return 'updated ${secs ~/ 60} min ago';
  }

  /// First/last scheduled bus for the drilled-in service at this stop.
  /// Returns null until the BusRoutes dataset loads, or when the service
  /// doesn't run on today's day-type.
  Widget? _operatingHoursCard(LyneTheme t, AppModel m, Service s) {
    final timings = DataStore.shared
        .busTimings(serviceNo: s.no, stopCode: widget.stopCode);
    if (timings == null) return null;
    final first = fmtClock(timings.first, use24h: m.use24h);
    final last = fmtClock(timings.last, use24h: m.use24h);
    final gone = lastBusGone(timings.first, timings.last, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: gone ? t.crit.withValues(alpha: 0.4) : t.lineHi),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _hoursCol(t, 'First bus today', first)),
              const SizedBox(width: 16),
              Container(width: 1, height: 38, color: t.line),
              const SizedBox(width: 16),
              Expanded(child: _hoursCol(t, 'Last bus today', last)),
            ],
          ),
          if (gone) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.nightlight_round, size: 13, color: t.crit),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last bus has departed for today — plan another way home.',
                    style: t.mono(10, color: t.crit)
                        .copyWith(height: 1.5, letterSpacing: 0.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _hoursCol(LyneTheme t, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MicroLabel(label),
          const SizedBox(height: 7),
          Text(value,
              style: t.mono(18, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.3)),
        ],
      );

  Widget _sectionLabel(LyneTheme t, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MicroLabel(label),
          const Spacer(),
          if (hint != null)
            Text(hint.toUpperCase(),
                style: t.mono(10, color: t.faint).copyWith(letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
