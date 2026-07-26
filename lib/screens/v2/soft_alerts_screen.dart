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
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';
import '../../theme.dart';
import '../../theme/soft_blue.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_mrt_station_screen.dart';

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
                // Reordered (spec item 9, 2026-07-25): user alerts FIRST —
                // they're the thing YOU asked the app to watch — then
                // network disruptions, then lift outages. Previously service
                // status/lifts sat above "Your alerts", burying the
                // personal alerts the screen exists to manage.
                children: [
                  _header(context),
                  const SizedBox(height: 14),
                  _summaryCard(context, trainAlerts, liftItems),
                  const SizedBox(height: 20),
                  _yourAlertsSection(context, busAlerts),
                  const SizedBox(height: 20),
                  _advisoriesSection(context, trainAlerts),
                  const SizedBox(height: 20),
                  _liftSection(context, liftItems),
                  // One native ad per screen, after the live alert cards
                  // (iOS parity: WSAlertsView). Zero-size until a creative
                  // loads — padding applies only then.
                  const NativeAdCard(padding: EdgeInsets.only(top: 20)),
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
    // The static "Service status & your notifications" subtitle is gone
    // (spec item 9, 2026-07-25) — replaced by the status-first summary card
    // below, which actually says something ("4 alerts" said nothing, per
    // owner feedback mirrored from WSAlertsView's `summaryCard`).
    return Text(
      'Alerts',
      style: t.sans(28, weight: FontWeight.w700, color: t.fg),
    );
  }

  /// Status-first summary card (spec item 9): leads with the NETWORK state —
  /// normal service is the calm headline; disruptions take it over in amber
  /// — with lift outages as context on the sub-line (never counted as
  /// "alerts"). Mirrors iOS WSAlertsView's `summaryCard` exactly, replacing
  /// the old static subtitle.
  Widget _summaryCard(
    BuildContext context,
    List<TrainAlert> trainAlerts,
    List<LiftMaintenance> lifts,
  ) {
    final t = context.t;
    final disruptions = trainAlerts.length;
    final liftCount = lifts.length;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _PulseDot(
              color: disruptions > 0 ? t.warn : t.accent,
              size: 7,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    disruptions > 0
                        ? '$disruptions line ${disruptions == 1 ? 'disruption' : 'disruptions'}'
                        : 'All MRT lines running normally',
                    style: t.sans(
                      14.5,
                      weight: FontWeight.w600,
                      color: disruptions > 0 ? t.warn : t.fg,
                    ),
                  ),
                  if (liftCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$liftCount ${liftCount == 1 ? 'lift' : 'lifts'} out of service',
                      style: t.sans(12, color: t.dim),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
                        // Fixed double-title bug (spec item 9, 2026-07-25):
                        // this used to render `alert.title` here AND again
                        // inside the chip below. The line NAME is the
                        // correct headline (mirrors iOS's
                        // `Text(wsLineNames(from: [a.lineCode]))`) — the
                        // chip already carries the disruption title.
                        Text(
                          alert.line?.displayName ?? alert.lineCode,
                          style: t.sans(
                            14,
                            weight: FontWeight.w600,
                            color: t.fg,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SoftDisruptionChip(text: alert.title),
                        const SizedBox(height: 6),
                        Text(alert.detail, style: t.sans(13, color: t.dim)),
                      ],
                    ),
                  ),
                ],
              ),
              // Free bus / shuttle relief badges
              if (alert.freeBus || alert.freeShuttle) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    if (alert.freeBus) _freeBadge('FREE BUS'),
                    if (alert.freeShuttle) _freeBadge('FREE SHUTTLE'),
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
        // It's the OUTAGE that matters to a rider, not the activity that
        // caused it — same wording as WSAlertsView's `liftSection`.
        _eyebrow(context, 'Lifts out of service'),
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

  /// Resolves a lift's station name to the geo dataset, case-insensitively —
  /// mirrors iOS WSAlertsView's `liftRow` station lookup. Null when the name
  /// doesn't match (the row stays inert, matching iOS's `.disabled`).
  MrtGeoStation? _resolveLiftStation(LiftMaintenance item) {
    for (final s in MrtGeo.all) {
      if (s.name.toLowerCase() == item.stationName.toLowerCase()) return s;
    }
    return null;
  }

  /// Pill codes for a lift outage's station. The feed only names a LINE
  /// ("EWL"), which tells a rider nothing about where the lift is — so the
  /// station is resolved in MrtGeo and shows its own code(s) on that line
  /// (Clementi on the EWL → "EW23"), its first two codes when none match,
  /// and only the raw line code when the station doesn't resolve at all.
  /// Mirrors WSAlertsView's `stationCodes`.
  List<String> _liftStationCodes(LiftMaintenance item) {
    final station = _resolveLiftStation(item);
    if (station == null) return [item.line];
    final prefix = item.line.endsWith('L')
        ? item.line.substring(0, item.line.length - 1)
        : item.line;
    final onLine = station.codes.where((c) => c.startsWith(prefix)).toList();
    return onLine.isEmpty ? station.codes.take(2).toList() : onLine;
  }

  /// One lift-outage row: line pill for identity, tappable through to the
  /// station screen when the station resolves in MrtGeo (spec item 9 —
  /// previously inert and line-less). The redundant "Lift maintenance" chip
  /// is gone — the section header already says that; the chip repeated it
  /// on every row with no new information.
  Widget _liftRow(BuildContext context, LiftMaintenance item) {
    final t = context.t;
    final station = _resolveLiftStation(item);
    return Semantics(
      button: station != null,
      label: station == null
          ? '${item.stationName} lift maintenance'
          : 'Open ${item.stationName} MRT station, lift maintenance',
      child: InkWell(
        onTap: station == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SoftMrtStationScreen(
                    station: station,
                    onBack: () => Navigator.of(context).pop(),
                    onTab: widget.onTab,
                    tabSelection: SoftTab.alerts,
                    // No handler: a no-op callback made the station's bus
                    // rows LOOK tappable and do nothing. Left null, they
                    // degrade honestly to info-only.
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.warnBg,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.elevator_rounded,
                  size: 14,
                  color: t.warn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.stationName,
                            style: t.sans(
                              13,
                              weight: FontWeight.w600,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final code in _liftStationCodes(item)) ...[
                          const SizedBox(width: 6),
                          _linePill(code),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // LTA sends this ALL CAPS; wsFacilityText sentence-cases
                    // it so it reads like the rest of the app.
                    Text(
                      wsFacilityText(item.detail),
                      style: t.sans(12, color: t.dim),
                    ),
                  ],
                ),
              ),
              if (station != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: t.dim,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A small line-code roundel — white code on the line's brand colour.
  /// Mirrors WSAlertsView's `LineBullet(code:isLineCode:)`.
  Widget _linePill(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: lineColorFor(code),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
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
                Expanded(
                  child: _collapsible(a, _yourAlertCard(context, t, a)),
                ),
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

  /// Alerts currently collapsing out of the list. Tapping "Remove" mutates
  /// AppModel directly, so the card used to blink out of existence while a
  /// swipe got Dismissible's slide for free. The id parks here for one
  /// animation, the card shrinks and fades, and the model is mutated once
  /// it's gone (owner, 2026-07-26 — "no animation, they just disappear").
  final Set<String> _removing = {};
  static const _removeDuration = Duration(milliseconds: 260);

  void _removeAlert(String id) {
    if (_removing.contains(id)) return;
    setState(() => _removing.add(id));
    Future.delayed(_removeDuration, () {
      if (!mounted) {
        AppModel.shared.removeAlert(id);
        return;
      }
      AppModel.shared.removeAlert(id);
      setState(() => _removing.remove(id));
    });
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
      child: _collapsible(a, _yourAlertCard(context, t, a)),
    );
  }

  /// Height + opacity collapse for a card on its way out. Alignment is
  /// topCenter so the rows below rise into the gap rather than the card
  /// closing on itself from both edges.
  Widget _collapsible(BusAlert a, Widget child) {
    final going = _removing.contains(a.id);
    return AnimatedSize(
      duration: _removeDuration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: _removeDuration,
        curve: Curves.easeOut,
        opacity: going ? 0 : 1,
        child: going ? const SizedBox(width: double.infinity) : child,
      ),
    );
  }

  /// Shared row visuals for a bus alert — route badge + stop name + subtitle
  /// ("{stop} · {lead}", or "Paused — flip on to resume" at 55% opacity) and
  /// a trailing pause/resume + Remove column. Mirrors
  /// manage_alerts_screen.dart:227-350's _alertCard.
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
            // BOTH affordances, on every card, always — mirrors
            // WSAlertsView's `yourAlertCard` trailing column. Remove used to
            // hide behind Edit mode, which left swipe-to-delete as the only
            // discoverable way out of an alert; it's a text button under the
            // toggle now. Swipe and Edit-mode reordering both still work.
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Semantics(
                  label: a.enabled ? 'Pause alert' : 'Resume alert',
                  child: SoftToggle(
                    value: a.enabled,
                    onChanged: (v) => AppModel.shared.setAlertEnabled(a.id, v),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Remove alert',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _removeAlert(a.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Remove',
                        style: t.sans(
                          12,
                          weight: FontWeight.w600,
                          color: SoftBlue.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

  /// Uppercase amber badge for free-bus / free-shuttle relief on a disruption
  /// card. Mirrors WSAlertsView's `freeBadge`: it's a two-word fact riders
  /// scan for mid-disruption, so it reads as a badge in the disruption's own
  /// colour, not a neutral icon chip with a sentence in it.
  Widget _freeBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SoftBlue.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: SoftBlue.sans(
          9,
          weight: FontWeight.w700,
          color: SoftBlue.amber,
        ).copyWith(letterSpacing: 0.5),
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

/// Small breathing dot for the summary card — mirrors iOS's `SoftPulseDot`
/// (a 1s ease-in-out opacity pulse; there's no shared Android equivalent of
/// that primitive, so this is a local, minimal port).
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.size = 7});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.6 + 0.4 * _c.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
