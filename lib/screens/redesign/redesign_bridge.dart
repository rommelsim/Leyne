// Live-data bridge for the SG Transit redesign (Flutter).
//
// Mirrors ios-native/Leyne/Redesign/RedesignBridge.swift: adapts the app's
// real LTA DataMall domain types (Service / NearbyStop / MrtStation) into the
// redesign's compact Rd* view-models, so the redesign renders genuine live data
// without rewriting every screen. No mock content here — everything flows from
// DataStore.shared.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/mrt_stations.dart';
import 'redesign_data.dart';
import 'redesign_theme.dart';

RdLoad rdLoad(Load l) => switch (l) {
      Load.sea => RdLoad.seats,
      Load.sda => RdLoad.standing,
      Load.lsd => RdLoad.packed,
    };

/// Whole-minute ETA label; "0" means arriving now.
String rdMinLabel(int etaSec) => '${((etaSec + 30) ~/ 60).clamp(0, 999)}';

RdArrival rdArrival(Service s) => RdArrival(
      route: s.no,
      dest: s.dest,
      load: rdLoad(s.load),
      min: rdMinLabel(s.etaSec),
      then: s.followingSec > 0 ? 'then ${((s.followingSec + 30) ~/ 60).clamp(1, 999)}' : null,
    );

RdStop rdStop(NearbyStop n) {
  final here = n.distanceM <= 40;
  return RdStop(
    name: n.stopName,
    code: n.stopCode,
    dist: here ? "You're at this stop" : '${n.walkMin} min walk · ${fmtDistance(n.distanceM)}',
    distShort: here ? 'You are here' : fmtDistance(n.distanceM),
    badge: here ? "YOU'RE HERE" : '${n.walkMin} MIN WALK',
    arrivals: n.services.map(rdArrival).toList(growable: false),
  );
}

/// MRT line code(s) for an interchange bus-stop description, or [] otherwise.
List<MrtCode> rdMrtBadges(String stopName) => resolveMrtStation(stopName)?.codes ?? const [];

/// Readable foreground for a line-coloured badge — dark ink on the light
/// (orange) Circle Line, white on everything else.
Color rdMrtBadgeFg(String code) {
  final prefix = (code.length >= 2 ? code.substring(0, 2) : code).toUpperCase();
  return (prefix == 'CC' || prefix == 'CE') ? const Color(0xFF38240A) : Colors.white;
}

/// Small line-coloured code chip(s) shown beside an interchange stop name
/// (item 3). Renders nothing when the stop isn't a recognised rail station.
class RdMrtBadgeRow extends StatelessWidget {
  const RdMrtBadgeRow({super.key, required this.stopName, this.size = 10});

  final String stopName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final codes = rdMrtBadges(stopName);
    if (codes.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in codes)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(6)),
              child: Text(c.code,
                  style: rdText(size: size, weight: FontWeight.w800, color: rdMrtBadgeFg(c.code))),
            ),
          ),
      ],
    );
  }
}
