// ETA pill — the "3 min" / "Arr now" headline rendered for one service.
//
// Mono numerals; mint when the bus is within the live window (≤ 60s),
// foreground otherwise. No background — the redesign relies on type and
// colour alone for the urgency cue.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';

class EtaPill extends StatelessWidget {
  const EtaPill({super.key, required this.etaSec, this.size = 18});

  final int etaSec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final eta = fmtEta(etaSec);
    final color = eta.live ? t.accent : t.fg;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(eta.big,
            style: t.mono(size, weight: FontWeight.w600, color: color)),
        const SizedBox(width: 3),
        Text(eta.small,
            style: t.mono(size * 0.6, color: t.dim)),
      ],
    );
  }
}
