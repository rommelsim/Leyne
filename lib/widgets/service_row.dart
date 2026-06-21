// One bus service inside a card — BusChip + destination + load badge,
// next ETA + the "after that" small ETA.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';
import 'atoms.dart';

class ServiceRow extends StatelessWidget {
  const ServiceRow({super.key, required this.service, this.onTap});
  final Service service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final etaMin = (service.etaSec / 60).floor();
    final followingMin = (service.followingSec / 60).floor();
    final estimate = !service.monitored;
    final big = etaMin <= 0 ? 'Arr' : '$etaMin';
    final unit = etaMin <= 0 ? 'now' : 'min';
    final arriving = service.etaSec <= 60;
    final etaColor = arriving ? t.accent : t.fg;
    final loadColor = switch (service.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            BusChip(no: service.no, size: ChipSize.sm),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(service.dest,
                      style: t.sans(14, weight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: loadColor, shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(service.load.label.toLowerCase(),
                          style: t.mono(10, color: t.dim)),
                      if (service.wab) ...[
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(big,
                        style: t.mono(22, weight: FontWeight.w600, color: etaColor)),
                    const SizedBox(width: 3),
                    Text(unit, style: t.mono(11, color: t.dim)),
                  ],
                ),
                if (followingMin > etaMin + 1) ...[
                  const SizedBox(height: 2),
                  Text('then $followingMin',
                      style: t.mono(10, color: t.faint)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
