// Settings — three sections of controls a transit user actually wants.
// Personalize (walking speed, alerts, appearance, language), Data
// (refresh, data-saver, 24h time), and About (version + credits).
//
// 24-hour time and Data-saver toggles persist via AppModel; the remaining
// rows are placeholders that flash a "coming soon" snackbar — full wiring
// is a follow-up.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(t),
                  _section(
                    t,
                    label: 'Personalize',
                    rows: [
                    _navRow(t, context,
                        icon: Icons.directions_walk,
                        title: 'Walking speed',
                        value: 'Average · 4.5 km/h'),
                    _navRow(t, context,
                        icon: Icons.notifications_none,
                        title: 'Notifications',
                        value: '2 alerts · ETA + delays'),
                    _navRow(t, context,
                        icon: Icons.dark_mode_outlined,
                        title: 'Appearance',
                        value: 'System · ${t.isDark ? "Dark" : "Light"}'),
                    _navRow(t, context,
                        icon: Icons.language,
                        title: 'Language',
                        value: 'English (SG)',
                        isLast: true),
                  ],
                ),
                _section(
                  t,
                  label: 'Data',
                  rows: [
                    _navRow(t, context,
                        icon: Icons.refresh,
                        title: 'Refresh interval',
                        value: '15s'),
                    _toggleRow(
                      t,
                      icon: Icons.wifi,
                      title: 'Data saver',
                      value: AppModel.shared.dataSaver ? 'On' : 'Off',
                      on: AppModel.shared.dataSaver,
                      onChanged: AppModel.shared.setDataSaver,
                    ),
                    _toggleRow(
                      t,
                      icon: Icons.schedule,
                      title: '24-hour time',
                      value: AppModel.shared.use24h ? 'On' : 'Off',
                      on: AppModel.shared.use24h,
                      onChanged: AppModel.shared.setUse24h,
                      isLast: true,
                    ),
                  ],
                ),
                  _aboutSection(t, context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────

  Widget _header(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text('Settings',
          style:
              t.sans(28, weight: FontWeight.w600).copyWith(letterSpacing: -0.4)),
    );
  }

  // ─── Section + rows ─────────────────────────────────────────

  Widget _section(LyneTheme t,
      {required String label, required List<Widget> rows}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: MicroLabel(label),
          ),
          Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(LyneTheme t, BuildContext context,
      {required IconData icon,
      required String title,
      required String value,
      bool isLast = false}) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title — coming soon',
                style: t.sans(13, color: t.fg)),
            backgroundColor: t.surfaceHi,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: _rowFrame(
        t,
        icon: icon,
        title: title,
        value: value,
        isLast: isLast,
        trailing: Icon(Icons.chevron_right, size: 16, color: t.faint),
      ),
    );
  }

  Widget _toggleRow(
    LyneTheme t, {
    required IconData icon,
    required String title,
    required String value,
    required bool on,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: () => onChanged(!on),
      child: _rowFrame(
        t,
        icon: icon,
        title: title,
        value: value,
        isLast: isLast,
        trailing: _Toggle(on: on, onChanged: onChanged),
      ),
    );
  }

  Widget _rowFrame(LyneTheme t,
      {required IconData icon,
      required String title,
      required String value,
      required bool isLast,
      required Widget trailing}) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.sans(14, weight: FontWeight.w500)),
                if (value.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(value,
                      style: t.mono(11, color: t.dim)
                          .copyWith(letterSpacing: 0.4)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  // ─── About ──────────────────────────────────────────────────

  Widget _aboutSection(LyneTheme t, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: MicroLabel('About'),
          ),
          Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                _appBadge(t),
                const SizedBox(width: 14),
                Expanded(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (_, snap) {
                      final info = snap.data;
                      final v = info == null
                          ? '…'
                          : 'v${info.version} (${info.buildNumber}) · beta';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Leyne',
                              style: t.sans(15, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(v,
                              style: t.mono(11, color: t.dim)
                                  .copyWith(letterSpacing: 0.4)),
                        ],
                      );
                    },
                  ),
                ),
                Text('Made in SG',
                    style: t.sans(12, color: t.dim)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
            child: Text(
              'Data from LTA DataMall.\nNot affiliated with any operator.',
              style: t.mono(11, color: t.faint)
                  .copyWith(height: 1.6, letterSpacing: 0.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => AppModel.shared.resetOnboarding(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Show onboarding again',
                  style: t.sans(13, weight: FontWeight.w500, color: t.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appBadge(LyneTheme t) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accent, t.accent.withValues(alpha: 0.55)],
        ),
      ),
      alignment: Alignment.center,
      child: Text('L',
          style:
              t.mono(22, weight: FontWeight.w700, color: t.contrastFg)),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40, height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: on
              ? t.accent
              : (t.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.12)
                  : t.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisAlignment:
              on ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: on ? t.contrastFg : t.contrast,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
