// HiddenStopsScreen — manages the stops a user has hidden from Nearby (via the
// long-press "Hide from Nearby" action). Swipe a row to bring a stop back.
// Reached from Settings → Hidden stops, which only surfaces while something is
// hidden. Material counterpart to iOS HiddenStopsView.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../state/app_model.dart';
import '../../theme.dart';

class HiddenStopsScreen extends StatelessWidget {
  const HiddenStopsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) {
            // Name-sorted for a stable order, mirroring iOS.
            final codes = AppModel.shared.hiddenNearby.toList()
              ..sort((a, b) =>
                  DataStore.shared.stopName(a).compareTo(DataStore.shared.stopName(b)));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _header(context, t),
                const SizedBox(height: 20),
                if (codes.isEmpty)
                  _emptyState(context, t)
                else ...[
                  _card(context, t, codes),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      "Hidden stops won't show in Nearby. Swipe a stop to bring "
                      'it back.',
                      style: t.sans(12, color: t.faint),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header: back + title ───────────────────────────────────────────────
  Widget _header(BuildContext context, LyneTheme t) {
    return Row(
      children: [
        Semantics(
          label: 'Back',
          button: true,
          child: Material(
            color: t.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_back, size: 20, color: t.fg),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Hidden stops',
            style: t.sans(24, weight: FontWeight.w700, color: t.fg),
          ),
        ),
      ],
    );
  }

  // ── Grouped card of hidden rows ────────────────────────────────────────
  Widget _card(BuildContext context, LyneTheme t, List<String> codes) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LyneRadius.lg),
          border: Border.all(color: t.line, width: 1),
        ),
        child: Column(
          children: [
            for (var i = 0; i < codes.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
              _row(context, t, codes[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, LyneTheme t, String code) {
    final name = DataStore.shared.stopName(code);
    final road = DataStore.shared.roadName(code);
    final title = name.isEmpty ? code : name;
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';

    // Swipe-to-unhide — restorative, so a green (t.soon) background + "Unhide".
    return Dismissible(
      key: ValueKey('hidden-$code'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => AppModel.shared.unhideNearby(code),
      background: Container(
        color: t.soon,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 18, color: t.contrastFg),
            const SizedBox(width: 6),
            Text('Unhide',
                style: t.sans(13, weight: FontWeight.w700, color: t.contrastFg)),
          ],
        ),
      ),
      child: Container(
        color: t.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surfaceHi,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.location_off_outlined, size: 17, color: t.dim),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.mono(12, color: t.dim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Explicit unhide button too — discoverable without the swipe.
            TextButton(
              onPressed: () => AppModel.shared.unhideNearby(code),
              child: Text('Unhide',
                  style: t.sans(14, weight: FontWeight.w600, color: t.accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, LyneTheme t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        children: [
          Icon(Icons.visibility_outlined, size: 30, color: t.dim),
          const SizedBox(height: 12),
          Text('Nothing hidden',
              style: t.sans(17, weight: FontWeight.w600, color: t.fg)),
          const SizedBox(height: 4),
          Text(
            'Stops you hide from Nearby will show up here.',
            textAlign: TextAlign.center,
            style: t.sans(13, color: t.dim),
          ),
        ],
      ),
    );
  }
}
