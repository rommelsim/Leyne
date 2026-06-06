// NotifyWhenSheet — the "Notify me when" modal bottom sheet (Material 3).
//
// One sheet, two kinds (mirrors the product mockup + AlertTiming.AlertKind):
//   • arrival     — opened from the Stop view for a chosen bus; lead options
//                   "When arriving / 2 / 5 / 10 / 15 min before", default 5.
//   • destination — opened from the Bus view for a chosen alight stop; adds a
//                   30-min option, default 10.
//
// Returns the chosen lead (minutes) + the delivery prefs on Done, or null on
// Cancel. Push delivery is implicit (the alert IS the push); the Live Activity
// (ongoing-tracker) toggle round-trips so the caller can start the tracker.
// The caller owns creating the BusAlert + showing the confirmation.

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../theme.dart';

/// Result of the "Notify me when" sheet: the chosen lead + delivery prefs.
typedef NotifyWhenResult = ({int lead, bool liveActivity});

/// Present the "Notify me when" sheet. Returns the chosen lead + delivery
/// prefs, or null if the user cancels.
Future<NotifyWhenResult?> showNotifyWhenSheet(
  BuildContext context, {
  required AlertKind kind,
  required String busNo,
  required String stopName,
  String dest = '',
}) {
  return showModalBottomSheet<NotifyWhenResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotifyWhenSheet(
      kind: kind,
      busNo: busNo,
      stopName: stopName,
      dest: dest,
    ),
  );
}

class _NotifyWhenSheet extends StatefulWidget {
  const _NotifyWhenSheet({
    required this.kind,
    required this.busNo,
    required this.stopName,
    required this.dest,
  });

  final AlertKind kind;
  final String busNo;
  final String stopName;
  final String dest;

  @override
  State<_NotifyWhenSheet> createState() => _NotifyWhenSheetState();
}

class _NotifyWhenSheetState extends State<_NotifyWhenSheet> {
  late int _lead = AlertTiming.defaultLead(widget.kind);
  bool _push = true;
  bool _liveActivity = true;

  /// Live Activity (ongoing tracker) only makes sense for an arrival alert —
  /// you follow the bus to YOUR stop. Hide the lock-screen row for destination.
  bool get _showsLiveActivity => widget.kind == AlertKind.arrival;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final options = AlertTiming.leadOptions(widget.kind);

    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(LyneRadius.lg)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _topBar(context, t),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerChip(context, t),
                    const SizedBox(height: 20),
                    _sectionHeader(
                      t,
                      icon: Icons.schedule_rounded,
                      title: 'How early do you want to be notified?',
                      subtitle:
                          "You'll get a notification before the bus arrives.",
                    ),
                    const SizedBox(height: 10),
                    _leadList(context, t, options),
                    const SizedBox(height: 16),
                    _summaryCard(context, t),
                    const SizedBox(height: 20),
                    _sectionHeader(
                      t,
                      icon: Icons.smartphone_rounded,
                      title: 'Where should we notify you?',
                      subtitle: 'Choose where you want to receive alerts.',
                    ),
                    const SizedBox(height: 10),
                    _deliveryList(context, t),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: Cancel · "Notify me when" · Done ──────────────────────────
  Widget _topBar(BuildContext context, LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: t.sans(15, color: t.dim)),
          ),
          Expanded(
            child: Text(
              'Notify me when',
              textAlign: TextAlign.center,
              style: t.sans(16, weight: FontWeight.w700, color: t.fg),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop((
              lead: _lead,
              liveActivity: _showsLiveActivity && _liveActivity,
            )),
            child: Text(
              'Done',
              style: t.sans(15, weight: FontWeight.w700, color: t.accent),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header chip — bus badge (arrival) / flag + "Destination stop" (dest) ──
  Widget _headerChip(BuildContext context, LyneTheme t) {
    final isDest = widget.kind == AlertKind.destination;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Row(
        children: [
          if (isDest)
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.soonBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.flag_rounded, size: 22, color: t.soon),
            )
          else
            Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                widget.busNo,
                style: t.sans(18, weight: FontWeight.w700, color: t.onAccent),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDest ? 'Destination stop' : 'Bus ${widget.busNo}',
                  style: t.sans(13, weight: FontWeight.w500, color: t.dim),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.stopName,
                  style: t.sans(16, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.dest.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Towards ${widget.dest}',
                    style: t.sans(12, color: t.faint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (!isDest) ...[
            const SizedBox(width: 8),
            _livePill(t),
          ],
        ],
      ),
    );
  }

  /// Confident "LIVE" badge — the sheet is only ever opened for a bus with
  /// live arrivals, so we present it without hedging (per the timely-updates
  /// design language). Replaces the old trailing chevron.
  Widget _livePill(LyneTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.soonBg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_rounded, size: 13, color: t.soon),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: t.sans(12, weight: FontWeight.w700, color: t.soon),
          ),
        ],
      ),
    );
  }

  // ── Section header: icon + title + subtitle ─────────────────────────────
  Widget _sectionHeader(
    LyneTheme t, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: t.soon),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.sans(15, weight: FontWeight.w600, color: t.fg)),
                const SizedBox(height: 2),
                Text(subtitle, style: t.sans(12, color: t.dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Lead radio list ─────────────────────────────────────────────────────
  Widget _leadList(BuildContext context, LyneTheme t, List<int> options) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          border: Border.all(color: t.line, width: 1),
        ),
        child: Column(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Divider(height: 1, thickness: 1, color: t.line),
                ),
              _leadRow(context, t, options[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leadRow(BuildContext context, LyneTheme t, int lead) {
    final selected = lead == _lead;
    final recommended = lead <= 1; // "When bus is arriving"
    return InkWell(
      onTap: () => setState(() => _lead = lead),
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? t.soonBg : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? t.soon : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? t.soonBg : t.surfaceHi,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                recommended
                    ? Icons.directions_bus_rounded
                    : Icons.notifications_rounded,
                size: 17,
                color: selected ? t.soon : t.dim,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          AlertTiming.leadLabel(lead),
                          style: t.sans(
                            15,
                            weight: FontWeight.w500,
                            color: t.fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.soonBg,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'Recommended',
                            style: t.sans(10,
                                weight: FontWeight.w600, color: t.soon),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    AlertTiming.leadSubLabel(lead),
                    style: t.mono(11, color: t.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 22, color: t.soon)
            else
              Icon(Icons.circle_outlined, size: 22, color: t.faint),
          ],
        ),
      ),
    );
  }

  // ── Summary card + live notification preview ────────────────────────────
  Widget _summaryCard(BuildContext context, LyneTheme t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.soonBg,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.soonBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.notifications_active_rounded,
                    size: 18, color: t.soon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lead <= 1
                          ? "You'll be notified when it arrives"
                          : "You'll be notified $_lead min before",
                      style:
                          t.sans(14, weight: FontWeight.w600, color: t.fg),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      AlertTiming.summary(
                        kind: widget.kind,
                        busNo: widget.busNo,
                        stopName: widget.stopName,
                        leadMinutes: _lead,
                      ),
                      style: t.sans(13, color: t.dim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _notificationPreview(t),
            ],
          ),
        ],
      ),
    );
  }

  /// A miniature lock-screen banner showing exactly what will be delivered,
  /// built from the same AlertTiming copy so it tracks the chosen lead.
  Widget _notificationPreview(LyneTheme t) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 5),
              Text('Leyne',
                  style: t.sans(10, weight: FontWeight.w600, color: t.fg)),
              const Spacer(),
              Text('now', style: t.sans(9, color: t.faint)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AlertTiming.arrivalTitle(widget.busNo),
            style: t.sans(11, weight: FontWeight.w700, color: t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            AlertTiming.arrivalBody(widget.stopName, _lead),
            style: t.sans(10, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }


  // ── Delivery prefs: where to notify ─────────────────────────────────────
  Widget _deliveryList(BuildContext context, LyneTheme t) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          border: Border.all(color: t.line, width: 1),
        ),
        child: Column(
          children: [
            _deliveryRow(
              t,
              value: _push,
              onChanged: (v) => setState(() => _push = v),
              title: 'Push notification',
              subtitle: 'Sent to this device',
            ),
            if (_showsLiveActivity) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Divider(height: 1, thickness: 1, color: t.line),
              ),
              _deliveryRow(
                t,
                value: _liveActivity,
                onChanged: (v) => setState(() => _liveActivity = v),
                title: 'Lock screen (Live Activity)',
                subtitle: 'Follow your bus in real time',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deliveryRow(
    LyneTheme t, {
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          t.sans(15, weight: FontWeight.w500, color: t.fg)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: t.sans(12, color: t.dim)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              size: 22,
              color: value ? t.soon : t.faint,
            ),
          ],
        ),
      ),
    );
  }

}
