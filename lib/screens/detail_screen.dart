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
  String? _alightCode;
  RouteInfo? _routeInfo;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedNo = widget.initialSelectedNo;
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

  Future<void> _refresh() async {
    DataStore.shared.ensureArrivals(widget.stopCode, force: true);
    if (_selectedNo != null) await _loadRoute();
    await Future.delayed(const Duration(milliseconds: 400));
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
                  child: RefreshIndicator(
                    color: t.accent,
                    backgroundColor: t.surface,
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                      children: [
                        if (selected == null)
                          ..._stopOverview(t, m, stopName, services)
                        else
                          ..._serviceDetail(t, m, stopName, selected),
                      ],
                    ),
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
    return [
      _stopHeading(t, m, stopName),
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
    final big = etaMin <= 0 ? 'Arr' : '$etaMin';
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
    return [
      _serviceHeading(t, s, stopName),
      const SizedBox(height: 16),
      _heroCapacityCard(t, s),
      const SizedBox(height: 18),
      _sectionLabel(t, 'Live map',
          hint: _routeInfo?.busCoord == null ? 'bus gps unavailable' : null),
      RouteMap(route: _routeInfo, busNo: s.no, loading: _routeLoading),
      const SizedBox(height: 18),
      if (_routeInfo != null) ...[
        _sectionLabel(t, 'Journey',
            hint: _stopsAwayLabel(_routeInfo!)),
        RouteProgress(
          busNo: s.no,
          route: _routeInfo!,
          alightCode: _alightCode,
          onAlightChanged: (code) => setState(() => _alightCode = code),
        ),
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
              Text(s.dest,
                  style: t.sans(22, weight: FontWeight.w600)
                      .copyWith(letterSpacing: -0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '${s.deck.word.toUpperCase()} · FROM $stopName'.toUpperCase(),
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
    final big = etaMin <= 0 ? 'Arr' : '$etaMin';
    final unit = etaMin <= 0 ? 'now' : 'min';
    final bars = switch (s.load) {
      Load.sea => 5,
      Load.sda => 3,
      Load.lsd => 1,
    };
    final loadColor = switch (s.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
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
              ],
            ),
          ),
          Container(width: 1, height: 36, color: t.line),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MicroLabel('Capacity'),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Container(
                      width: 8, height: 16,
                      decoration: BoxDecoration(
                        color: i < bars
                            ? loadColor
                            : t.fg.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(s.load.label,
                      style: t.sans(11, color: t.dim)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

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
