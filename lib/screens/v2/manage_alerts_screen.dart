// ManageAlertsScreen — the central "Manage alerts" list (Material 3).
//
// Two sections, mirroring the mockup:
//   • ACTIVE ALERTS — alerts whose bus currently has a live arrival in the
//     arrivals store (the notification is imminent / armed off live data).
//   • OTHER ALERTS  — everything else (armed, just not currently live).
//
// Every row carries a Switch that pauses/resumes the alert in place — it
// never deletes (mirrors iOS WSAlertsView / AppModel.setAlertEnabled, owner
// decision 2026-07-02). A paused row dims to 55% and swaps its subtitle for
// "Paused — flip on to resume".
//
// Edit mode reveals a delete affordance per row and switches each section to
// a drag-to-reorder ReorderableListView (mirrors SoftFavouritesScreen's
// pins/services/stations sections); swipe-to-delete works in the normal
// (non-edit) list. Reachable from the confirmation sheet and from Settings.

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../data/data_store.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';

class ManageAlertsScreen extends StatefulWidget {
  const ManageAlertsScreen({super.key});

  @override
  State<ManageAlertsScreen> createState() => _ManageAlertsScreenState();
}

class _ManageAlertsScreenState extends State<ManageAlertsScreen> {
  bool _editing = false;

  /// Whether the alert's bus has a live arrival at the relevant stop right now.
  bool _isLive(BusAlert a) {
    final state = DataStore.shared.arrivals[a.boardStopCode];
    if (state == null || state.kind != ArrivalStateKind.loaded) return false;
    return state.services.any((s) => s.no == a.busNo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) {
            final alerts = AppModel.shared.alerts;
            final active = alerts.where(_isLive).toList();
            final other = alerts.where((a) => !_isLive(a)).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _header(context, t),
                const SizedBox(height: 20),
                if (alerts.isEmpty)
                  _emptyState(context, t)
                else ...[
                  if (active.isNotEmpty) ...[
                    _sectionLabel(context, t, 'ACTIVE ALERTS'),
                    const SizedBox(height: 8),
                    _alertSection(context, t, active),
                    const SizedBox(height: 24),
                  ],
                  if (other.isNotEmpty) ...[
                    _sectionLabel(context, t, 'OTHER ALERTS'),
                    const SizedBox(height: 8),
                    _alertSection(context, t, other),
                    const SizedBox(height: 24),
                  ],
                  _footerHint(context, t),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header: back + title + Edit toggle ─────────────────────────────────
  Widget _header(BuildContext context, LyneTheme t) {
    return Row(
      children: [
        Semantics(
          label: 'Back',
          button: true,
          child: Material(
            color: t.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Manage alerts',
            style: t.sans(24, weight: FontWeight.w700, color: t.fg),
          ),
        ),
        if (AppModel.shared.alerts.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _editing = !_editing),
            child: Text(
              _editing ? 'Done' : 'Edit',
              style: t.sans(
                15,
                weight: FontWeight.w600,
                color: t.accent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, LyneTheme t, String text) {
    return Text(
      text,
      style: t
          .mono(11, weight: FontWeight.w600, color: t.dim)
          .copyWith(letterSpacing: 1),
    );
  }

  // ── Section of alert rows ────────────────────────────────────────────────
  // Normal mode: a static list of standalone cards, each swipeable to delete.
  // Edit mode: the same cards inside a ReorderableListView with an explicit
  // drag handle (mirrors SoftFavouritesScreen's pins/services/stations
  // sections) plus a delete button — swipe is disabled here so the drag
  // gesture doesn't fight it.
  Widget _alertSection(BuildContext context, LyneTheme t, List<BusAlert> alerts) {
    if (_editing) {
      return ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Rows carry a Switch and a delete button, both tappable — restrict
        // drag activation to the explicit handle instead of "long-press
        // anywhere" so it can't steal those gestures.
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
              key: ValueKey('reorder-alert-${a.id}'),
              padding: EdgeInsets.only(bottom: a == alerts.last ? 0 : 10),
              child: Row(
                children: [
                  Expanded(child: _alertCard(context, t, a)),
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

    return Column(
      children: [
        for (var i = 0; i < alerts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _alertRow(context, t, alerts[i]),
        ],
      ],
    );
  }

  // Swipe-to-delete wrapper used outside edit mode.
  Widget _alertRow(BuildContext context, LyneTheme t, BusAlert a) {
    return Dismissible(
      key: ValueKey('alert-${a.id}'),
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
      child: _alertCard(context, t, a),
    );
  }

  // Shared row visuals — a standalone card used both in the static list and
  // as a reorderable drag item. Toggle pauses in place; edit mode adds the
  // delete affordance. Paused alerts dim their icon/text (not the toggle).
  Widget _alertCard(BuildContext context, LyneTheme t, BusAlert a) {
    final isDest = a.kind == AlertKind.destination;
    final title = isDest
        ? (a.dest.isNotEmpty ? a.dest : a.stopName)
        : a.stopName;
    // Arrival alerts fire at fixed dual leads; destination keeps its lead copy.
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LyneRadius.lg),
          border: Border.all(color: t.line, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: a.enabled ? 1 : 0.55,
                child: Row(
                  children: [
                    // Leading icon.
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
            if (_editing)
              IconButton(
                tooltip: 'Delete alert',
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 22,
                  color: t.crit,
                ),
                onPressed: () => AppModel.shared.removeAlert(a.id),
              ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────
  Widget _emptyState(BuildContext context, LyneTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        children: [
          Icon(Icons.notifications_off_outlined, size: 40, color: t.dim),
          const SizedBox(height: 12),
          Text(
            'No alerts yet',
            style: t.sans(16, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 6),
          Text(
            'Set an alert from a bus or stop to be notified before it '
            'reaches you.',
            textAlign: TextAlign.center,
            style: t.sans(13, color: t.dim),
          ),
        ],
      ),
    );
  }

  Widget _footerHint(BuildContext context, LyneTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline_rounded, size: 12, color: t.faint),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'You can turn off or edit alerts anytime.',
            style: t.sans(12, color: t.faint),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
