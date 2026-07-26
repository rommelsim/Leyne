// Tests for resolveMrtStation/lineColorFor — the name-based MRT/LRT station
// resolver. (stopServesMRT and its tests were removed 2026-07-25 alongside
// the dead `widgets/v2/route_timeline.dart` `RouteTimeline` widget — that
// widget was its only caller anywhere in the app.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyne/data/mrt_stations.dart';

void main() {
  group('resolveMrtStation', () {
    test('resolves a simple single-line station', () {
      final s = resolveMrtStation('Clementi Stn');
      expect(s, isNotNull);
      expect(s!.name, 'Clementi');
      expect(s.codes.map((c) => c.code), ['EW23']);
    });

    test('handles directional prefix and exit suffix', () {
      expect(resolveMrtStation('Opp Clementi Stn')?.name, 'Clementi');
      expect(resolveMrtStation('Bishan Stn Exit C')?.name, 'Bishan');
    });

    test('expands LTA abbreviations (Rd, Bt)', () {
      // The screenshot example: "Farrer Rd Stn" → Farrer Road (CC20).
      final farrer = resolveMrtStation('Farrer Rd Stn Exit A');
      expect(farrer?.name, 'Farrer Road');
      expect(farrer?.codes.single.code, 'CC20');
      expect(resolveMrtStation('Bt Batok Stn')?.name, 'Bukit Batok');
    });

    test('returns every code for an interchange', () {
      final je = resolveMrtStation('Jurong East Stn');
      expect(je?.name, 'Jurong East');
      expect(je?.codes.map((c) => c.code), ['EW24', 'NS1']);
    });

    test('returns null for non-station and unknown-station names', () {
      expect(resolveMrtStation('Opp Blk 2'), isNull); // not a station
      expect(resolveMrtStation('Clementi Int'), isNull); // no "Stn" token
      expect(resolveMrtStation('Nonexistent Stn'), isNull); // unknown
    });

    test('line colours come from the code prefix', () {
      expect(lineColorFor('EW23'), const Color(0xFF009645)); // green
      expect(lineColorFor('NS1'), const Color(0xFFD42E12)); // red
      expect(lineColorFor('CC20'), const Color(0xFFFA9E0D)); // orange
    });
  });
}
