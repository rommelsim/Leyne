// ETA pill — the "3 min" / "Arr" headline rendered for one service.
//
// Visual rules (legacy PinnedCardView.swift):
//   • live=true → green text + soft green background (eta ≤ 1 min)
//   • live=false → muted body text
//   • "Arr/now" is shown when sec ≤ 0 or sec < 60.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';

class EtaPill extends StatelessWidget {
  const EtaPill({super.key, required this.etaSec});
  final int etaSec;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final eta = fmtEta(etaSec);
    final color = eta.live ? t.live : t.fg;
    final bg = eta.live ? t.liveBg : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(eta.big,
              style: t.mono(18, weight: FontWeight.w700).copyWith(color: color)),
          const SizedBox(width: 4),
          Text(eta.small,
              style: t.mono(11).copyWith(color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}
