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

/// Ink for an arrival's ETA. Soon-ness is not colour-coded — times read as
/// uniform foreground ink; only a scheduled/ghost (unconfirmed) arrival dims
/// to faint, the whisper-quiet honesty cue used app-wide.
Color etaColor({
  required int etaSec,
  required ArrivalConfidence confidence,
  required LyneTheme t,
}) =>
    confidence == ArrivalConfidence.unconfirmed ? t.dim : t.fg;

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
