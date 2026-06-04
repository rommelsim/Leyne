// Proximity & occupancy — 2.4.0 semantic-colour layer.
// Dart port of ios-native/Leyne/V2/Proximity.swift.
//
// Two orthogonal signals get colour here, and ONLY these two:
//   • ETA proximity — how soon a bus arrives (green → amber → neutral)
//   • Occupancy     — how full it is (seats green · standing amber · grey)
//
// Confidence (live / stale / scheduled) is deliberately NOT colour — it stays
// shape + opacity + the whisper "~" (see confidence.dart), so the honesty
// thesis and colour-blind legibility survive. A scheduled/ghost arrival is
// shown neutral regardless of how soon it is: we never paint an unverified
// time green.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme.dart';
import 'confidence.dart';

// ─── ETA proximity ─────────────────────────────────────────────────────────

/// How soon an arrival is, bucketed for colour + "Arriving soon" copy.
/// Thresholds mirror the iOS Proximity.swift spec:
///   imminent  < 150s  (< ~2.5 min) → green + "Arriving soon"
///   soon      < 540s  (< ~9 min)   → green
///   medium    < 960s  (< ~16 min)  → amber
///   far       ≥ 960s               → neutral grey
enum EtaTier {
  imminent,
  soon,
  medium,
  far;

  static EtaTier of(int etaSec) {
    if (etaSec < 150) return EtaTier.imminent;
    if (etaSec < 540) return EtaTier.soon;
    if (etaSec < 960) return EtaTier.medium;
    return EtaTier.far;
  }

  bool get isImminent => this == EtaTier.imminent;
}

/// Resolves the colour for an arrival's ETA, gating on confidence: a bus we
/// can't verify live (scheduled/ghost) is always neutral — we never paint an
/// unconfirmed time green or amber. Stale (was-live, now aging) keeps its
/// proximity hue; the "~" whisper already signals the aging.
Color etaColor({
  required int etaSec,
  required ArrivalConfidence confidence,
  required LyneTheme t,
}) {
  switch (confidence) {
    case ArrivalConfidence.unconfirmed:
    case ArrivalConfidence.none:
      return t.dim;
    case ArrivalConfidence.live:
    case ArrivalConfidence.stale:
      switch (EtaTier.of(etaSec)) {
        case EtaTier.imminent:
        case EtaTier.soon:
          return t.soon;
        case EtaTier.medium:
          return t.mid;
        case EtaTier.far:
          return t.dim;
      }
  }
}

/// Fill + foreground colour for a proximity-coloured service badge.
/// soon → green fill, amber for medium, neutral surface for far / scheduled.
({Color fill, Color fg}) serviceBadgeColors({
  required int etaSec,
  required ArrivalConfidence confidence,
  required LyneTheme t,
}) {
  switch (confidence) {
    case ArrivalConfidence.unconfirmed:
    case ArrivalConfidence.none:
      return (fill: t.surfaceHi, fg: t.fg);
    case ArrivalConfidence.live:
    case ArrivalConfidence.stale:
      switch (EtaTier.of(etaSec)) {
        case EtaTier.imminent:
        case EtaTier.soon:
          return (fill: t.soon, fg: t.contrastFg);
        case EtaTier.medium:
          return (fill: t.mid, fg: t.contrastFg);
        case EtaTier.far:
          return (fill: t.surfaceHi, fg: t.fg);
      }
  }
}

// ─── Occupancy ─────────────────────────────────────────────────────────────

/// Shared crowding colour: seats → green, standing → amber, limited/unknown
/// → neutral grey. Used by both OccupancyLabel and CrowdMeter.
Color occupancyColor(Load? load, LyneTheme t) {
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

// ─── OccupancyLabel ────────────────────────────────────────────────────────

/// Crowding label — icon + plain-English words, coloured by space remaining.
/// seats (green) · standing (amber) · limited (grey).
/// Sits under the destination on Stop/Bus rows.
class OccupancyLabel extends StatelessWidget {
  const OccupancyLabel({super.key, required this.load, this.size = 12});

  final Load load;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = occupancyColor(load, t);
    return Semantics(
      label: _text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: size, color: color),
          const SizedBox(width: 4),
          Text(_text,
              style: t.mono(size, weight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (load) {
      case Load.sea:
        return Icons.weekend_outlined; // seats
      case Load.sda:
        return Icons.people_outline;
      case Load.lsd:
        return Icons.people;
    }
  }

  String get _text {
    switch (load) {
      case Load.sea:
        return 'Seats available';
      case Load.sda:
        return 'Standing available';
      case Load.lsd:
        return 'Limited standing';
    }
  }
}
