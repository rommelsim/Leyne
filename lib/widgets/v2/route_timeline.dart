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

class RouteTimeline extends StatefulWidget {
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

  /// Beyond this many stops the leading run is collapsed behind a "show
  /// earlier stops" node so a long route stays scannable. Kept in sync with
  /// the iOS RouteTimeline (`maxVisible`).
  static const int maxVisible = 8;

  @override
  State<RouteTimeline> createState() => _RouteTimelineState();
}

class _RouteTimelineState extends State<RouteTimeline> {
  // Whether the collapsed leading stops are revealed. Long routes start
  // collapsed so the boarding/upcoming area is what you see first.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final stops = widget.stops;

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
        widget.alightId == null &&
        stops.any((s) => s.state == SoftRouteStopState.next);

    // Long-route collapse: fold the lead-in (everything more than 2 stops
    // before the focal stop — the boarding stop, else the live bus, else the
    // start) into one expandable node, keeping the actionable tail visible.
    int focalIdx =
        stops.indexWhere((s) => s.state == SoftRouteStopState.board);
    if (focalIdx < 0) focalIdx = hereIdx;
    if (focalIdx < 0) focalIdx = 0;
    final keepFrom = (focalIdx - 2).clamp(0, stops.length);
    final canCollapse = stops.length > RouteTimeline.maxVisible && keepFrom >= 2;
    final startIdx = (canCollapse && !_expanded) ? keepFrom : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ROUTE · BUS ${widget.svc}',
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
          // The collapse node sits at the visual top when active; the first
          // rendered stop then keeps its top connector so the line is unbroken.
          if (canCollapse) _collapseNode(context, hiddenCount: keepFrom),
          for (var i = startIdx; i < stops.length; i++)
            _row(
              context,
              stops[i],
              !canCollapse && i == startIdx,
              i == stops.length - 1,
            ),
        ],
      ),
    );
  }

  /// Expandable node standing in for the collapsed leading stops. Tapping it
  /// toggles the full list. Drawn like a route row (connector + glyph) so it
  /// reads as part of the line, not a detached button.
  Widget _collapseNode(BuildContext context, {required int hiddenCount}) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _expanded = !_expanded),
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
                      // Node is the visual top — no connector above it.
                      const Expanded(child: SizedBox()),
                      Expanded(
                        child: Center(
                          child: Container(width: 2, color: t.line),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: t.dim,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 2),
              child: Text(
                _expanded
                    ? 'Hide earlier stops'
                    : 'Show $hiddenCount earlier stop${hiddenCount == 1 ? "" : "s"}',
                style: t.sans(13, weight: FontWeight.w500, color: t.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, SoftRouteStop stop, bool first, bool last) {
    final t = context.t;
    final upcoming =
        stop.state == SoftRouteStopState.next ||
        stop.state == SoftRouteStopState.alight;
    final resolved = (widget.alightId == stop.id && upcoming)
        ? SoftRouteStopState.alight
        : (stop.state == SoftRouteStopState.alight
              ? SoftRouteStopState.next
              : stop.state);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: upcoming
          ? () => widget.onAlight(widget.alightId == stop.id ? null : stop.id)
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
        // Traversed — a completed green check.
        return Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 10, color: t.contrastFg),
        );
      case SoftRouteStopState.here:
        // The bus, right now — green with a bus glyph.
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: t.soon.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
              child: Icon(Icons.directions_bus_rounded, size: 11, color: t.contrastFg),
            ),
          ],
        );
      case SoftRouteStopState.board:
        // Your stop — a green ring.
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: t.soon.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: t.surface,
                shape: BoxShape.circle,
                border: Border.all(color: t.soon, width: 2.5),
              ),
            ),
          ],
        );
      case SoftRouteStopState.alight:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: t.soon.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
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
      case SoftRouteStopState.next:
        return t.line;
      case SoftRouteStopState.past:
      case SoftRouteStopState.here:
      case SoftRouteStopState.board:
      case SoftRouteStopState.alight:
        return t.soon;
    }
  }

  Widget _chip(LyneTheme t, String text, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? t.soon : t.soonBg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: filled ? Colors.transparent : t.soon.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: t
            .mono(
              9,
              weight: FontWeight.w600,
              color: filled ? t.contrastFg : t.soon,
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
        color: t.soon,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active_rounded, size: 10, color: t.contrastFg),
          const SizedBox(width: 3),
          Text(
            'ALIGHT',
            style: t
                .mono(9, weight: FontWeight.w600, color: t.contrastFg)
                .copyWith(letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  String _clockETA(int mins) {
    final target = (widget.now ?? DateTime.now()).add(Duration(minutes: mins));
    final h = target.hour.toString().padLeft(2, '0');
    final m = target.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
