// Proximity & occupancy.
// Dart port of ios-native/Leyne/V2/Proximity.swift.
//
// ETA / soon-ness is deliberately NOT colour-coded: arrival times read as
// uniform ink, and only confidence dims them (scheduled/ghost arrivals show
// faint — the honesty whisper, see confidence.dart). The one remaining colour
// signal here is occupancy — how full a bus is (seats green · standing amber ·
// limited grey).
//
// (iOS keeps an `ETATier` enum to drive an "Arriving soon" text cue on its
// Home mini-chips; the Flutter UI has no such cue, so it isn't ported here.)

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme.dart';
import 'confidence.dart';

// ─── ETA proximity ─────────────────────────────────────────────────────────

/// Ink for an arrival's ETA. ETA numerals always render at full foreground ink
/// regardless of confidence — the app sells timeliness, not uncertainty.
/// The one exception preserved: an imminent live arrival uses t.accent (handled
/// at each call site via `arriving && conf == ArrivalConfidence.live`).
Color etaColor({
  required int etaSec,
  required ArrivalConfidence confidence,
  required LyneTheme t,
}) => t.fg;

// ─── Occupancy ─────────────────────────────────────────────────────────────

/// Shared crowding colour: seats → green, standing → amber, limited/unknown
/// → neutral grey. Used by OccupancyLabel (CrowdMeter has its own copy to
/// avoid a circular import).
///
/// Colours are HARDCODED (not sourced from t.soon/t.mid) so occupancy stays
/// green/amber after the 2.6.0 monochrome theme change. Mirrors the intent
/// of iOS Proximity.swift occupancyColor, where t.soon/t.mid are also the
/// source but iOS keeps them coloured — Android makes this explicit instead.
///   sea → system green   (seats available)
///   sda → system orange  (standing available)
///   lsd/null → t.dim     (limited/unknown — neutral grey)
Color occupancyColor(Load? load, LyneTheme t) {
  switch (load) {
    case Load.sea:
      return const Color(0xFF34C759); // system green
    case Load.sda:
      return const Color(0xFFFF9500); // system orange/amber
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
          Text(
            _text,
            style: t.mono(size, weight: FontWeight.w500, color: color),
          ),
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
