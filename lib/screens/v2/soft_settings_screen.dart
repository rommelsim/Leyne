// SoftSettingsScreen — Leyne 2.0 Settings (Material 3 Android variant).
// Restyled for the 2.4.0 design language: grouped Material cards, icon chips,
// chevron-trailing nav rows, SoftToggle for binary settings.
// Settings: manage alerts, appearance, 24h time, haptics, search radius,
// about. Notification permission is requested once at onboarding (no in-app
// on/off toggle); the app ships English-only (no language picker).

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import '../about_screen.dart';
import 'manage_alerts_screen.dart';

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

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light  => 'Light',
    ThemeMode.dark   => 'Dark',
  };

  String _radiusLabel(int metres) {
    if (metres < 1000) return '$metres m';
    final km = metres / 1000;
    if (metres % 1000 == 0) return '${km.toInt()} km';
    return '${km.toStringAsFixed(1)} km';
  }

  // ── Sheets ───────────────────────────────────────────────────────────────

  void _showAppearanceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LyneRadius.lg)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: AppModel.shared,
        builder: (ctx, _) {
          final t = ctx.t;
          const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.line,
                    borderRadius: BorderRadius.circular(LyneRadius.full),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Appearance',
                          style: t.sans(18, weight: FontWeight.w600, color: t.fg)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final mode in modes) ...[
                  InkWell(
                    onTap: () {
                      AppModel.shared.setThemeMode(mode);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_themeLabel(mode),
                                style: t.sans(15,
                                    weight: FontWeight.w500, color: t.fg)),
                          ),
                          if (AppModel.shared.themeMode == mode)
                            Icon(Icons.check, size: 18, color: t.fg),
                        ],
                      ),
                    ),
                  ),
                  if (mode != ThemeMode.dark)
                    Divider(color: t.line, height: 1, indent: 20),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRadiusSheet() {
    const radii = [250, 500, 1000, 2000];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LyneRadius.lg)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: AppModel.shared,
        builder: (ctx, _) {
          final t = ctx.t;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.line,
                    borderRadius: BorderRadius.circular(LyneRadius.full),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Search radius',
                          style: t.sans(18, weight: FontWeight.w600, color: t.fg)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'When you search a 6-digit postal code, bus stops within this '
                    'distance of that address are shown.',
                    style: t.sans(12, color: t.dim),
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in radii) ...[
                  InkWell(
                    onTap: () {
                      AppModel.shared.setSearchRadiusM(r);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_radiusLabel(r),
                                style: t.sans(15,
                                    weight: FontWeight.w500, color: t.fg)),
                          ),
                          if (AppModel.shared.searchRadiusM == r)
                            Icon(Icons.check, size: 18, color: t.fg),
                        ],
                      ),
                    ),
                  ),
                  if (r != radii.last)
                    Divider(color: t.line, height: 1, indent: 20),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.settings,
        onSelect: widget.onTab,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            final m = AppModel.shared;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // ── Large page title ──────────────────────────────────────
                Text(
                  'Settings',
                  style: t.sans(28, weight: FontWeight.w700, color: t.fg),
                ),
                const SizedBox(height: 20),

                // ── Section 1: Preferences ────────────────────────────────
                _sectionLabel(context, 'Preferences'),
                const SizedBox(height: 8),
                _card(context, [
                  // Manage alerts → central alerts list. Notification
                  // permission itself is requested once at onboarding, so
                  // there is no separate in-app on/off toggle here.
                  _navRow(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Manage alerts',
                    detail: m.alerts.isEmpty ? null : '${m.alerts.length}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ManageAlertsScreen(),
                      ),
                    ),
                  ),
                  _divider(context),
                  // Appearance → sheet picker
                  _navRow(
                    context,
                    icon: Icons.dark_mode_outlined,
                    title: 'Appearance',
                    detail: _themeLabel(m.themeMode),
                    onTap: _showAppearanceSheet,
                  ),
                  _divider(context),
                  // About → AboutScreen
                  _navRow(
                    context,
                    icon: Icons.info_outline,
                    title: 'About',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AboutScreen(),
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 24),

                // ── Section 2: Time & Feedback ────────────────────────────
                _sectionLabel(context, 'Time & Feedback'),
                const SizedBox(height: 8),
                _card(context, [
                  _toggleRow(
                    context,
                    icon: Icons.access_time,
                    title: '24-hour time',
                    value: m.use24h,
                    onChanged: m.setUse24h,
                  ),
                  _divider(context),
                  _toggleRow(
                    context,
                    icon: Icons.vibration,
                    title: 'Haptics',
                    value: m.hapticsEnabled,
                    onChanged: m.setHaptics,
                  ),
                  _divider(context),
                  // Search radius → sheet picker
                  _navRow(
                    context,
                    icon: Icons.radar,
                    title: 'Search radius',
                    detail: _radiusLabel(m.searchRadiusM),
                    onTap: _showRadiusSheet,
                  ),
                ]),

                const SizedBox(height: 24),

                // ── Footer ────────────────────────────────────────────────
                Text(
                  'Leyne v$_version · Data from LTA DataMall.',
                  style: t.mono(10, color: t.faint),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Primitives ────────────────────────────────────────────────────────────

  Widget _sectionLabel(BuildContext context, String title) {
    final t = context.t;
    return Text(
      title,
      style: t.sans(13, weight: FontWeight.w600, color: t.dim),
    );
  }

  /// Rounded Material card that clips InkWell ripples to its corners.
  Widget _card(BuildContext context, List<Widget> children) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// Tappable nav row: icon chip + title + optional trailing value + chevron.
  Widget _navRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? detail,
    required VoidCallback onTap,
  }) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _iconChip(context, icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: t.sans(15, weight: FontWeight.w500, color: t.fg),
              ),
            ),
            if (detail != null) ...[
              Text(detail, style: t.sans(13, color: t.dim)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right, color: t.faint, size: 18),
          ],
        ),
      ),
    );
  }

  /// Toggle row: icon chip + title + SoftToggle (no chevron).
  Widget _toggleRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _iconChip(context, icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: t.sans(15, weight: FontWeight.w500, color: t.fg),
            ),
          ),
          SoftToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 32×32 rounded tile with a centred icon — matches iOS iconChip.
  Widget _iconChip(BuildContext context, IconData icon) {
    final t = context.t;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: t.fg),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(color: context.t.line, height: 1, indent: 58);
}
