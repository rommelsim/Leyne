// RouteTimeline (Material 3) — vertical list of route stops with
// connector + dot + state chip. Tap upcoming to set alight.

import 'package:flutter/material.dart';
import '../../data/bus_progress.dart';
import '../../data/mrt_stations.dart';
import '../../theme.dart';

enum SoftRouteStopState { past, here, board, next, alight }

/// True when a bus stop sits at an MRT/LRT station. There's no bus-stop→station
/// dataset from LTA, but SG stop descriptions tag these with the "Stn" token
/// (e.g. "Bishan Stn", "Opp Serangoon Stn", "Bef Bugis Stn Exit C"), so the
/// name is the signal. Word-boundaried so ordinary names ("Stadium", "Newton")
/// don't false-positive; an explicit "MRT"/"LRT" also qualifies. Conservative
/// by design — surfaces a station only when confident ("if have", not always).
/// Mirrors iOS RouteTimeline.swift `stopServesMRT`.
bool stopServesMRT(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('mrt') || lower.contains('lrt')) return true;
  return RegExp(r'\bstn\b').hasMatch(lower);
}

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
    this.selectable = true,
    this.embedded = false,
  });

  final String svc;
  final List<SoftRouteStop> stops;
  final String? alightId;
  final ValueChanged<String?> onAlight;
  final DateTime? now;

  /// When false the list is a read-only viewer: no "tap to be alerted" hint
  /// and rows aren't tappable (alight selection disabled). Used in the bus
  /// view's route card, which is a glanceable viewer, not an editor.
  final bool selectable;

  /// When true, drop the inner card chrome (padding + surface) so the list
  /// sits flush inside its parent — e.g. embedded in the route bottom sheet.
  final bool embedded;

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

  // Whether the whole route list is shown. The header toggles it so the
  // (often long) bus→terminus list can be folded away.
  bool _routeShown = true;

  // Whether the stops past your stop (→ terminus) are revealed. Long routes
  // start with the tail folded so the card opens on bus → your stop.
  bool _tailExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final stops = widget.stops;

    final hereIdx = stops.indexWhere((s) => s.state == SoftRouteStopState.here);
    final boardIdx =
        stops.indexWhere((s) => s.state == SoftRouteStopState.board);

    // "N STOPS AWAY" badge: only meaningful when we have a live bus position
    // (`here`) and the boarding stop ahead of it. Count from the bus to YOUR
    // stop — not to the terminus, which the timeline now extends to.
    final showAhead = hereIdx >= 0 && boardIdx > hereIdx;
    final aheadCount = showAhead ? boardIdx - hereIdx : 0;

    final showHint = widget.selectable &&
        stops.any((s) => s.state == SoftRouteStopState.next);

    // Long-route collapse: fold the lead-in (everything more than 2 stops
    // before the focal stop) into one expandable node, keeping the actionable
    // tail visible. Focal = the earlier of the live bus and the boarding stop,
    // so collapse never folds the bus away.
    int focalIdx;
    if (hereIdx >= 0 && boardIdx >= 0) {
      focalIdx = hereIdx < boardIdx ? hereIdx : boardIdx;
    } else if (hereIdx >= 0) {
      focalIdx = hereIdx;
    } else if (boardIdx >= 0) {
      focalIdx = boardIdx;
    } else {
      focalIdx = 0;
    }
    final keepFrom = (focalIdx - 2).clamp(0, stops.length);
    final canCollapse = stops.length > RouteTimeline.maxVisible && keepFrom >= 2;
    final startIdx = (canCollapse && !_expanded) ? keepFrom : 0;

    // Trailing collapse: fold the run from past your stop → terminus so the
    // card opens on the part you care about (bus → your stop). Anchor = the
    // furthest important stop — boarding (or the live bus if no boarding),
    // pushed to the alight target when one is further along.
    final alightIdx = widget.alightId == null
        ? -1
        : stops.indexWhere((s) => s.id == widget.alightId);
    final boardOrHere = boardIdx >= 0 ? boardIdx : hereIdx;
    final tailAnchorIdx = boardOrHere > alightIdx ? boardOrHere : alightIdx;
    final tailKeepTo = tailAnchorIdx < 0
        ? stops.length - 1
        : (tailAnchorIdx + 2).clamp(0, stops.length - 1);
    final canCollapseTail =
        tailAnchorIdx >= 0 && (stops.length - 1 - tailKeepTo) >= 2;
    final effectiveEndIdx =
        (canCollapseTail && !_tailExpanded) ? tailKeepTo : stops.length - 1;

    return Container(
      padding: EdgeInsets.all(widget.embedded ? 0 : 16),
      decoration: widget.embedded
          ? null
          : BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(LyneRadius.md),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header — collapse / expand the whole route list.
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _routeShown = !_routeShown),
            child: Padding(
              padding: EdgeInsets.only(bottom: _routeShown ? 8 : 0, top: 2),
              child: Row(
                children: [
                  Text(
                    'ROUTE · BUS ${widget.svc}',
                    style: t
                        .mono(10, weight: FontWeight.w600, color: t.dim)
                        .copyWith(letterSpacing: 1),
                  ),
                  Text(
                    '  · ${stops.length}',
                    style: t.mono(10, weight: FontWeight.w600, color: t.faint),
                  ),
                  const Spacer(),
                  if (showAhead)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$aheadCount STOP${aheadCount == 1 ? "" : "S"} AWAY',
                        style: t
                            .mono(10, weight: FontWeight.w600, color: t.dim)
                            .copyWith(letterSpacing: 1),
                      ),
                    ),
                  Icon(
                    _routeShown
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: t.dim,
                  ),
                ],
              ),
            ),
          ),
          if (_routeShown) ...[
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
            for (var i = startIdx; i <= effectiveEndIdx; i++)
              _row(
                context,
                stops[i],
                !canCollapse && i == startIdx,
                i == stops.length - 1,
              ),
            // The long tail past your stop folds away; tapping reveals it.
            if (canCollapseTail)
              _tailCollapseNode(
                context,
                hiddenCount: stops.length - 1 - tailKeepTo,
                terminus: stops.isNotEmpty ? stops.last.name : 'the end',
              ),
          ],
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
                style: t.sans(13, weight: FontWeight.w500, color: t.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trailing counterpart to [_collapseNode] — folds the stops between your
  /// stop and the terminus. The connector enters from the top; nothing below.
  Widget _tailCollapseNode(
    BuildContext context, {
    required int hiddenCount,
    required String terminus,
  }) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _tailExpanded = !_tailExpanded),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Connector only while collapsed; when expanded the terminus
                  // above is the line's end, so this is a plain "hide" control.
                  if (!_tailExpanded)
                    Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Container(width: 2, color: t.line),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  Icon(
                    _tailExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: t.dim,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  _tailExpanded
                      ? 'Hide later stops'
                      : 'Show all $hiddenCount stop${hiddenCount == 1 ? "" : "s"} to $terminus',
                  style: t.sans(13, weight: FontWeight.w500, color: t.accent),
                ),
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
    // If this stop sits at a rail station, resolve its line code(s) so we can
    // show a colour-coded pill ("[EW23] Clementi"). Falls back to the generic
    // MRT tag for "Stn" names we can't map.
    final mrt = resolveMrtStation(stop.name);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: (upcoming && widget.selectable)
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
                // The bus marker's pulsing halo paints past the 24px rail.
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      // Top half: green if the bus has reached this stop.
                      Expanded(
                        child: Container(
                          width: 2,
                          color: first
                              ? Colors.transparent
                              : _connector(t, resolved),
                        ),
                      ),
                      // Bottom half: the bus hasn't travelled past its own stop
                      // yet, so the green trail ends *at* the bus — this half
                      // greys out, giving one continuous green run from the
                      // origin to the bus and grey all the way after.
                      Expanded(
                        child: Container(
                          width: 2,
                          color: last
                              ? Colors.transparent
                              : (BusProgress.lowerConnectorIsGreen(resolved)
                                  ? t.soon
                                  : t.line),
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
                child: Builder(
                  builder: (context) {
                    final isBoard = resolved == SoftRouteStopState.board;
                    final nameText = Text(
                      stop.name,
                      style: t.sans(
                        14,
                        weight: resolved == SoftRouteStopState.past
                            ? FontWeight.w400
                            : (isBoard ? FontWeight.w700 : FontWeight.w600),
                        color: resolved == SoftRouteStopState.past
                            ? t.dim
                            : (isBoard ? t.soon : t.fg),
                      ),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + code block. Boarding stop gets a soft green
                        // highlight fill + left accent bar (no outline).
                        Container(
                          padding: isBoard
                              ? const EdgeInsets.fromLTRB(9, 6, 8, 6)
                              : EdgeInsets.zero,
                          decoration: isBoard
                              ? BoxDecoration(
                                  color: t.soonBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                    left: BorderSide(color: t.soon, width: 3),
                                  ),
                                )
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name + rail pill wrap onto a second line
                                  // when they can't share one — no truncation.
                                  Expanded(
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 3,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        nameText,
                                        if (mrt != null)
                                          _mrtStationPill(t, mrt)
                                        else if (stopServesMRT(stop.name))
                                          _mrtBadge(t),
                                      ],
                                    ),
                                  ),
                                  if (resolved == SoftRouteStopState.next &&
                                      stop.etaMin != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      _clockETA(stop.etaMin!),
                                      style: t.mono(
                                        12,
                                        weight: FontWeight.w500,
                                        color: t.fg,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              // Dim mono stop-code subline when the code differs
                              // from the displayed name — parity with iOS.
                              if (stop.id != stop.name) ...[
                                const SizedBox(height: 1),
                                Text(stop.id,
                                    style: t.mono(10, color: t.faint)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (resolved == SoftRouteStopState.here)
                          _chip(t, 'BUS HERE NOW', filled: true),
                        if (resolved == SoftRouteStopState.alight)
                          _alightChip(t),
                      ],
                    );
                  },
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
        // The bus, right now — green with a bus glyph and a pulsing halo.
        return _BusHereDot(t: t);
      case SoftRouteStopState.board:
        // Your stop — a bold filled green target with a person glyph.
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: t.soon.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
              child: Icon(Icons.directions_walk_rounded,
                  size: 11, color: t.contrastFg),
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

  // Green marks track the bus has covered. Only stops the bus has reached
  // (passed, or its current stop) are green; your boarding/alight stop is
  // ahead of the bus, so its connector stays grey — no isolated green segment
  // detached from the bus's trail.
  Color _connector(LyneTheme t, SoftRouteStopState state) =>
      BusProgress.connectorIsGreen(state) ? t.soon : t.line;

  /// Subtle MRT-station marker — a tram glyph + "MRT" chip. Monochrome
  /// (t.dim on t.surfaceHi) so it reads as a neutral wayfinding attribute, not
  /// a live signal (green stays reserved for proximity/arrival). Mirrors the
  /// iOS RouteTimeline.swift `mrtBadge`.
  Widget _mrtBadge(LyneTheme t) {
    return Semantics(
      label: 'MRT station',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: t.surfaceHi,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tram, size: 9, color: t.dim),
            const SizedBox(width: 3),
            Text(
              'MRT',
              style: t
                  .mono(8, weight: FontWeight.w700, color: t.dim)
                  .copyWith(letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Colour-coded rail-station pill: one line-coloured code chip per line
  /// (e.g. green "EW23", or "EW24"+"NS1" for an interchange) followed by the
  /// station name. Single-line stations tint the pill with the line colour so
  /// it reads as, e.g., a "green pill"; interchanges stay neutral. Mirrors the
  /// iOS RouteTimeline.swift `mrtStationPill`.
  Widget _mrtStationPill(LyneTheme t, MrtStation mrt) {
    final tint = mrt.codes.length == 1 ? mrt.codes.first.color : null;
    return Semantics(
      label: 'MRT station ${mrt.name}, '
          '${mrt.codes.map((c) => c.code).join(", ")}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: tint != null
              ? tint.withValues(alpha: 0.14)
              : t.surfaceHi,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final code in mrt.codes) ...[
              _codeChip(code),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                mrt.name,
                style: t.sans(12, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A single station-code roundel — white code on the line's brand colour.
  Widget _codeChip(MrtCode code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: code.color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        code.code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
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

/// The live bus marker — green dot with a bus glyph and a continuously
/// rippling halo so the bus's position is findable at a glance. Honours
/// the system reduce-motion setting by falling back to the static halo.
/// Mirrors iOS RouteTimeline.swift `BusHereDot`.
class _BusHereDot extends StatefulWidget {
  const _BusHereDot({required this.t});

  final LyneTheme t;

  @override
  State<_BusHereDot> createState() => _BusHereDotState();
}

class _BusHereDotState extends State<_BusHereDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (reduceMotion)
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: t.soon.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
          )
        else
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              // Transform.scale paints outside the 22px box without
              // affecting layout, so the ripple never shifts the row.
              final v = Curves.easeOut.transform(_pulse.value);
              return Transform.scale(
                scale: 1 + 0.9 * v,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: t.soon.withValues(alpha: 0.45 * (1 - v)),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
          child:
              Icon(Icons.directions_bus_rounded, size: 11, color: t.contrastFg),
        ),
      ],
    );
  }
}
