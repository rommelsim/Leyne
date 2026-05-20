// Detail — stop overview → drill into a service for a real route + map.
//
// Two modes:
//   • Stop overview: header + service list with per-bus track toggles.
//     Tapping a service row sets `selectedNo` and drills in.
//   • Service drill-in: hero card, Start Live Activity stub (Task #12),
//     split RouteMap (Apple iOS / Google Android), RouteProgress with
//     tap-to-alight.
//
// Entered with `initialSelectedNo` to land directly in service drill-in
// (e.g. tapping a specific bus row on a Home card).

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/eta_pill.dart';
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
  String? _alightCode;
  RouteInfo? _routeInfo;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedNo = widget.initialSelectedNo;
    // Force a fresh arrivals fetch on entry; the Home/Nearby cards may be
    // showing slightly stale data and Detail should match what's on LTA now.
    DataStore.shared.ensureArrivals(widget.stopCode, force: true);
    if (_selectedNo != null) _loadRoute();
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
                _topBar(t, m, pinned, selected, stopName),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: [
                      _heading(t, m, stopName, selected),
                      if (selected == null)
                        ..._stopOverview(t, m, services)
                      else
                        ..._serviceDetail(t, m, selected),
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

  // ─── Top bar ─────────────────────────────────────────────────

  Widget _topBar(LyneTheme t, AppModel m, bool pinned, Service? selected,
      String stopName) {
    final backLabel = selected != null
        ? (_enteredViaService ? 'Back' : stopName)
        : 'Close';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _backOrPop,
            icon: const Icon(Icons.chevron_left, size: 20),
            label: Text(
              backLabel,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              foregroundColor: t.accent,
              textStyle: t.sans(16, weight: FontWeight.w500),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => m.togglePin(widget.stopCode),
            icon: Icon(pinned ? Icons.bookmark : Icons.bookmark_outline,
                size: 13),
            label: Text(pinned ? 'Pinned stop' : 'Pin stop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: pinned ? t.accent : t.fg,
              backgroundColor: pinned
                  ? t.accent.withValues(alpha: 0.08)
                  : Colors.transparent,
              side: BorderSide(
                  color: pinned
                      ? t.accent.withValues(alpha: 0.25)
                      : t.line),
              shape: const StadiumBorder(),
              textStyle: t.sans(12, weight: FontWeight.w500),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Heading ─────────────────────────────────────────────────

  Widget _heading(LyneTheme t, AppModel m, String stopName, Service? selected) {
    final pin = m.pinForCode(widget.stopCode);
    final label = pin?.nickname.isNotEmpty == true ? pin!.nickname : stopName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: t.accent.withValues(alpha: 0.25)),
                ),
                child: Text(label,
                    style: t.sans(11, weight: FontWeight.w600)
                        .copyWith(color: t.accent)),
              ),
              const SizedBox(width: 8),
              Text('· STOP ${widget.stopCode}',
                  style: t.mono(10, weight: FontWeight.w600)
                      .copyWith(color: t.dim, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 6),
          Text(stopName, style: t.sans(24, weight: FontWeight.w600)),
          if (selected != null) ...[
            const SizedBox(height: 6),
            Text('VIEWING BUS ${selected.no} → ${selected.dest}',
                style: t.mono(11).copyWith(color: t.dim, letterSpacing: 1)),
          ],
        ],
      ),
    );
  }

  // ─── Mode A: Stop overview ──────────────────────────────────

  List<Widget> _stopOverview(LyneTheme t, AppModel m, List<Service> services) {
    if (services.isEmpty) {
      final state = DataStore.shared.arrivals[widget.stopCode];
      return [_arrivalsPlaceholder(t, state)];
    }
    final allNos = services.map((s) => s.no).toList();
    final tracked = allNos
        .where((no) => m.isTracked(code: widget.stopCode, busNo: no))
        .length;
    final allOn = m.allTracked(widget.stopCode);

    return [
      _sectionLabel(t, 'SERVICES AT THIS STOP', hint: 'tap a bus to drill in'),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              onTap: () => m.setAllTracked(
                code: widget.stopCode,
                allNos: allNos,
                tracked: !allOn,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(allOn ? 'Untrack all' : 'Track all',
                        style: t.sans(13, weight: FontWeight.w600)
                            .copyWith(color: t.accent)),
                    const Spacer(),
                    Text('$tracked/${allNos.length}',
                        style: t.mono(11).copyWith(color: t.dim)),
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
      const SizedBox(height: 14),
      Text(
        'Tap the bookmark to add/remove a bus from your Home view.',
        style: t.mono(11).copyWith(color: t.dim),
      ),
    ];
  }

  Widget _serviceTapRow(
      LyneTheme t, AppModel m, Service s, List<String> allNos) {
    final tracked = m.isTracked(code: widget.stopCode, busNo: s.no);
    final arriving = s.etaSec <= 60;
    return InkWell(
      onTap: () => _selectService(s.no),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: arriving ? t.liveBg : Colors.transparent,
        child: Opacity(
          opacity: tracked ? 1 : 0.55,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  tracked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: tracked ? t.accent : t.line,
                  size: 22,
                ),
                onPressed: () => m.toggleTracked(
                  code: widget.stopCode,
                  busNo: s.no,
                  allNos: allNos,
                ),
              ),
              const SizedBox(width: 4),
              Text(s.no,
                  style: t.mono(20, weight: FontWeight.w700)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.dest,
                        style: t.sans(13, weight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    Text(s.load.label,
                        style: t.mono(10).copyWith(color: t.dim)),
                  ],
                ),
              ),
              EtaPill(etaSec: s.etaSec),
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
              style: t.sans(12).copyWith(color: t.dim)),
        ],
      );
    } else if (kind == ArrivalStateKind.error) {
      body = Column(
        children: [
          Text('Couldn’t load arrivals',
              style: t.sans(13, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(msg ?? '', style: t.sans(11).copyWith(color: t.dim)),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: t.accent),
            onPressed: () =>
                DataStore.shared.ensureArrivals(widget.stopCode, force: true),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      body = Text('No buses running here right now',
          style: t.sans(13).copyWith(color: t.dim));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: body),
    );
  }

  // ─── Mode B: Service drill-in ────────────────────────────────

  List<Widget> _serviceDetail(LyneTheme t, AppModel m, Service s) {
    return [
      _heroCard(t, s),
      const SizedBox(height: 14),
      _liveActivityStub(t, s),
      const SizedBox(height: 18),
      _sectionLabel(t, 'LIVE MAP',
          hint: _routeInfo?.busCoord == null ? 'BUS GPS UNAVAILABLE' : null),
      RouteMap(route: _routeInfo, busNo: s.no, loading: _routeLoading),
      const SizedBox(height: 18),
      if (_routeInfo != null) ...[
        _sectionLabel(t, 'ROUTE PROGRESS',
            hint: _stopsAwayLabel(_routeInfo!)),
        RouteProgress(
          busNo: s.no,
          route: _routeInfo!,
          alightCode: _alightCode,
          onAlightChanged: (code) => setState(() => _alightCode = code),
        ),
      ] else if (_routeLoading) ...[
        _sectionLabel(t, 'ROUTE PROGRESS'),
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
                  style: t.sans(12).copyWith(color: t.dim)),
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

  Widget _heroCard(LyneTheme t, Service s) {
    final eta = fmtEta(s.etaSec);
    final loadColor = switch (s.load) {
      Load.sea => t.live,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.line),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.no, style: t.mono(22, weight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('→ ${s.dest}',
                          style: t.sans(12).copyWith(color: t.dim),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('NEXT ARRIVAL',
                    style: t.mono(11)
                        .copyWith(color: t.dim, letterSpacing: 1)),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                eta.big,
                style: t.mono(eta.big == 'Arr' ? 36 : 56,
                        weight: FontWeight.w300)
                    .copyWith(color: loadColor),
              ),
              const SizedBox(width: 4),
              Text(eta.small,
                  style: t.mono(15).copyWith(color: t.dim)),
            ],
          ),
        ],
      ),
    );
  }

  /// Placeholder for the iOS Live Activity start/stop button. Re-added in
  /// Task #12 via Flutter MethodChannel → native Swift ActivityKit code
  /// from legacy/ios-native/LyneWidgets/.
  Widget _liveActivityStub(LyneTheme t, Service s) {
    return InkWell(
      onTap: null,
      child: Container(
        decoration: BoxDecoration(
          color: t.fg,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: t.bg.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.lock_outline,
                  color: t.bg.withValues(alpha: 0.6), size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live Activity — coming back in Task #12',
                      style: t.sans(13, weight: FontWeight.w600)
                          .copyWith(color: t.bg)),
                  Text('iOS-only · re-wired via MethodChannel',
                      style: t.sans(11).copyWith(
                          color: t.bg.withValues(alpha: 0.65))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(LyneTheme t, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: t.mono(11, weight: FontWeight.w600)
                  .copyWith(color: t.dim, letterSpacing: 1)),
          const Spacer(),
          if (hint != null)
            Text(hint,
                style: t.mono(10).copyWith(color: t.dim, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
