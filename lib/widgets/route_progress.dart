// Vertical route progress — a focused window of stops centred on the bus
// and your stop. Tap-to-alight column on the right; mint dot with halo
// marks the bus's current position, dim dots mark stops it's passed.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../theme.dart';

class RouteProgress extends StatefulWidget {
  const RouteProgress({
    super.key,
    required this.busNo,
    required this.route,
    required this.alightCode,
    required this.onAlightChanged,
  });

  final String busNo;
  final RouteInfo route;
  final String? alightCode;
  final ValueChanged<String?> onAlightChanged;

  @override
  State<RouteProgress> createState() => _RouteProgressState();
}

class _RouteProgressState extends State<RouteProgress> {
  /// When true, the card swaps from the focused window to the full
  /// route list. Driven by the "Show all N stops" expander pinned at
  /// the bottom of the card; collapses back to the window on tap.
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final route = widget.route;
    final busIdx = route.busIndex ?? -1;
    final base = busIdx >= 0 ? busIdx : route.youIndex;
    final lo = (base < route.youIndex ? base : route.youIndex) - 1;
    var hi = (base > route.youIndex ? base : route.youIndex) + 5;
    // Pull the alight stop into view when it sits past the default
    // window upper bound. Capped to one beyond the alight so we don't
    // accidentally render every stop on long routes — the expander
    // handles the "show me everything" case.
    final alightCode = widget.alightCode;
    if (alightCode != null) {
      final alightIdx =
          route.stops.indexWhere((s) => s.code == alightCode);
      if (alightIdx > hi) hi = alightIdx + 1;
    }
    final start = _showAll ? 0 : lo.clamp(0, route.stops.length - 1);
    final end = _showAll
        ? route.stops.length - 1
        : hi.clamp(0, route.stops.length - 1);
    final hasHiddenStops =
        !_showAll && (end - start + 1) < route.stops.length;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = start; i <= end; i++)
            _row(t, i, route.stops[i], busIdx,
                isFirst: i == start, isLast: i == end),
          if (hasHiddenStops || _showAll)
            _expander(t, route.stops.length),
        ],
      ),
    );
  }

  Widget _expander(LyneTheme t, int total) {
    return InkWell(
      onTap: () => setState(() => _showAll = !_showAll),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.line)),
        ),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 14, color: t.accent),
            const SizedBox(width: 6),
            Text(
              _showAll
                  ? 'Show focused view'
                  : 'Show all $total stops',
              style: t.mono(11,
                      weight: FontWeight.w500, color: t.accent)
                  .copyWith(letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(LyneTheme t, int i, RouteStopLive stop, int busIdx,
      {required bool isFirst, required bool isLast}) {
    final isYou = i == widget.route.youIndex;
    final isBus = i == busIdx;
    final isAlight = widget.alightCode == stop.code;
    final passed = busIdx >= 0 && i < busIdx;
    final canAlight = i > (busIdx >= 0 ? busIdx : 0) && !isYou;
    final isEnd = i == widget.route.stops.length - 1;

    return InkWell(
      onTap: canAlight
          ? () => widget.onAlightChanged(isAlight ? null : stop.code)
          : null,
      child: Container(
        color: (isYou || isAlight)
            ? t.accent.withValues(alpha: 0.07)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _trailIndicator(t, isFirst: isFirst, isLast: isLast,
                isBus: isBus, isYou: isYou, isAlight: isAlight, passed: passed),
            const SizedBox(width: 14),
            Expanded(
              child: Opacity(
                opacity: passed ? 0.45 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stop.name,
                            style: t.sans(14,
                                weight: (isYou || isBus || isAlight)
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: (isBus || isYou) ? t.accent : t.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEnd) ...[
                          const SizedBox(width: 6),
                          Text('END',
                              style: t.mono(10, color: t.dim)
                                  .copyWith(letterSpacing: 0.6)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'STOP ${stop.code}',
                      style: t.mono(10, color: t.faint)
                          .copyWith(letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
            ),
            if (isBus)
              _trailingBadge(t, 'BUS ${widget.busNo}', t.accent)
            else if (isYou)
              _trailingBadge(t, 'BOARD HERE', t.accent, filled: true)
            else if (isAlight)
              _trailingBadge(t, 'ALIGHT', t.fg, filled: true)
            else if (canAlight)
              Text('tap to alight',
                  style: t.mono(9, color: t.faint)),
          ],
        ),
      ),
    );
  }

  Widget _trailIndicator(LyneTheme t,
      {required bool isFirst,
      required bool isLast,
      required bool isBus,
      required bool isYou,
      required bool isAlight,
      required bool passed}) {
    final lineColor = passed ? t.accent.withValues(alpha: 0.5) : t.line;
    return SizedBox(
      width: 20,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!isFirst)
            Positioned(
              top: 0, bottom: 15,
              child: Container(width: 2, color: lineColor),
            ),
          if (!isLast)
            Positioned(
              top: 15, bottom: 0,
              child: Container(
                  width: 2,
                  color: passed && !isBus
                      ? t.accent.withValues(alpha: 0.5)
                      : t.line),
            ),
          _dot(t, isBus: isBus, isYou: isYou, isAlight: isAlight, passed: passed),
        ],
      ),
    );
  }

  Widget _dot(LyneTheme t,
      {required bool isBus,
      required bool isYou,
      required bool isAlight,
      required bool passed}) {
    if (isBus) {
      return Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          color: t.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: t.accent.withValues(alpha: 0.35),
              blurRadius: 0, spreadRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            color: t.contrastFg, shape: BoxShape.circle,
          ),
        ),
      );
    }
    final outline = isYou || isAlight ? t.accent : (passed ? t.accent.withValues(alpha: 0.5) : t.line);
    final fill = isYou || isAlight
        ? t.accent
        : (passed ? t.accent.withValues(alpha: 0.5) : t.bg);
    return Container(
      width: 14, height: 14,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: outline, width: 2),
      ),
    );
  }

  Widget _trailingBadge(LyneTheme t, String label, Color color,
      {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: color),
      ),
      child: Text(
        label,
        style: t.mono(10, weight: FontWeight.w600,
                color: filled ? t.contrastFg : color)
            .copyWith(letterSpacing: 0.5),
      ),
    );
  }
}
