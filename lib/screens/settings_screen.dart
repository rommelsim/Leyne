// Settings tab — About card with the live app version.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _sectionHeader(t, 'ABOUT'),
          _card(t, [
            _staticRow(
              t,
              leading: Icons.info_outline,
              label: 'Leyne',
              trailing: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (_, snap) {
                  final info = snap.data;
                  final label = info == null
                      ? '…'
                      : 'v${info.version} (${info.buildNumber}) · beta';
                  return Text(label,
                      style: t.mono(13).copyWith(color: t.dim));
                },
              ),
            ),
          ]),
        ],
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
