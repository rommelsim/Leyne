// SoftSettingsScreen — Leyne 2.0 Settings (Material 3 Android variant).

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftSettingsScreen extends StatefulWidget {
  const SoftSettingsScreen({super.key, required this.onTab});
  final ValueChanged<SoftTab> onTab;

  @override
  State<SoftSettingsScreen> createState() => _SoftSettingsScreenState();
}

class _SoftSettingsScreenState extends State<SoftSettingsScreen> {
  String _version = '—';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar:
          SoftBottomBar(selection: SoftTab.settings, onSelect: widget.onTab),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Settings',
                  style: t.sans(28, weight: FontWeight.w400, color: t.fg)),
              const SizedBox(height: 16),
              _section(context, 'Routines', [
                _row(context,
                    icon: Icons.wb_sunny_outlined,
                    title: 'Morning commute',
                    detail: 'Not set',
                    onTap: () {}),
                _divider(context),
                _row(context,
                    icon: Icons.nightlight_outlined,
                    title: 'Evening commute',
                    detail: 'Not set',
                    onTap: () {}),
                _divider(context),
                _row(context,
                    icon: Icons.add,
                    title: 'Add a routine',
                    onTap: () {}),
              ]),
              const SizedBox(height: 16),
              _section(context, 'Personalize', [
                _row(context,
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    detail: AppModel.shared.notificationsEnabled ? 'On' : 'Off',
                    onTap: () {}),
                _divider(context),
                _appearanceRow(context),
                _divider(context),
                _row(context,
                    icon: Icons.language_outlined,
                    title: 'Language',
                    detail: 'Device',
                    onTap: () {}),
                _divider(context),
                _toggleRow(context,
                    icon: Icons.access_time,
                    title: '24-hour time',
                    value: AppModel.shared.use24h,
                    onChanged: (v) => AppModel.shared.setUse24h(v)),
              ]),
              const SizedBox(height: 24),
              Text('Leyne v$_version · beta · Data from LTA DataMall.',
                  style: t.mono(10, color: t.faint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: t.sans(13, weight: FontWeight.w600, color: t.dim)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              color: t.surface, borderRadius: BorderRadius.circular(22)),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _row(BuildContext context,
      {required IconData icon,
      required String title,
      String? detail,
      required VoidCallback onTap}) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.surfaceHi, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: t.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: t.sans(14, weight: FontWeight.w500, color: t.fg)),
          ),
          if (detail != null)
            Text(detail, style: t.sans(13, color: t.dim)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: t.faint, size: 18),
        ]),
      ),
    );
  }

  Widget _toggleRow(BuildContext context,
      {required IconData icon,
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: t.surfaceHi, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: t.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: t.sans(14, weight: FontWeight.w500, color: t.fg)),
        ),
        SoftToggle(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _appearanceRow(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: t.surfaceHi, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.brightness_4_outlined, size: 16, color: t.fg),
        ),
        const SizedBox(width: 12),
        Text('Appearance',
            style: t.sans(14, weight: FontWeight.w500, color: t.fg)),
        const Spacer(),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {AppModel.shared.themeMode},
          onSelectionChanged: (s) => AppModel.shared.setThemeMode(s.first),
          showSelectedIcon: false,
        ),
      ]),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(color: context.t.line, height: 1, indent: 58);
}
