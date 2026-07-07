// SoftAlertsScreen — Leyne 2.0 Alerts tab (Material 3 Android variant).
//
// Mirrors ios-native/Leyne/V2/SoftAlertsView.swift in behaviour; design
// follows Material 3 idioms (NOT iOS-26 Liquid Glass).
//
// Three sections:
//   1. Service status — live train disruptions from DataStore.trainAlerts
//      and lift maintenance from DataStore.liftMaintenance, each with a
//      calm "all clear" empty state.
//   2. Your alerts   — the user's personal bus arrival alerts INLINE (owner
//      decision, 2026-07-02 — mirrors WSAlertsView.swift:153-184, which
//      manages alerts directly on the Alerts tab rather than pushing to a
//      separate screen): pause/resume toggle, swipe-to-delete, and an Edit
//      affordance for drag-to-reorder. ManageAlertsScreen still exists —
//      it's reachable from the Bus view (soft_bus_screen.dart) — this
//      screen just no longer routes to it.
//
// Owner decision, 2026-07-03 (punch list Section E, item 9): the header gear
// that opened SoftSettingsScreen as a modal sheet is REMOVED — WSAlertsView
// has no settings entry at all, and Android shouldn't invent one iOS lacks.
// SoftSettingsScreen itself and its routes are untouched; this was the ONLY
// call site that presented it (grep verified), so Settings — Appearance,
// Hidden stops, Buy-me-a-coffee, Haptics — is currently unreachable in the
// Android app until a new entry point is chosen. Flagged to the owner.
//
// Pull-to-refresh triggers stale-check refreshes on both feeds. The screen
// also calls refreshIfStale on first render (onAppear parity).

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../data/data_store.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';
import '../../theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

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
  /// Edit affordance for "Your alerts" — reveals drag handles for
  /// reordering. Swipe-to-delete works in both modes.
  bool _editingAlerts = false;

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
            final busAlerts = AppModel.shared.alerts;

            // Auto-exit edit mode when the list becomes empty (mirrors
            // SoftFavouritesScreen).
            if (_editingAlerts && busAlerts.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(() => _editingAlerts = false),
              );
            }

            return RefreshIndicator(
              color: t.accent,
              // Disable pull-to-refresh while editing — drag gestures conflict.
              onRefresh: _editingAlerts ? () async {} : _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _header(context),
                  const SizedBox(height: 20),
                  _advisoriesSection(context, trainAlerts),
                  const SizedBox(height: 20),
                  _liftSection(context, liftItems),
                  // One native ad per screen, between the system sections and
                  // the user's own alerts (iOS parity: WSAlertsView).
                  // Zero-size until a creative loads — padding applies only then.
                  const NativeAdCard(padding: EdgeInsets.only(top: 20)),
                  const SizedBox(height: 20),
                  _yourAlertsSection(context, busAlerts),
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
    // No trailing gear — WSAlertsView has no settings entry on this screen
    // either (owner decision 2026-07-03, punch list item 9).
    return Column(
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
    );
  }

  // ── Service status (train disruptions) ─────────────────────────────────────

  Widget _advisoriesSection(BuildContext context, List<TrainAlert> alerts) {
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
                        Text(alert.detail, style: t.sans(13, color: t.dim)),
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
                      _freeChip(
                        context,
                        icon: Icons.directions_bus_rounded,
                        label: 'Free bus rides',
                      ),
                    if (alert.freeShuttle)
                      _freeChip(
                        context,
                        icon: Icons.train_rounded,
                        label: 'Free MRT shuttle',
                      ),
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

  Widget _liftSection(BuildContext context, List<LiftMaintenance> items) {
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
                    Divider(color: t.line, height: 1, indent: 40),
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
                Text(item.detail, style: t.sans(12, color: t.dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Your alerts (personal bus notifications, managed inline) ────────────────
  // Owner decision 2026-07-02: manage bus alerts directly on this tab rather
  // than pushing to ManageAlertsScreen (mirrors WSAlertsView.swift:153-184).

  Widget _yourAlertsSection(BuildContext context, List<BusAlert> alerts) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _eyebrow(context, 'Your alerts')),
            if (alerts.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _editingAlerts = !_editingAlerts),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                  child: Text(
                    _editingAlerts ? 'DONE' : 'EDIT',
                    style: t
                        .mono(10, weight: FontWeight.w600, color: t.accent)
                        .copyWith(letterSpacing: 0.8),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (alerts.isEmpty)
          _calmCard(
            context,
            title: 'No bus alerts',
            body: 'Set one from any bus.',
          )
        else if (_editingAlerts)
          _yourAlertsReorderable(context, t, alerts)
        else
          Column(
            children: [
              for (var i = 0; i < alerts.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _yourAlertRow(context, t, alerts[i]),
              ],
            ],
          ),
      ],
    );
  }

  /// Edit-mode drag-to-reorder list. Restricts drag activation to an
  /// explicit handle (rather than long-press-anywhere) so it doesn't steal
  /// the row's own toggle gesture. Mirrors ManageAlertsScreen/
  /// SoftFavouritesScreen's reorderable sections and AppModel.reorderAlerts'
  /// contract (onReorderItem's newIndex is pre-adjusted — no extra offset).
  Widget _yourAlertsReorderable(
    BuildContext context,
    LyneTheme t,
    List<BusAlert> alerts,
  ) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 0, color: Colors.transparent, child: child),
      onReorderItem: (oldIndex, newIndex) {
        final reordered = [...alerts];
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        AppModel.shared.reorderAlerts(reordered.map((a) => a.id).toList());
      },
      children: [
        for (final a in alerts)
          Padding(
            key: ValueKey('reorder-your-alert-${a.id}'),
            padding: EdgeInsets.only(bottom: a == alerts.last ? 0 : 10),
            child: Row(
              children: [
                Expanded(child: _yourAlertCard(context, t, a)),
                ReorderableDragStartListener(
                  index: alerts.indexOf(a),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 22,
                      color: t.dim,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Swipe-to-delete wrapper used outside edit mode.
  Widget _yourAlertRow(BuildContext context, LyneTheme t, BusAlert a) {
    return Dismissible(
      key: ValueKey('your-alert-${a.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: t.critBg,
          borderRadius: BorderRadius.circular(LyneRadius.lg),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: t.crit),
      ),
      onDismissed: (_) => AppModel.shared.removeAlert(a.id),
      child: _yourAlertCard(context, t, a),
    );
  }

  /// Shared row visuals for a bus alert — route badge + stop name + subtitle
  /// ("{stop} · {lead}", or "Paused — flip on to resume" at 55% opacity) and
  /// a pause/resume toggle. Mirrors manage_alerts_screen.dart:227-350's
  /// _alertCard.
  Widget _yourAlertCard(BuildContext context, LyneTheme t, BusAlert a) {
    final isDest = a.kind == AlertKind.destination;
    final title = isDest
        ? (a.dest.isNotEmpty ? a.dest : a.stopName)
        : a.stopName;
    final leadText = isDest
        ? AlertTiming.leadRowSubtitle(a.leadMinutes)
        : AlertTiming.arrivalRowSubtitle;
    final subtitle = a.enabled
        ? '${a.stopName} · $leadText'
        : 'Paused — flip on to resume';

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: a.enabled ? 1 : 0.55,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.soonBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isDest
                            ? Icons.flag_rounded
                            : Icons.notifications_active_rounded,
                        size: 20,
                        color: t.soon,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: t.liveBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  a.busNo,
                                  style: t.mono(
                                    11,
                                    weight: FontWeight.w700,
                                    color: t.fg,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  title,
                                  style: t.sans(
                                    15,
                                    weight: FontWeight.w600,
                                    color: t.fg,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: t.sans(12, color: t.dim),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: a.enabled ? 'Pause alert' : 'Resume alert',
              child: SoftToggle(
                value: a.enabled,
                onChanged: (v) => AppModel.shared.setAlertEnabled(a.id, v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared primitives ───────────────────────────────────────────────────────

  /// Calm "all clear" card — title + body, no icon. Shown when a section
  /// has no items. Mirrors iOS WSAlertsView.calmRow, which is plain dim
  /// text with no glyph at all.
  ///
  /// Owner decision 2026-07-03 (punch list item 8): this used to lead with
  /// a green check-circle icon (`LyneSeverity.normal.color`). Green is
  /// reserved for EWL line identity only and must never signal status, so
  /// the icon is dropped entirely rather than just recoloured — matching
  /// what iOS does in the same spot.
  Widget _calmCard(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
    );
  }

  /// Small pill chip for free-bus / free-shuttle indicators on alert cards.
  /// Mirrors iOS SoftAlertsView.freeChip.
  Widget _freeChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
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
      style: t.mono(10, weight: FontWeight.w600, color: t.dim),
    );
  }
}
