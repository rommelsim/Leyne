// Settings tab — real toggles wired to AppModel + LTA key status.
//
// Ports legacy SettingsView.swift: Feedback (Sound, Haptics), About.
// The legacy iOS app also followed the system theme (no in-app toggle);
// keeping that here.

import 'package:flutter/material.dart';

import '../data/lta_config.dart';
import '../state/app_model.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: AppModel.shared,
        builder: (context, _) {
          final m = AppModel.shared;
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _sectionHeader(t, 'FEEDBACK'),
              _card(t, [
                _toggleRow(
                  t,
                  label: 'Sound',
                  sub: 'Audio cues on arrival',
                  value: m.sound,
                  onChanged: (v) => m.sound = v,
                ),
                Divider(height: 1, color: t.line),
                _toggleRow(
                  t,
                  label: 'Haptics',
                  sub: 'Subtle buzz on tap and arrival',
                  value: m.haptic,
                  onChanged: (v) => m.haptic = v,
                ),
              ]),
              _sectionHeader(t, 'ABOUT'),
              _card(t, [
                _staticRow(
                  t,
                  leading: Icons.info_outline,
                  label: 'Leyne',
                  trailing: Text('v1.0 · beta',
                      style: t.mono(13).copyWith(color: t.dim)),
                ),
                Divider(height: 1, color: t.line),
                _staticRow(
                  t,
                  leading: LtaConfig.accountKey.isNotEmpty
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  leadingColor: LtaConfig.accountKey.isNotEmpty
                      ? t.live
                      : t.crit,
                  label: 'LTA DataMall key',
                  sub: LtaConfig.accountKey.isNotEmpty
                      ? 'Configured via --dart-define'
                      : 'Not set — pass --dart-define=LTA_API_KEY=…',
                ),
              ]),
              _sectionHeader(t, 'THEME'),
              _card(t, [
                _staticRow(
                  t,
                  leading: Icons.brightness_auto_outlined,
                  label: 'Follow system',
                  sub: 'Light / Dark switches with the OS',
                ),
              ]),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'LEYNE · BETA',
                  style: t.mono(11, weight: FontWeight.w600)
                      .copyWith(color: t.dim, letterSpacing: 1.2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(LyneTheme t, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label,
        style: t.mono(10, weight: FontWeight.w600)
            .copyWith(color: t.dim, letterSpacing: 1.2),
      ),
    );
  }

  Widget _card(LyneTheme t, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _toggleRow(
    LyneTheme t, {
    required String label,
    String? sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: t.sans(14, weight: FontWeight.w500)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: t.sans(11).copyWith(color: t.dim)),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: t.accent,
          ),
        ],
      ),
    );
  }

  Widget _staticRow(
    LyneTheme t, {
    required IconData leading,
    Color? leadingColor,
    required String label,
    String? sub,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(leading, color: leadingColor ?? t.dim, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: t.sans(14, weight: FontWeight.w500)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: t.sans(11).copyWith(color: t.dim)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
