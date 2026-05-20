// Vertical route progress — a window of stops centred on the bus and
// your stop, with a tap-to-alight column and live status badges.
//
// Same focus-window logic as legacy DetailView.swift RouteProgress:
//   lo = min(busIndex ?? youIndex, youIndex) - 1
//   hi = max(busIndex ?? youIndex, youIndex) + 5

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../theme.dart';

class RouteProgress extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.t;
    final busIdx = route.busIndex ?? -1;
    final base = busIdx >= 0 ? busIdx : route.youIndex;
    final lo = (base < route.youIndex ? base : route.youIndex) - 1;
    final hi = (base > route.youIndex ? base : route.youIndex) + 5;
    final start = lo.clamp(0, route.stops.length - 1);
    final end = hi.clamp(0, route.stops.length - 1);

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
            _row(context, t, i, route.stops[i], busIdx),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, LyneTheme t, int i, RouteStopLive stop,
      int busIdx) {
    final isYou = i == route.youIndex;
    final isBus = i == busIdx;
    final isAlight = alightCode == stop.code;
    final passed = busIdx >= 0 && i < busIdx;
    final canAlight = i > (busIdx >= 0 ? busIdx : 0) && !isYou;

    final dotSize = (isYou || isAlight) ? 12.0 : 8.0;
    final dotColor = isAlight
        ? t.accent
        : isYou
            ? t.accent
            : passed
                ? t.dim
                : t.surface;

    return InkWell(
      onTap: canAlight
          ? () => onAlightChanged(isAlight ? null : stop.code)
          : null,
      child: Container(
        color: isAlight ? t.accent.withValues(alpha: 0.07) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Opacity(
          opacity: passed ? 0.45 : 1,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      children: [
                        Container(
                            width: 2,
                            height: 12,
                            color: passed ? t.dim : t.line),
                        Container(
                            width: 2,
                            height: 12,
                            color: i < busIdx ? t.dim : t.line),
                      ],
                    ),
                    Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: t.fg,
                          width: (!isYou && !isAlight && !passed) ? 2 : 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stop.name,
                      style: t.sans(
                        14,
                        weight: (isYou || isBus || isAlight)
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      stop.code +
                          (isYou ? ' · YOUR STOP' : '') +
                          (isBus ? ' · BUS HERE NOW' : '') +
                          (isAlight ? ' · ALIGHT HERE' : ''),
                      style: t.mono(10).copyWith(color: t.dim),
                    ),
                  ],
                ),
              ),
              if (isBus)
                _badge(t, 'BUS $busNo', t.live, t.liveBg,
                    borderColor: t.live)
              else if (isAlight)
                _badge(t, 'ALIGHT', Colors.white, t.accent)
              else if (canAlight)
                Text('tap to alight',
                    style:
                        t.mono(9).copyWith(color: t.dim.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(LyneTheme t, String label, Color fg, Color bg,
      {Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Text(label,
          style: t.mono(10, weight: FontWeight.w600)
              .copyWith(color: fg, letterSpacing: 0.5)),
    );
  }
}
