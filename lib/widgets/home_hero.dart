// The hero arrival card on Home — the single most-urgent pinned arrival
// promoted to a full-bleed card with leave-now math.
//
// "Most urgent" is the Service with the smallest (etaSec - walkSec) across
// all pinned stops; HomeScreen passes us the winning (card, service) pair.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';
import 'atoms.dart';

class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.card,
    required this.service,
    required this.onTap,
  });

  final CardModel card;
  final Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final etaMin = (service.etaSec / 60).floor();
    final followingMin = (service.followingSec / 60).floor();
    final walk = card.walkMin;

    // Leave-now math: if the bus will be here before you can walk there
    // (plus 1 min buffer), the answer is leave now. Otherwise leave in
    // (eta - walk) minutes.
    final leaveIn = etaMin - walk;
    final leaveLabel = leaveIn <= 1
        ? 'Leave now'
        : 'Leave in $leaveIn min';
    final walkLabel = walk > 0 ? '$walk min walk' : 'At the stop';

    final isArriving = etaMin <= 1;
    final etaColor = isArriving ? t.accent : t.accent;
    final etaBig = etaMin <= 0 ? 'Arr' : '$etaMin';
    final etaUnit = etaMin <= 0 ? 'now' : 'min';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.lineHi),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _leftBlock(t, leaveLabel, walkLabel)),
                  const SizedBox(width: 12),
                  _rightBlock(t, etaBig, etaUnit, etaColor, followingMin),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, thickness: 0.6),
              const SizedBox(height: 12),
              _bottomStrip(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leftBlock(LyneTheme t, String leaveLabel, String walkLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel('$leaveLabel · $walkLabel'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BusChip(no: service.no, size: ChipSize.lg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.dest,
                    style: t.sans(17, weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${card.label.toUpperCase()} · STOP ${card.stopCode}',
                    style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.6),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rightBlock(LyneTheme t, String big, String unit, Color color, int next) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              big,
              style: t.mono(big == 'Arr' ? 40 : 54, weight: FontWeight.w600, color: color)
                  .copyWith(letterSpacing: -1.2, height: 1.0),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: t.mono(14, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          next > 0 ? 'arriving · then $next' : 'arriving',
          style: t.mono(11, color: t.dim),
        ),
      ],
    );
  }

  Widget _bottomStrip(LyneTheme t) {
    final loadLabel = service.load.label.toUpperCase();
    final loadColor = switch (service.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };
    return Row(
      children: [
        Pill(loadLabel, color: loadColor),
        if (service.wab) ...[
          const SizedBox(width: 6),
          Pill('WHEELCHAIR', color: t.dim),
        ],
        const Spacer(),
        Text(
          service.deck.word.toUpperCase(),
          style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.6),
        ),
      ],
    );
  }
}
