// SoftAlertsScreen — Leyne 2.0 Alerts tab (Material 3 Android variant).
//
// Mirrors ios-native/Leyne/V2/SoftAlertsView.swift in behaviour; design
// follows Material 3 idioms (NOT iOS-26 Liquid Glass).
//
// Three sections:
//   1. Service status — live train disruptions from DataStore.trainAlerts
//      and lift maintenance from DataStore.liftMaintenance, each with a
//      calm "all clear" empty state.
//   2. Your alerts   — a tappable row to ManageAlertsScreen (personal bus
//      arrival alerts), showing how many are set.
//   3. A gear button in the page header opens SoftSettingsScreen as a
//      modal bottom sheet (Settings is no longer a tab).
//
// Pull-to-refresh triggers stale-check refreshes on both feeds. The screen
// also calls refreshIfStale on first render (onAppear parity).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'manage_alerts_screen.dart';
import 'soft_settings_screen.dart';

class SoftAlertsScreen extends StatefulWidget {
  const SoftAlertsScreen({
    super.key,
    required this.onTab,
    required this.alertBadgeCount,
    required this.onAlertsDataChanged,
  });

  final ValueChanged<SoftTab> onTab;

  /// Current unseen-alert count — forwarded to [SoftBottomBar] so the badge
  /// is visible on the tab bar while this screen is active.
  final int alertBadgeCount;

  /// Called by SoftRoot whenever alert data changes while this tab is open,
  /// so new data is immediately marked as seen. The screen itself also calls
  /// it on first render and after a manual refresh.
  final VoidCallback onAlertsDataChanged;

  @override
  State<SoftAlertsScreen> createState() => _SoftAlertsScreenState();
}

class _SoftAlertsScreenState extends State<SoftAlertsScreen> {
  @override
  void initState() {
    super.initState();
    // Mirror SoftAlertsView.onAppear: refresh when the tab first mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DataStore.shared.refreshTrainAlertsIfStale(force: false);
      DataStore.shared.refreshLiftMaintenanceIfStale(force: false);
      widget.onAlertsDataChanged();
    });
  }

  Future<void> _onRefresh() async {
    DataStore.shared.refreshTrainAlertsIfStale(force: true);
    DataStore.shared.refreshLiftMaintenanceIfStale(force: true);
    widget.onAlertsDataChanged();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.t.bg,
      // A drag handle + safe area give an always-available dismiss affordance.
      // Without these (and with the full-height settings content capturing
      // vertical drags) there was no obvious way to close the sheet, which read
      // as the app being locked. SoftSettingsScreen also renders an explicit
      // close button in asSheet mode. Cap the height so a sliver of tappable
      // scrim remains above the sheet too.
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LyneRadius.lg)),
      ),
      builder: (_) => SoftSettingsScreen(onTab: widget.onTab, asSheet: true),
    );
  }

  void _openManageAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManageAlertsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.alerts,
        onSelect: widget.onTab,
        alertBadgeCount: widget.alertBadgeCount,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
          builder: (context, _) {
            final trainAlerts = DataStore.shared.trainAlerts;
            final liftItems = DataStore.shared.liftMaintenance;
            final busAlertsCount = AppModel.shared.alerts.length;

            return RefreshIndicator(
              color: t.accent,
              onRefresh: _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _header(context),
                  const SizedBox(height: 20),
                  _advisoriesSection(context, trainAlerts),
                  const SizedBox(height: 20),
                  _liftSection(context, liftItems),
                  const SizedBox(height: 20),
                  _yourAlertsSection(context, busAlertsCount),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alerts',
                style: t.sans(28, weight: FontWeight.w700, color: t.fg),
              ),
              const SizedBox(height: 2),
              Text(
                'Service status & your notifications',
                style: t.sans(13, color: t.dim),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Gear → Settings sheet (mirrors iOS SoftAlertsView gear button).
        Semantics(
          button: true,
          label: 'Settings',
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: _openSettings,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface,
                shape: BoxShape.circle,
                border: Border.all(color: t.line, width: 1),
              ),
              child: Icon(Icons.settings_rounded, size: 20, color: t.fg),
            ),
          ),
        ),
      ],
    );
  }

  // ── Service status (train disruptions) ─────────────────────────────────────

  Widget _advisoriesSection(
      BuildContext context, List<TrainAlert> alerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(context, 'Service status'),
        const SizedBox(height: 10),
        if (alerts.isEmpty)
          _calmCard(
            context,
            title: 'All lines running normally',
            body: 'No disruptions or advisories right now.',
          )
        else
          ...alerts.map((a) => _advisoryCard(context, a)),
      ],
    );
  }

  Widget _advisoryCard(BuildContext context, TrainAlert alert) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vertical MRT line bar — same component used in Home + MRT.
                  if (alert.line != null) ...[
                    MRTLineBar(color: alert.line!.color),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: LyneSeverity.warning.color,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                alert.title,
                                style: t.sans(
                                  14,
                                  weight: FontWeight.w600,
                                  color: t.fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.detail,
                          style: t.sans(13, color: t.dim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Free bus / shuttle chips
              if (alert.freeBus || alert.freeShuttle) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    if (alert.freeBus)
                      _freeChip(context,
                          icon: Icons.directions_bus_rounded,
                          label: 'Free bus rides'),
                    if (alert.freeShuttle)
                      _freeChip(context,
                          icon: Icons.train_rounded,
                          label: 'Free MRT shuttle'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Lift maintenance ────────────────────────────────────────────────────────

  Widget _liftSection(
      BuildContext context, List<LiftMaintenance> items) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(context, 'Lift maintenance'),
        const SizedBox(height: 10),
        if (items.isEmpty)
          _calmCard(
            context,
            title: 'No maintenance underway',
            body: 'All network lifts are operating normally.',
          )
        else
          Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(LyneRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _liftRow(context, items[i]),
                  if (i < items.length - 1)
                    Divider(
                      color: t.line,
                      height: 1,
                      indent: 40,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _liftRow(BuildContext context, LiftMaintenance item) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.construction_rounded,
              size: 14,
              color: LyneSeverity.warning.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.stationName,
                  style: t.sans(13, weight: FontWeight.w600, color: t.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: t.sans(12, color: t.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Your alerts (personal bus notifications) ────────────────────────────────

  Widget _yourAlertsSection(BuildContext context, int busAlertsCount) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(context, 'Your alerts'),
        const SizedBox(height: 10),
        Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openManageAlerts,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  // Icon chip — 32×32 rounded tile, matches SoftSettingsScreen.
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.surfaceHi,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.notifications_rounded,
                      size: 16,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bus arrival alerts',
                          style: t.sans(15,
                              weight: FontWeight.w500, color: t.fg),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          busAlertsCount == 0
                              ? 'None set yet'
                              : '$busAlertsCount set',
                          style: t.sans(12, color: t.dim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: t.faint, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared primitives ───────────────────────────────────────────────────────

  /// Calm "all clear" card. Green check icon + title + body — shown when
  /// a section has no items. Mirrors iOS SoftAlertsView.calmCard.
  Widget _calmCard(BuildContext context,
      {required String title, required String body}) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 22,
              color: LyneSeverity.normal.color.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: t.sans(13, color: t.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small pill chip for free-bus / free-shuttle indicators on alert cards.
  /// Mirrors iOS SoftAlertsView.freeChip.
  Widget _freeChip(BuildContext context,
      {required IconData icon, required String label}) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: t.dim),
          const SizedBox(width: 4),
          Text(label, style: t.sans(11, color: t.fg)),
        ],
      ),
    );
  }

  /// Section label eyebrow — monospace, uppercase, letter-spaced.
  /// Mirrors iOS SoftAlertsView.eyebrow.
  Widget _eyebrow(BuildContext context, String label) {
    final t = context.t;
    return Text(
      label.toUpperCase(),
      style: t.mono(
        10,
        weight: FontWeight.w600,
        color: t.dim,
      ),
    );
  }
}
