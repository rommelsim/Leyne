// Regression tests for the Bus-view route-progress math (BusProgress).
//
// These pin the five bugs fixed on 2026-06-06:
//   1/3/4 — pin vs. text disagreement: the bus index must be grounded in the
//           real GPS fix (nearest stop, clamped to your stop), and only fall
//           back to the ETA estimate when there is no fix.
//   2     — the timeline must run to the terminus (lead is 2 before the bus).
//   5     — the green connector marks only track the bus has covered; the
//           boarding stop stays grey and the green ends exactly at the bus.
//
// Mirrors ios-native/LeyneTests/BusProgressTests.swift.

import 'package:flutter_test/flutter_test.dart';
import 'package:lyne/data/bus_progress.dart';
import 'package:lyne/widgets/v2/route_timeline.dart';

void main() {
  group('busIndex — GPS-grounded with ETA fallback (bugs 1/3/4)', () {
    test('GPS nearest is clamped to your stop', () {
      // A fix whose nearest stop is past you never renders past you.
      expect(
        BusProgress.busIndex(
            youIndex: 5, gpsNearest: 9, etaSec: 0, elapsedSec: 0),
        5,
      );
    });

    test('GPS nearest beats the ETA', () {
      // Real position (stop 3) wins even when the ETA says "arriving" (eta 0,
      // which alone would place the bus at your stop). This is the "arriving
      // now but the bus is 1.3 km away" bug.
      expect(
        BusProgress.busIndex(
            youIndex: 5, gpsNearest: 3, etaSec: 0, elapsedSec: 0),
        3,
      );
    });

    test('no fix falls back to the ETA estimate (~90s/stop)', () {
      // 270 s ≈ 3 stops back from stop 5 → stop 2.
      expect(
        BusProgress.busIndex(
            youIndex: 5, gpsNearest: null, etaSec: 270, elapsedSec: 0),
        2,
      );
      // Arriving → at your stop.
      expect(
        BusProgress.busIndex(
            youIndex: 5, gpsNearest: null, etaSec: 0, elapsedSec: 0),
        5,
      );
    });

    test('elapsed ages the ETA forward', () {
      // 270 s ETA, 180 s elapsed → ~90 s left → 1 stop back → stop 4.
      expect(
        BusProgress.busIndex(
            youIndex: 5, gpsNearest: null, etaSec: 270, elapsedSec: 180),
        4,
      );
    });

    test('origin returns 0', () {
      expect(
        BusProgress.busIndex(
            youIndex: 0, gpsNearest: null, etaSec: 999, elapsedSec: 0),
        0,
      );
    });
  });

  group('nearestIndex', () {
    final stops = <({double lat, double lon})>[
      (lat: 1.30, lon: 103.80),
      (lat: 1.31, lon: 103.80),
      (lat: 1.32, lon: 103.80),
    ];

    test('snaps to the closest stop', () {
      expect(BusProgress.nearestIndex(stops, (lat: 1.319, lon: 103.80)), 2);
      expect(BusProgress.nearestIndex(stops, (lat: 1.301, lon: 103.80)), 0);
    });

    test('empty list returns null', () {
      expect(BusProgress.nearestIndex(const [], (lat: 1.3, lon: 103.8)), isNull);
    });
  });

  group('timelineLead — segment reaches the terminus (bug 2)', () {
    test('starts two stops before the bus', () {
      expect(
        BusProgress.timelineLead(busIndex: 6, youIndex: 10, stopsCount: 30),
        4,
      );
    });

    test('falls back to your stop when the bus is unknown', () {
      expect(
        BusProgress.timelineLead(busIndex: null, youIndex: 10, stopsCount: 30),
        8,
      );
    });

    test('never negative', () {
      expect(
        BusProgress.timelineLead(busIndex: 1, youIndex: 1, stopsCount: 30),
        0,
      );
    });
  });

  group('stopState', () {
    test('here at the bus, board at your stop, past before, next after', () {
      expect(
        BusProgress.stopState(
            idx: 3, busIndex: 3, youIndex: 6, canMarkBoard: true),
        SoftRouteStopState.here,
      );
      expect(
        BusProgress.stopState(
            idx: 6, busIndex: 3, youIndex: 6, canMarkBoard: true),
        SoftRouteStopState.board,
      );
      expect(
        BusProgress.stopState(
            idx: 1, busIndex: 3, youIndex: 6, canMarkBoard: true),
        SoftRouteStopState.past,
      );
      expect(
        BusProgress.stopState(
            idx: 8, busIndex: 3, youIndex: 6, canMarkBoard: true),
        SoftRouteStopState.next,
      );
    });

    test('board suppressed in full-route (bus search) mode', () {
      expect(
        BusProgress.stopState(
            idx: 6, busIndex: 3, youIndex: 6, canMarkBoard: false),
        SoftRouteStopState.next,
      );
    });
  });

  group('connector colours — green = track covered (bug 5)', () {
    test('green only through the bus', () {
      expect(BusProgress.connectorIsGreen(SoftRouteStopState.past), isTrue);
      expect(BusProgress.connectorIsGreen(SoftRouteStopState.here), isTrue);
      // No detached green segment at your stop.
      expect(BusProgress.connectorIsGreen(SoftRouteStopState.board), isFalse);
      expect(BusProgress.connectorIsGreen(SoftRouteStopState.next), isFalse);
      expect(BusProgress.connectorIsGreen(SoftRouteStopState.alight), isFalse);
    });

    test('bus row lower half greys so green ends at the bus', () {
      expect(BusProgress.lowerConnectorIsGreen(SoftRouteStopState.here), isFalse);
      expect(BusProgress.lowerConnectorIsGreen(SoftRouteStopState.past), isTrue);
    });
  });
}
