// Route timeline — the vertical rail on the Route screen: passed stops
// (collapsible), the live bus position, the rider's stop, downstream stops
// (collapsible) and the terminus. Passed/downstream segments are dotted; the
// active region around the live bus uses a flowing primary dash.

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/data_store.dart';
import 'redesign_bridge.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_theme.dart';

class RdRouteTimeline extends StatefulWidget {
  const RdRouteTimeline({super.key, required this.c, required this.route});
  final RedesignController c;
  final RouteInfo route;

  @override
  State<RdRouteTimeline> createState() => _RdRouteTimelineState();
}

class _RdRouteTimelineState extends State<RdRouteTimeline> with SingleTickerProviderStateMixin {
  late final AnimationController _flow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final c = widget.c;
    final stops = widget.route.stops;
    if (stops.isEmpty) {
      return Text('Route stops unavailable',
          style: rdText(size: 13, weight: FontWeight.w500, color: t.onVariant));
    }

    final you = widget.route.youIndex.clamp(0, stops.length - 1);
    final rawBus = widget.route.busIndex;
    // Show the live-bus marker only when LTA placed it upstream of the rider's
    // stop (the "approaching" case); otherwise omit it honestly.
    final int? bus = (rawBus != null && rawBus >= 0 && rawBus < you) ? rawBus : null;
    final firstActive = bus ?? you;
    final lastIdx = stops.length - 1;
    final rows = <Widget>[];

    // 1 — passed stops (collapsible).
    if (firstActive > 0) {
      if (!c.routeExpanded) {
        rows.add(_RailRow(
          line: _Seg(t.outlineVariant, dotted: true),
          node: _Dot(color: t.surface, border: t.outlineVariant, size: 9),
          onTap: c.toggleRoute,
          child: Row(children: [
            Text('$firstActive stop${firstActive == 1 ? '' : 's'} passed',
                style: rdText(size: 12.5, weight: FontWeight.w600, color: t.onVariant)),
            const SizedBox(width: 5),
            RdIcon(Symbols.expand_more, size: 17, color: t.outline),
          ]),
        ));
      } else {
        rows.add(_Toggle(label: 'Hide passed stops', onTap: c.toggleRoute));
        for (var i = 0; i < firstActive; i++) {
          final code = stops[i].code;
          rows.add(_RailRow(
            line: _Seg(t.outlineVariant),
            node: _Dot(color: t.outlineVariant, size: 9),
            onTap: () => c.openStopCode(code),
            child: _stopLabel(t, stops[i].name, t.onVariant),
          ));
        }
      }
    }

    // 2 — live bus.
    if (bus != null) {
      final approaching = (bus + 1 <= lastIdx) ? stops[bus + 1].name : stops[bus].name;
      rows.add(_RailRow(
        line: _Seg(t.primary, dotted: true, flow: true),
        node: _BusNode(flow: _flow),
        nodeTop: 0,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bus is here now', style: rdText(size: 13.5, weight: FontWeight.w800, color: t.primary)),
            Text('Approaching $approaching', style: rdText(size: 11, weight: FontWeight.w500, color: t.onVariant)),
          ]),
        ),
      ));
    }

    // 3 — upcoming stops (between the bus and your stop).
    for (var i = firstActive; i < you; i++) {
      final code = stops[i].code;
      rows.add(_RailRow(
        line: _Seg(t.primary, dotted: true, flow: true),
        node: _Dot(color: t.primary, size: 11),
        onTap: () => c.openStopCode(code),
        child: Row(
          children: [
            Expanded(child: _stopLabel(t, stops[i].name, t.onSurface)),
            RdIcon(Symbols.chevron_right, size: 16, color: t.outline),
          ],
        ),
      ));
    }

    // 4 — your stop.
    rows.add(_RailRow(
      line: lastIdx > you ? _Seg(t.outlineVariant, dotted: true) : null,
      node: _Ring(color: t.primary, surface: t.surface),
      nodeTop: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: t.primaryContainer, borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(stops[you].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: rdText(size: 14.5, weight: FontWeight.w800, color: t.onPrimaryContainer)),
          Text('YOUR STOP',
              style: rdText(size: 9.5, weight: FontWeight.w700, color: t.onPrimaryContainer, letterSpacing: 0.48)),
        ]),
      ),
    ));

    // 5 + 6 — downstream stops (collapsible) and terminus.
    final downStart = you + 1;
    if (downStart <= lastIdx) {
      final downCount = lastIdx - downStart;
      if (downCount > 0) {
        if (!c.routeDownExpanded) {
          rows.add(_RailRow(
            line: _Seg(t.outlineVariant, dotted: true),
            node: _Dot(color: t.surface, border: t.outlineVariant, size: 9),
            onTap: c.toggleRouteDown,
            child: Row(children: [
              Text('$downCount more stop${downCount == 1 ? '' : 's'}',
                  style: rdText(size: 12.5, weight: FontWeight.w600, color: t.primary)),
              const SizedBox(width: 5),
              RdIcon(Symbols.expand_more, size: 17, color: t.primary),
            ]),
          ));
        } else {
          for (var i = downStart; i < lastIdx; i++) {
            final code = stops[i].code;
            rows.add(_RailRow(
              line: _Seg(t.outlineVariant),
              node: _Dot(color: t.surface, border: t.outlineVariant, size: 9),
              onTap: () => c.openStopCode(code),
              child: Row(
                children: [
                  Expanded(child: _stopLabel(t, stops[i].name, t.onVariant)),
                  RdIcon(Symbols.chevron_right, size: 16, color: t.outline),
                ],
              ),
            ));
          }
          rows.add(_Toggle(label: 'Hide stops', onTap: c.toggleRouteDown));
        }
      }
      // Terminus.
      rows.add(_RailRow(
        line: null,
        node: RdIcon(Symbols.place, size: 18, color: t.onVariant, fill: 1),
        nodeTop: 1,
        onTap: () => c.openStopCode(stops[lastIdx].code),
        child: Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stops[lastIdx].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rdText(size: 14, weight: FontWeight.w700, color: t.onSurface)),
                Text('Terminus', style: rdText(size: 11, weight: FontWeight.w500, color: t.outline)),
              ]),
            ),
            RdIcon(Symbols.chevron_right, size: 16, color: t.outline),
          ],
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// Stop name + an MRT line-colour badge when it's an interchange (item 3).
  Widget _stopLabel(RdTokens t, String name, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: rdText(size: 14, weight: FontWeight.w500, color: color)),
        ),
        RdMrtBadgeRow(stopName: name, size: 8),
      ],
    );
  }
}

/// Description of the vertical line drawn behind a rail node.
class _Seg {
  const _Seg(this.color, {this.dotted = false, this.flow = false});
  final Color color;
  final bool dotted;
  final bool flow;
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.node,
    required this.child,
    this.line,
    this.nodeTop = 4,
    this.onTap,
  });

  final Widget node;
  final Widget child;
  final _Seg? line;
  final double nodeTop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Stack(
              children: [
                if (line != null)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 8,
                    width: 2,
                    child: line!.dotted
                        ? CustomPaint(painter: _DottedLinePainter(line!.color))
                        : Container(color: line!.color),
                  ),
                Positioned(
                  top: nodeTop,
                  left: 0,
                  right: 0,
                  child: Center(child: node),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: child,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: row);
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 18, child: Center(child: RdIcon(Symbols.expand_less, size: 17, color: t.primary))),
            const SizedBox(width: 14),
            Text(label, style: rdText(size: 11.5, weight: FontWeight.w600, color: t.primary)),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.border, required this.size});
  final Color color;
  final Color? border;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border != null ? Border.all(color: border!, width: 2) : null,
      ),
      // keep a surface ring so the line doesn't bleed through filled dots
      foregroundDecoration: border == null
          ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.surface, width: 1.5))
          : null,
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.surface});
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 4),
      ),
    );
  }
}

class _BusNode extends StatelessWidget {
  const _BusNode({required this.flow});
  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: flow,
            builder: (_, _) {
              final v = flow.value;
              return Container(
                width: 28 + v * 10,
                height: 28 + v * 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.primary.withValues(alpha: (1 - v) * 0.35),
                ),
              );
            },
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: t.primary,
              shape: BoxShape.circle,
              border: Border.all(color: t.surface, width: 3),
            ),
            alignment: Alignment.center,
            child: RdIcon(Symbols.directions_bus, size: 16, color: const Color(0xFFFFFFFF), fill: 1),
          ),
        ],
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  _DottedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 2.0, gap = 4.0;
    double y = 0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter old) => old.color != color;
}
