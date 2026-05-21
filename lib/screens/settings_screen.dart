// Settings — Personalize controls (notifications, appearance, language,
// 24-hour time) plus a tappable About card.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
import 'about_screen.dart';
import 'notifications_screen.dart';

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
            final m = AppModel.shared;
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
                      _navRow(t,
                          icon: Icons.notifications_none,
                          title: 'Notifications',
                          value: m.notificationsEnabled
                              ? 'Arrival alerts on'
                              : 'Off',
                          onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsScreen(),
                                ),
                              )),
                      _navRow(t,
                          icon: Icons.dark_mode_outlined,
                          title: 'Appearance',
                          value: _themeLabel(m.themeMode),
                          onTap: () => _showAppearanceSheet(context, m)),
                      _navRow(t,
                          icon: Icons.language,
                          title: 'Language',
                          value: AppLocalizations.labelFor(
                              m.locale?.languageCode ?? 'en'),
                          onTap: () => _showLanguageSheet(context, m)),
                      _toggleRow(
                        t,
                        icon: Icons.schedule,
                        title: '24-hour time',
                        value: m.use24h ? 'On' : 'Off',
                        on: m.use24h,
                        onChanged: m.setUse24h,
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

  Widget _navRow(LyneTheme t,
      {required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
      bool isLast = false}) {
    return InkWell(
      onTap: onTap,
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
        trailing: LyneToggle(on: on, onChanged: onChanged),
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
        border: isLast ? null : Border(bottom: BorderSide(color: t.line)),
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

  // ─── Pickers ────────────────────────────────────────────────

  String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  Future<void> _showAppearanceSheet(BuildContext context, AppModel m) {
    return _showOptionSheet(
      context,
      title: 'Appearance',
      options: [
        for (final mode in ThemeMode.values)
          _Option(
            selected: m.themeMode == mode,
            label: _themeLabel(mode),
            sub: mode == ThemeMode.system ? 'Follow the device setting' : null,
            onPick: () => m.setThemeMode(mode),
          ),
      ],
    );
  }

  Future<void> _showLanguageSheet(BuildContext context, AppModel m) {
    final current = m.locale?.languageCode ?? 'en';
    return _showOptionSheet(
      context,
      title: 'Language',
      footnote: 'App text is in English today — more languages are rolling '
          'out. Your choice still localises dates, pickers and system text.',
      options: [
        for (final code in const ['en', 'zh', 'ms', 'ta'])
          _Option(
            selected: current == code,
            label: AppLocalizations.labelFor(code),
            onPick: () =>
                m.setLocale(code == 'en' ? null : Locale(code)),
          ),
      ],
    );
  }

  Future<void> _showOptionSheet(
    BuildContext context, {
    required String title,
    required List<_Option> options,
    String? footnote,
  }) {
    final t = context.t;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(title,
                      style: t.sans(15, weight: FontWeight.w600)),
                ),
                for (final o in options)
                  InkWell(
                    onTap: () {
                      o.onPick();
                      Navigator.of(sheetContext).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(o.label,
                                    style: t.sans(15,
                                        weight: o.selected
                                            ? FontWeight.w600
                                            : FontWeight.w400)),
                                if (o.sub != null) ...[
                                  const SizedBox(height: 2),
                                  Text(o.sub!,
                                      style: t.mono(11, color: t.dim)),
                                ],
                              ],
                            ),
                          ),
                          if (o.selected)
                            Icon(Icons.check_rounded,
                                size: 20, color: t.accent),
                        ],
                      ),
                    ),
                  ),
                if (footnote != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: Text(footnote,
                        style: t.mono(11, color: t.faint)
                            .copyWith(height: 1.5, letterSpacing: 0.3)),
                  ),
              ],
            ),
          ),
        );
      },
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.line),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                                  style:
                                      t.sans(15, weight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(v,
                                  style: t.mono(11, color: t.dim)
                                      .copyWith(letterSpacing: 0.4)),
                            ],
                          );
                        },
                      ),
                    ),
                    Text("What's new",
                        style: t.sans(12, color: t.accent)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: t.faint),
                  ],
                ),
              ),
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
        ],
      ),
    );
  }

  Widget _appBadge(LyneTheme t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/app_icon.png',
        width: 44,
        height: 44,
        cacheWidth: 132,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _Option {
  _Option({
    required this.selected,
    required this.label,
    required this.onPick,
    this.sub,
  });
  final bool selected;
  final String label;
  final String? sub;
  final VoidCallback onPick;
}
