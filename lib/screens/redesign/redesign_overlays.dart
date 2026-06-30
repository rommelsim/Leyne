// Overlays drawn above the app content: the full-screen Search sheet, the
// Live Update glass tracking card, and the Toast snackbar.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/data_store.dart';
import '../../data/lta_models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import 'redesign_bridge.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_theme.dart';

// =============================================================== SEARCH

class RdSearchOverlay extends StatefulWidget {
  const RdSearchOverlay({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdSearchOverlay> createState() => _RdSearchOverlayState();
}

class _RdSearchOverlayState extends State<RdSearchOverlay> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openBus(String svc) async {
    final origin = await DataStore.shared.originStop(svc);
    if (mounted) widget.c.openBus(svc, origin?.busStopCode);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = RdTheme.of(context);
    final q = _ctrl.text.trim();
    final services = q.isEmpty ? const <LtaBusService>[] : DataStore.shared.searchServices(q);
    final stations = q.isEmpty ? const <MrtGeoStation>[] : MrtGeo.matching(q);
    final stops = q.isEmpty ? const <LtaBusStop>[] : DataStore.shared.searchStops(q);

    final rows = <Widget>[];
    if (q.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
        child: Column(children: [
          RdIcon(Symbols.search, size: 30, color: t.outline),
          const SizedBox(height: 8),
          Text('Search for a stop, bus number or MRT station',
              textAlign: TextAlign.center,
              style: rdText(size: 13, weight: FontWeight.w500, color: t.onVariant)),
        ]),
      ));
    } else if (services.isEmpty && stations.isEmpty && stops.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Center(
          child: Text('No matches for “$q”', style: rdText(size: 13, weight: FontWeight.w500, color: t.onVariant)),
        ),
      ));
    } else {
      if (services.isNotEmpty) {
        rows.add(_label(t, 'BUSES'));
        for (final s in services.take(6)) {
          rows.add(_ResultRow(
            iconBg: t.primaryContainer,
            iconColor: t.onPrimaryContainer,
            icon: Symbols.directions_bus,
            bold: 'Bus ',
            rest: s.serviceNo,
            sub: 'Tap to see the route',
            onTap: () => _openBus(s.serviceNo),
          ));
        }
      }
      if (stations.isNotEmpty) {
        rows.add(_label(t, 'MRT / LRT'));
        for (final st in stations.take(6)) {
          final code = st.codes.isNotEmpty ? st.codes.first : '';
          rows.add(_ResultRow(
            iconBg: lineColorFor(code),
            iconColor: rdMrtBadgeFg(code),
            icon: Symbols.train,
            bold: st.name,
            rest: '',
            sub: st.codes.join(' · '),
            onTap: () => c.openStationNamed(st.name),
          ));
        }
      }
      if (stops.isNotEmpty) {
        rows.add(_label(t, 'STOPS'));
        for (final s in stops.take(12)) {
          rows.add(_ResultRow(
            iconBg: t.busContainer,
            iconColor: t.onBusContainer,
            icon: Symbols.signpost,
            bold: s.description,
            rest: '',
            sub: '${s.roadName} · ${s.busStopCode}',
            onTap: () => c.openStopCode(s.busStopCode),
          ));
        }
      }
    }

    return Positioned.fill(
      child: Container(
        color: t.surface,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(27)),
                  child: Row(
                    children: [
                      GestureDetector(onTap: c.closeSearch, child: RdIcon(Symbols.arrow_back, size: 23, color: t.onSurface)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          autofocus: true,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          cursorColor: t.primary,
                          style: rdText(size: 16, weight: FontWeight.w500, color: t.onSurface),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Search stops, buses, MRT',
                            hintStyle: rdText(size: 16, weight: FontWeight.w500, color: t.onVariant),
                          ),
                        ),
                      ),
                      if (_ctrl.text.isNotEmpty)
                        GestureDetector(onTap: () => _ctrl.clear(), child: RdIcon(Symbols.close, size: 22, color: t.onVariant)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: rows),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(RdTokens t, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Text(s, style: rdText(size: 12, weight: FontWeight.w700, color: t.onVariant, letterSpacing: 0.24)),
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.bold,
    required this.rest,
    required this.sub,
    required this.onTap,
  });
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String bold;
  final String rest;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: RdIcon(icon, size: 20, color: iconColor, fill: 1),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: bold, style: rdText(size: 15, weight: FontWeight.w700, color: t.onSurface)),
                      TextSpan(text: rest, style: rdText(size: 15, weight: FontWeight.w600, color: t.onSurface)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ),
            ),
            RdIcon(Symbols.north_west, size: 16, color: t.outline),
          ],
        ),
      ),
    );
  }
}

// ============================================================ LIVE UPDATE

class RdLiveUpdate extends StatelessWidget {
  const RdLiveUpdate({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 10,
      right: 10,
      child: SafeArea(
        bottom: false,
        child: _LiveCard(c: c),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.c});
  final RedesignController c;

  static const _accent = Color(0xFF9CC0FF);
  static const _onAccent = Color(0xFF10245E);
  static const _white = Color(0xFFFFFFFF);

  String get _svc => c.activeService ?? '';
  String get _trackedStop =>
      c.activeRouteStop != null ? DataStore.shared.stopName(c.activeRouteStop!) : 'your stop';
  String get _eta {
    final code = c.activeRouteStop;
    if (code == null) return '—';
    for (final s in DataStore.shared.servicesFor(code)) {
      if (s.no == _svc) return rdMinLabel(s.etaSec);
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xD114121C),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2C72E6), Color(0xFF222A38)],
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RdIcon(Symbols.directions_bus, size: 8, color: _white, fill: 1),
                    RdIcon(Symbols.train, size: 8, color: _white, fill: 1),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text('SG Transit', style: rdText(size: 12, weight: FontWeight.w700, color: const Color(0xE6FFFFFF))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x389CC0FF), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RdDot(_accent, size: 5),
                    const SizedBox(width: 4),
                    Text('LIVE', style: rdText(size: 10, weight: FontWeight.w800, color: _accent)),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: c.dismissLU,
                child: RdIcon(Symbols.close, size: 18, color: const Color(0x8CFFFFFF)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bus $_svc → your stop', style: rdText(size: 16, weight: FontWeight.w700, color: _white)),
                    const SizedBox(height: 2),
                    Text('Approaching $_trackedStop',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rdText(size: 12.5, weight: FontWeight.w500, color: const Color(0xA6FFFFFF))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_eta, style: rdText(size: 36, weight: FontWeight.w900, color: _accent, height: 1, letterSpacing: -1.08)),
                  Text('min', style: rdText(size: 11, weight: FontWeight.w600, color: const Color(0xB3FFFFFF))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // progress bar at 78%
          LayoutBuilder(builder: (context, cons) {
            return SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(3)),
                  ),
                  FractionallySizedBox(
                    widthFactor: 0.78,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  Positioned(
                    left: cons.maxWidth * 0.78 - 9,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [BoxShadow(color: Color(0x409CC0FF), blurRadius: 0, spreadRadius: 4)],
                      ),
                      alignment: Alignment.center,
                      child: RdIcon(Symbols.directions_bus, size: 11, color: _onAccent, fill: 1),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: c.stopTrack,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(color: const Color(0x47FFFFFF)),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RdIcon(Symbols.stop_circle, size: 18, color: _white),
                        const SizedBox(width: 7),
                        Text('Stop', style: rdText(size: 13.5, weight: FontWeight.w700, color: _white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: GestureDetector(
                  onTap: c.luView,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(21)),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RdIcon(Symbols.map, size: 18, color: _onAccent),
                        const SizedBox(width: 7),
                        Text('View route', style: rdText(size: 13.5, weight: FontWeight.w700, color: _onAccent)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================================================================= TOAST

class RdToast extends StatelessWidget {
  const RdToast({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 14,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2A33),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 34, offset: Offset(0, 14))],
          ),
          child: Row(
            children: [
              RdIcon(Symbols.notifications_active, size: 21, color: const Color(0xFF9CC0FF), fill: 1),
              const SizedBox(width: 12),
              Expanded(
                child: Text(c.toast ?? '',
                    style: rdText(size: 12.5, weight: FontWeight.w500, color: const Color(0xFFE9E5EE), height: 1.35)),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: c.dismissToast,
                child: Text('Got it', style: rdText(size: 13, weight: FontWeight.w700, color: const Color(0xFF9CC0FF))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
