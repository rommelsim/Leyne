// NotifyConfirm — the "You'll be notified!" confirmation sheet shown right
// after an alert is created (Material 3). Green check, the summary sentence,
// an "Active alert" chip whose ✕ removes the just-created alert, and a
// "Manage all alerts ›" row that hands off to the central list.

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../state/app_model.dart';
import '../../theme.dart';

/// Present the confirmation sheet. [onManageAll] is invoked (after the sheet
/// closes) when the user taps "Manage all alerts".
Future<void> showNotifyConfirm(
  BuildContext context, {
  required AlertKind kind,
  required String busNo,
  required String stopCode,
  required String stopName,
  required int leadMinutes,
  required VoidCallback onManageAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotifyConfirm(
      kind: kind,
      busNo: busNo,
      stopCode: stopCode,
      stopName: stopName,
      leadMinutes: leadMinutes,
      onManageAll: onManageAll,
    ),
  );
}

class _NotifyConfirm extends StatefulWidget {
  const _NotifyConfirm({
    required this.kind,
    required this.busNo,
    required this.stopCode,
    required this.stopName,
    required this.leadMinutes,
    required this.onManageAll,
  });

  final AlertKind kind;
  final String busNo;
  final String stopCode;
  final String stopName;
  final int leadMinutes;
  final VoidCallback onManageAll;

  @override
  State<_NotifyConfirm> createState() => _NotifyConfirmState();
}

class _NotifyConfirmState extends State<_NotifyConfirm> {
  // Once the user removes the alert from the chip, hide the chip + disable
  // "Manage all" so the sheet reads honestly without closing abruptly.
  bool _removed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(LyneRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Grabber.
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: t.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Green check circle.
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.soonBg, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 36, color: t.soon),
              ),
              const SizedBox(height: 16),
              Text(
                "You'll be notified!",
                style: t.sans(20, weight: FontWeight.w700, color: t.fg),
              ),
              const SizedBox(height: 8),
              Text(
                AlertTiming.summary(
                  kind: widget.kind,
                  busNo: widget.busNo,
                  stopName: widget.stopName,
                  leadMinutes: widget.leadMinutes,
                ),
                textAlign: TextAlign.center,
                style: t.sans(14, color: t.dim),
              ),
              const SizedBox(height: 20),
              if (!_removed) _activeChip(context, t),
              const SizedBox(height: 12),
              _manageRow(context, t),
            ],
          ),
        ),
      ),
    );
  }

  // ── Active-alert chip with a removing ✕ ─────────────────────────────────
  Widget _activeChip(BuildContext context, LyneTheme t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.full),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.kind == AlertKind.destination
                ? Icons.flag_rounded
                : Icons.notifications_active_rounded,
            size: 16,
            color: t.soon,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.stopName,
              style: t.sans(13, weight: FontWeight.w600, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Remove alert',
            icon: Icon(Icons.close_rounded, size: 18, color: t.dim),
            onPressed: () {
              AppModel.shared.removeAlertsFor(
                kind: widget.kind,
                busNo: widget.busNo,
                stopCode: widget.stopCode,
              );
              setState(() => _removed = true);
            },
          ),
        ],
      ),
    );
  }

  // ── "Manage all alerts ›" row ───────────────────────────────────────────
  Widget _manageRow(BuildContext context, LyneTheme t) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          widget.onManageAll();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            border: Border.all(color: t.line, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Manage all alerts',
                  style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }
}
