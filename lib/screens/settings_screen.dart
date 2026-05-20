// Settings — placeholder for Task #6. Task #9 fills in the real toggles
// (theme follow-system, sound/haptics, search style, replays, privacy
// link) matching legacy SettingsView.swift.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/lta_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final keyConfigured = LtaConfig.accountKey.isNotEmpty;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(title: 'About'),
          ListTile(
            tileColor: t.surface,
            leading: Icon(Icons.info_outline, color: t.dim),
            title: const Text('Leyne'),
            subtitle: Text('Live Singapore bus arrivals',
                style: TextStyle(color: t.dim)),
          ),
          ListTile(
            tileColor: t.surface,
            leading: Icon(
              keyConfigured ? Icons.check_circle_outline : Icons.error_outline,
              color: keyConfigured ? t.live : t.crit,
            ),
            title: const Text('LTA DataMall key'),
            subtitle: Text(
              keyConfigured
                  ? 'Configured via --dart-define'
                  : 'Not set — pass --dart-define=LTA_API_KEY=… to flutter run/build',
              style: TextStyle(color: t.dim),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Toggles for theme, sound/haptics, search style, and onboarding replay land in Task #9.',
              style: t.sans(13).copyWith(color: t.dim),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: t.mono(11, weight: FontWeight.w600).copyWith(color: t.dim),
      ),
    );
  }
}
