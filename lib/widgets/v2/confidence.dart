// Confidence — Leyne 3.0's headline idea, ported from the iOS Soft system
// (ios-native/Leyne/V2/Confidence.swift) into Flutter/Material.
//
// Leyne doesn't compete on accuracy (every SG app reads the same LTA feed);
// it competes on *honesty about uncertainty*. So every arrival carries a
// confidence level, and that level is expressed ONLY through opacity, dot
// shape and freshness microcopy — never a new hue. The one reserved accent
// (mint) still means just "imminent / arriving".
//
//   live         GPS-monitored and the feed is fresh           solid ink
//   stale        GPS-monitored but the feed has aged            hollow ring
//   unconfirmed  timetabled but no live GPS (the "ghost bus")   dashed ring
//   none         nothing coming                                 em-dash
//
// Derivation uses only data we actually have: LTA's `Monitored` flag
// (Service.monitored) and how long ago we last refreshed the stop
// (DataStore.lastRefresh → Freshness). Nothing is invented.
//
// Per the `feedback_timely_over_honest` memory: numerals stay full-ink and
// confident; the only tell that an arrival is estimated is a faint, trailing
// "~" a careful eye catches. Uncertainty is a whisper, never a banner.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../theme.dart';

// ─── Freshness ─────────────────────────────────────────────────────────
/// How recently a stop's arrivals were pulled from LTA. Mirrors
/// `Freshness` in ios-native/Leyne/Models.swift.
enum Freshness {
  live, // last successful refresh < 30s ago
  stale, // 30s – 5 min ago
  offline; // > 5 min ago, or never fetched, or error state

  static Freshness from(DateTime? lastRefresh, {DateTime? now}) {
    if (lastRefresh == null) return Freshness.offline;
    final dt = (now ?? DateTime.now()).difference(lastRefresh).inSeconds;
    if (dt < 30) return Freshness.live;
    if (dt < 300) return Freshness.stale;
    return Freshness.offline;
  }
}

// ─── ArrivalConfidence ─────────────────────────────────────────────────
enum ArrivalConfidence {
  live,
  stale,
  unconfirmed,
  none;

  /// Map an arrival to a confidence level. [feed] is the stop-level freshness
  /// (how recently we pulled arrivals); [monitored] is LTA's per-arrival GPS
  /// flag. A non-monitored arrival is always a ghost bus regardless of feed
  /// age — it's timetable data, not live.
  static ArrivalConfidence of({
    required bool monitored,
    required Freshness feed,
  }) {
    if (!monitored) return ArrivalConfidence.unconfirmed;
    switch (feed) {
      case Freshness.live:
        return ArrivalConfidence.live;
      case Freshness.stale:
      case Freshness.offline:
        return ArrivalConfidence.stale;
    }
  }

  /// Opacity applied to the ETA numeral when a caller wants the softened
  /// look. The inline [ConfidenceEta] keeps numerals full-ink (whisper rule);
  /// this is here for larger/secondary numerals that opt in.
  double numeralOpacity({double stale = 0.5}) {
    switch (this) {
      case ArrivalConfidence.live:
        return 1;
      case ArrivalConfidence.stale:
        return stale;
      case ArrivalConfidence.unconfirmed:
        return 0.42;
      case ArrivalConfidence.none:
        return 1;
    }
  }

  /// Numeral colour. The reserved accent appears only for a *live* imminent
  /// arrival; everything else is monochrome ink so confidence reads from
  /// opacity/shape, not colour.
  Color numeralColor({required bool imminent, required LyneTheme t}) {
    if (this == ArrivalConfidence.none) return t.faint;
    return (imminent && this == ArrivalConfidence.live) ? t.accent : t.fg;
  }

  /// Short status word for the provenance pill / chip.
  String get statusWord {
    switch (this) {
      case ArrivalConfidence.live:
        return 'Live';
      case ArrivalConfidence.stale:
        return 'Estimated';
      case ArrivalConfidence.unconfirmed:
        return 'Scheduled';
      case ArrivalConfidence.none:
        return '—';
    }
  }

  /// One honest line of freshness microcopy. [ageSec] is how long ago the
  /// feed last refreshed (null → omit the relative time).
  String microcopy({int? ageSec}) {
    switch (this) {
      case ArrivalConfidence.live:
        return ageSec == null ? 'live' : 'live · ${ageSec}s ago';
      case ArrivalConfidence.stale:
        return ageSec == null ? 'estimate aging' : 'updated ${ageSec}s ago';
      case ArrivalConfidence.unconfirmed:
        return 'scheduled · no live signal';
      case ArrivalConfidence.none:
        return 'last bus gone';
    }
  }
}

// ─── Freshness dot ─────────────────────────────────────────────────────
/// Tiny confidence dot. Hue-free: the *shape* carries the meaning so it
/// works for colour-blind users and doesn't spend the reserved accent.
///   live → filled ink · stale/none → hollow ring · unconfirmed → dashed ring
class ConfidenceDot extends StatelessWidget {
  const ConfidenceDot({super.key, required this.confidence, this.size = 7});

  final ArrivalConfidence confidence;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    switch (confidence) {
      case ArrivalConfidence.live:
        // Green dot for live confidence — mirrors iOS Confidence.swift
        // ConfidenceDot which fills with t.soon.
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
        );
      case ArrivalConfidence.stale:
      case ArrivalConfidence.none:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.faint, width: 1.5),
          ),
        );
      case ArrivalConfidence.unconfirmed:
        return CustomPaint(
          size: Size.square(size),
          painter: _DashedCirclePainter(color: t.faint, strokeWidth: 1.5),
        );
    }
  }
}

// ─── Confidence-aware ETA numeral (inline use) ─────────────────────────
/// The arrival number, rendered WHISPER-QUIET: always a confident, full-ink
/// figure (no dimming, no "~" prefix) so the app never undersells its
/// timeliness — that's the selling point. The only tell that an arrival is
/// estimated/aged is a faint, trailing "~" a careful eye catches. The
/// screen-reader label at the call site stays fully honest.
/// See memory `feedback_timely_over_honest`.
class ConfidenceEta extends StatelessWidget {
  const ConfidenceEta({
    super.key,
    required this.etaSec,
    required this.confidence,
    this.size = 15,
    this.weight = FontWeight.w600,
  });

  final int etaSec;
  final ArrivalConfidence confidence;
  final double size;
  final FontWeight weight;

  bool get _imminent {
    final eta = fmtEta(etaSec);
    return confidence == ArrivalConfidence.live && eta.live;
  }

  /// Show the faint estimate tell when the arrival isn't a fresh live fix.
  bool get _whisper =>
      confidence == ArrivalConfidence.stale ||
      confidence == ArrivalConfidence.unconfirmed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (confidence == ArrivalConfidence.none) {
      return Text(
        '—',
        style: t.mono(size, weight: weight, color: t.faint),
      );
    }
    final eta = fmtEta(etaSec);
    final color = _imminent ? t.accent : t.fg;
    final children = <Widget>[];
    if (eta.big == 'Arr') {
      // Arriving now — render the small word as the figure.
      children.add(
        Text(
          eta.small,
          style: t.mono(size, weight: weight, color: color),
        ),
      );
    } else {
      children.add(
        Text(
          eta.big,
          style: t.mono(size, weight: weight, color: color),
        ),
      );
      children.add(const SizedBox(width: 2));
      children.add(
        Text(
          eta.small,
          style: t.mono(
            size * 0.72,
            weight: FontWeight.w500,
            color: _imminent ? t.accent : t.dim,
          ),
        ),
      );
    }
    if (_whisper) {
      children.add(const SizedBox(width: 2));
      children.add(_whisperTilde(t));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }

  /// Near-invisible estimate marker — small, faint, screen-reader-hidden.
  Widget _whisperTilde(LyneTheme t) => ExcludeSemantics(
    child: Opacity(
      opacity: 0.7,
      child: Text(
        '~',
        style: t.mono(size * 0.6, weight: FontWeight.w400, color: t.faint),
      ),
    ),
  );
}

// ─── Status pill (Bus view) ────────────────────────────────────────────
/// LIVE / ESTIMATED / SCHEDULED pill. LIVE is the one place the accent
/// surfaces as a status dot (on an inverse pill); the softer states use a
/// hollow/dashed dot on a raised surface so the gradient of certainty reads
/// at a glance.
class ConfidenceStatusPill extends StatelessWidget {
  const ConfidenceStatusPill({super.key, required this.confidence});

  final ArrivalConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isLive = confidence == ArrivalConfidence.live;
    return Semantics(
      label: _a11y,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isLive ? t.contrast : t.surfaceHi,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isLive ? Colors.transparent : t.line,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(t),
            const SizedBox(width: 5),
            Text(
              _label,
              style: t
                  .mono(
                    10,
                    weight: FontWeight.w600,
                    color: isLive ? t.contrastFg : t.dim,
                  )
                  .copyWith(letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(LyneTheme t) {
    switch (confidence) {
      case ArrivalConfidence.live:
        // Green dot in the LIVE status pill — mirrors iOS ConfidenceStatusPill.
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
        );
      case ArrivalConfidence.stale:
      case ArrivalConfidence.none:
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.dim, width: 1.5),
          ),
        );
      case ArrivalConfidence.unconfirmed:
        return CustomPaint(
          size: const Size.square(6),
          painter: _DashedCirclePainter(color: t.dim, strokeWidth: 1.5),
        );
    }
  }

  String get _label {
    switch (confidence) {
      case ArrivalConfidence.live:
        return 'LIVE';
      case ArrivalConfidence.stale:
        return 'ESTIMATED';
      case ArrivalConfidence.unconfirmed:
        return 'SCHEDULED';
      case ArrivalConfidence.none:
        return '—';
    }
  }

  String get _a11y {
    switch (confidence) {
      case ArrivalConfidence.live:
        return 'Live arrival, tracked by GPS';
      case ArrivalConfidence.stale:
        return 'Estimated — live signal aging';
      case ArrivalConfidence.unconfirmed:
        return 'Scheduled estimate, no live GPS signal';
      case ArrivalConfidence.none:
        return 'No service';
    }
  }
}

// ─── Crowd meter glyph ─────────────────────────────────────────────────
/// Occupancy shown as a row of three person glyphs filled by load
/// (Seats=1, Standing=2, Crowded=3) and tinted green / amber / grey — the
/// "how full is the bus" metaphor riders already know from the LTA app.
/// (Deliberately NOT ascending bars: those read as a cellular-signal meter,
/// which is the wrong sense — more crowding is worse, not "stronger".)
/// Matches ios-native/Leyne/V2/Confidence.swift CrowdMeter exactly.
/// Unknown shows three faint outline persons, honestly rather than hidden.
class CrowdMeter extends StatelessWidget {
  const CrowdMeter({super.key, required this.load, this.showLabel = true});

  final Load? load; // null → unknown
  final bool showLabel;

  int get _fill {
    switch (load) {
      case Load.sea:
        return 1;
      case Load.sda:
        return 2;
      case Load.lsd:
        return 3;
      case null:
        return 0;
    }
  }

  /// Fuller phrasing so rows read "Seats available" rather than just "Seats".
  String get _label {
    switch (load) {
      case Load.sea:
        return 'Seats available';
      case Load.sda:
        return 'Standing available';
      case Load.lsd:
        return 'Limited standing';
      case null:
        return 'Crowd unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      label: load == null ? 'Crowd unknown' : _label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 1.5),
                Icon(
                  (load != null && i < _fill)
                      ? Icons.person_rounded
                      : Icons.person_outline_rounded,
                  size: 13,
                  color: _personColor(i, t),
                ),
              ],
            ],
          ),
          if (showLabel) ...[
            const SizedBox(width: 5),
            Text(
              _label,
              style: t.mono(
                10,
                weight: FontWeight.w500,
                color: load == null ? t.faint : _occupancyColor(load, t),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Filled persons take the occupancy hue; empty persons are hairline;
  /// unknown load greys the whole row.
  Color _personColor(int i, LyneTheme t) {
    if (load == null) return t.faint;
    return i < _fill ? _occupancyColor(load, t) : t.line;
  }

  /// Inline version of occupancyColor to avoid a circular import with
  /// proximity.dart (which imports confidence.dart). The logic is
  /// identical to occupancyColor() in proximity.dart.
  static Color _occupancyColor(Load? load, LyneTheme t) {
    switch (load) {
      case Load.sea:
        return t.soon;
      case Load.sda:
        return t.mid;
      case Load.lsd:
      case null:
        return t.dim;
    }
  }
}

// ─── Dashed-stroke painters ────────────────────────────────────────────
// Flutter has no dashed-border primitive, so the dashed dot/bar variants are
// drawn by walking the path and stamping `dash`/`gap` segments. Dash pattern
// [2, 2] mirrors the iOS StrokeStyle.

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()..addOval(rect);
    _drawDashed(canvas, path, paint, dash: 2, gap: 2);
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// Stamp a [dash]/[gap] pattern along [source], drawing onto [canvas].
void _drawDashed(
  Canvas canvas,
  Path source,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }
}
