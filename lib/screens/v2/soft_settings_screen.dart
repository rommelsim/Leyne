// SoftSettingsScreen — Leyne 2.0 Settings (Material 3 Android variant).
// Restyled for the 2.4.0 design language: grouped Material cards, icon chips,
// chevron-trailing nav rows, SoftToggle for binary settings.
// Settings: appearance, haptics, hidden stops, buy-me-a-coffee.
// The app uses a 12-hour clock (no time-format toggle). Notification
// permission is requested once at onboarding (no in-app on/off toggle);
// the app ships English-only (no language picker).

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'hidden_stops_screen.dart';

/// Where the "Buy me a coffee" row opens — the Stripe Payment Link for the
/// "Support Leyne" product (accepts PayNow + cards + Google Pay, settles SGD to
/// bank). Leyne is ad-funded, not paywalled; this is an optional way to chip in.
/// Shared with the iOS build (SoftSettingsView.swift `kCoffeeURL`).
const String _kCoffeeUrl = 'https://buy.stripe.com/6oU3cv5689oB3PI6R68so00';

class SoftSettingsScreen extends StatefulWidget {
  const SoftSettingsScreen({
    super.key,
    required this.onTab,
    /// When true the screen is presented inside a modal bottom sheet (from the
    /// Alerts tab gear button) — the bottom navigation bar is suppressed so it
    /// doesn't appear inside the sheet. Mirrors iOS SoftSettingsView which is
    /// always presented as a sheet since the Settings tab was removed.
    this.asSheet = false,
  });
  final ValueChanged<SoftTab> onTab;
  final bool asSheet;

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
                            Icon(Icons.check_rounded, size: 18, color: t.fg),
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      // Suppress the bottom nav bar when presented as a modal sheet (from the
      // Alerts tab gear). When used as the standalone Settings tab it still
      // renders. The `settings` tab enum value is kept for compatibility even
      // though the tab itself is no longer shown; once the old tab routing is
      // fully retired this can be cleaned up.
      bottomNavigationBar: widget.asSheet
          ? null
          : SoftBottomBar(
              selection: SoftTab.alerts,
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
                // ── Large page title (+ explicit close when shown as a sheet,
                //    so the user is never trapped without a dismiss control) ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Settings',
                        style: t.sans(28, weight: FontWeight.w700, color: t.fg),
                      ),
                    ),
                    if (widget.asSheet)
                      Semantics(
                        button: true,
                        label: 'Close',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.line, width: 1),
                            ),
                            child: Icon(Icons.close_rounded, size: 18, color: t.fg),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Section 1: Preferences ────────────────────────────────
                _sectionLabel(context, 'Preferences'),
                const SizedBox(height: 8),
                _card(context, [
                  // Appearance → sheet picker
                  _navRow(
                    context,
                    icon: Icons.dark_mode_outlined,
                    title: 'Appearance',
                    detail: _themeLabel(m.themeMode),
                    onTap: _showAppearanceSheet,
                  ),
                  // Hidden stops → HiddenStopsScreen. Only surfaces once the
                  // user has hidden something from Nearby (long-press → Hide
                  // from Nearby). Mirrors iOS SoftSettingsView.
                  if (m.hiddenNearby.isNotEmpty) ...[
                    _divider(context),
                    _navRow(
                      context,
                      icon: Icons.visibility_off_outlined,
                      title: 'Hidden stops',
                      detail: '${m.hiddenNearby.length}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HiddenStopsScreen(),
                        ),
                      ),
                    ),
                  ],
                  _divider(context),
                  // Buy me a coffee → opens the Stripe donation link in the
                  // browser. Optional supporter tier; the app is ad-funded, not
                  // paywalled. Mirrors iOS SoftSettingsView coffee row.
                  _coffeeRow(context),
                ]),

                const SizedBox(height: 24),

                // ── Section 2: Feedback ───────────────────────────────────
                _sectionLabel(context, 'Feedback'),
                const SizedBox(height: 8),
                _card(context, [
                  _toggleRow(
                    context,
                    icon: Icons.vibration,
                    title: 'Haptics',
                    value: m.hapticsEnabled,
                    onChanged: m.setHaptics,
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
            Icon(Icons.chevron_right_rounded, color: t.faint, size: 18),
          ],
        ),
      ),
    );
  }

  /// "Buy me a coffee" support row — icon chip, title + subtitle, and an
  /// external-link arrow (instead of a chevron) to signal it leaves the app.
  /// Mirrors iOS SoftSettingsView coffeeRow.
  Widget _coffeeRow(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: _openCoffee,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _iconChip(context, Icons.local_cafe_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Buy me a coffee',
                    style: t.sans(15, weight: FontWeight.w500, color: t.fg),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    "Support Leyne's development",
                    style: t.sans(12, color: t.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_east_rounded, color: t.faint, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openCoffee() async {
    final uri = Uri.parse(_kCoffeeUrl);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't open the donation page"),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
    // Fallback dismiss for devices with animations disabled (Flutter's built-in
    // SnackBar auto-hide timer doesn't fire then).
    Future.delayed(const Duration(seconds: 4), controller.close);
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
