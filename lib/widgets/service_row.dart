// One bus service inside a card — service no, destination, load badge,
// next ETA + the "after that" small ETA.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';
import 'eta_pill.dart';

class ServiceRow extends StatelessWidget {
  const ServiceRow({super.key, required this.service, this.onTap});
  final Service service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Service no — bold mono pill.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.line),
              ),
              child: Text(service.no,
                  style: t.mono(14, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.dest,
                    style: t.sans(13, weight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _LoadDot(load: service.load),
                      const SizedBox(width: 6),
                      Text(service.load.label,
                          style: t.mono(10).copyWith(color: t.dim)),
                      if (service.wab) ...[
                        const SizedBox(width: 8),
                        Text('WAB',
                            style: t.mono(9, weight: FontWeight.w600)
                                .copyWith(color: t.dim)),
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
                EtaPill(etaSec: service.etaSec),
                if (service.followingSec > service.etaSec + 30) ...[
                  const SizedBox(height: 2),
                  Text(
                    'then ${fmtEta(service.followingSec).big} ${fmtEta(service.followingSec).small}',
                    style: t.mono(10).copyWith(color: t.dim),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadDot extends StatelessWidget {
  const _LoadDot({required this.load});
  final Load load;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Color c;
    switch (load) {
      case Load.sea:
        c = t.live;
        break;
      case Load.sda:
        c = t.warn;
        break;
      case Load.lsd:
        c = t.crit;
        break;
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}
