// RouteTimeline (Material 3) — vertical list of route stops with
// connector + dot + state chip. Tap upcoming to set alight.

import 'package:flutter/material.dart';
import '../../theme.dart';

enum SoftRouteStopState { past, here, board, next, alight }

class SoftRouteStop {
  const SoftRouteStop({
    required this.id,
    required this.name,
    required this.state,
    this.etaMin,
  });
  final String id;
  final String name;
  final SoftRouteStopState state;
  final int? etaMin;
}

class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    super.key,
    required this.svc,
    required this.stops,
    required this.alightId,
    required this.onAlight,
    this.now,
  });

  final String svc;
  final List<SoftRouteStop> stops;
  final String? alightId;
  final ValueChanged<String?> onAlight;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    // "N STOPS AWAY" badge: iOS deliberately suppresses this because busIndex
    // is always nil today (DataStore hard-codes it to null — RouteTimeline.swift
    // comment). Android mirrors that decision: only show the badge when we have
    // a genuine live bus position (aheadIdx >= 0 AND at least one stop has
    // the `here` state, i.e. the live bus position is actually known).
    final hereIdx = stops.indexWhere((s) => s.state == SoftRouteStopState.here);
    // aheadCount is only meaningful when there is a live `.here` stop
    // (hereIdx > 0 ensures it isn't the very first stop, which would give 0).
    final showAhead = hereIdx > 0;
    final aheadCount = showAhead ? stops.length - hereIdx - 1 : 0;

    final showHint =
        alightId == null &&
        stops.any((s) => s.state == SoftRouteStopState.next);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ROUTE · BUS $svc',
                style: t
                    .mono(10, weight: FontWeight.w600, color: t.dim)
                    .copyWith(letterSpacing: 1),
              ),
              const Spacer(),
              // Badge suppressed unless we have a genuine live bus position.
              // Mirror of iOS RouteTimeline.swift comment.
              if (showAhead)
                Text(
                  '$aheadCount STOP${aheadCount == 1 ? "" : "S"} AWAY',
                  style: t
                      .mono(10, weight: FontWeight.w600, color: t.dim)
                      .copyWith(letterSpacing: 1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (showHint)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Tap a stop to be alerted when arriving.',
                style: t.sans(12, color: t.dim),
              ),
            ),
          for (var i = 0; i < stops.length; i++)
            _row(context, stops[i], i == 0, i == stops.length - 1),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SoftRouteStop stop, bool first, bool last) {
    final t = context.t;
    final upcoming =
        stop.state == SoftRouteStopState.next ||
        stop.state == SoftRouteStopState.alight;
    final resolved = (alightId == stop.id && upcoming)
        ? SoftRouteStopState.alight
        : (stop.state == SoftRouteStopState.alight
              ? SoftRouteStopState.next
              : stop.state);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: upcoming
          ? () => onAlight(alightId == stop.id ? null : stop.id)
          : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: 2,
                          color: first
                              ? Colors.transparent
                              : _connector(t, resolved),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: last
                              ? Colors.transparent
                              : _connector(t, resolved),
                        ),
                      ),
                    ],
                  ),
                  _dot(t, resolved),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stop.name,
                            style: t.sans(
                              14,
                              weight: resolved == SoftRouteStopState.past
                                  ? FontWeight.w400
                                  : FontWeight.w500,
                              color: resolved == SoftRouteStopState.past
                                  ? t.faint
                                  : t.fg,
                            ),
                          ),
                        ),
                        if (resolved == SoftRouteStopState.next &&
                            stop.etaMin != null)
                          Text(
                            _clockETA(stop.etaMin!),
                            style: t.mono(
                              12,
                              weight: FontWeight.w500,
                              color: t.dim,
                            ),
                          ),
                      ],
                    ),
                    // Dim mono stop-code subline when the code differs from
                    // the displayed name — parity with iOS RouteTimeline.swift.
                    if (stop.id != stop.name) ...[
                      const SizedBox(height: 1),
                      Text(stop.id, style: t.mono(10, color: t.faint)),
                    ],
                    const SizedBox(height: 2),
                    if (resolved == SoftRouteStopState.here)
                      _chip(t, 'BUS HERE NOW', filled: false),
                    // Change 7: "THIS STOP" aligns with iOS chip label (was "BOARD").
                    if (resolved == SoftRouteStopState.board)
                      _chip(t, 'THIS STOP', filled: true),
                    if (resolved == SoftRouteStopState.alight) _alightChip(t),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(LyneTheme t, SoftRouteStopState state) {
    switch (state) {
      case SoftRouteStopState.past:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: t.faint, shape: BoxShape.circle),
        );
      case SoftRouteStopState.here:
      case SoftRouteStopState.board:
      case SoftRouteStopState.alight:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      case SoftRouteStopState.next:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.dim, width: 1.5),
          ),
        );
    }
  }

  Color _connector(LyneTheme t, SoftRouteStopState state) {
    switch (state) {
      case SoftRouteStopState.past:
      case SoftRouteStopState.next:
        return t.line;
      case SoftRouteStopState.here:
      case SoftRouteStopState.board:
      case SoftRouteStopState.alight:
        return t.accent.withValues(alpha: 0.5);
    }
  }

  Widget _chip(LyneTheme t, String text, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? t.accent : t.liveBg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: filled ? Colors.transparent : t.accent.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: t
            .mono(
              9,
              weight: FontWeight.w600,
              color: filled ? t.onAccent : t.accent,
            )
            .copyWith(letterSpacing: 1),
      ),
    );
  }

  /// ALIGHT chip — replaces the bare "🔔 ALIGHT" emoji string with a
  /// proper Icon + text Row so TalkBack reads it correctly and it scales
  /// with system font size.
  Widget _alightChip(LyneTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active_rounded, size: 10, color: t.onAccent),
          const SizedBox(width: 3),
          Text(
            'ALIGHT',
            style: t
                .mono(9, weight: FontWeight.w600, color: t.onAccent)
                .copyWith(letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  String _clockETA(int mins) {
    final target = (now ?? DateTime.now()).add(Duration(minutes: mins));
    final h = target.hour.toString().padLeft(2, '0');
    final m = target.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
