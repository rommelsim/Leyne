// What's New — a once-per-release changelog screen.
//
// Shown by `_AppRoot` (main.dart) when a returning user opens a build whose
// version has a `kChangelog` entry they haven't seen yet. Dismissing it
// calls `onDismiss`, which records the version so it won't show again.

import 'package:flutter/material.dart';

import '../data/changelog.dart';
import '../theme.dart';
import '../widgets/atoms.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({
    super.key,
    required this.version,
    required this.entry,
    required this.onDismiss,
  });

  /// Marketing version this changelog is for (e.g. "2.0.0").
  final String version;
  final WhatsNewEntry entry;

  /// "Got it" — records the version as seen and drops back to the app.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
                children: [
                  MicroLabel('WHAT’S NEW · v$version'),
                  const SizedBox(height: 12),
                  Text(
                    entry.headline,
                    style: t.sans(28, weight: FontWeight.w600)
                        .copyWith(letterSpacing: -0.5, height: 1.15),
                  ),
                  const SizedBox(height: 30),
                  for (final item in entry.items) ...[
                    _item(t, item),
                    const SizedBox(height: 22),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: t.accent,
                    foregroundColor: t.contrastFg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onDismiss,
                  child: Text(
                    'Got it',
                    style: t.sans(15,
                        weight: FontWeight.w600, color: t.contrastFg),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(LyneTheme t, WhatsNewItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(item.icon, size: 20, color: t.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: t.sans(15, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(item.body,
                  style: t.sans(13, color: t.dim).copyWith(height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
