// Tests for AlertTiming — the timing + copy rules behind the two alert types.
// Mirrors ios-native/LeyneTests/AlertTimingTests.swift.

import 'package:flutter_test/flutter_test.dart';
import 'package:lyne/data/alert_timing.dart';

void main() {
  group('leadOptions / defaults', () {
    test('arrival has no 30-min option, destination does', () {
      expect(AlertTiming.leadOptions(AlertKind.arrival), [1, 2, 5, 10, 15]);
      expect(
          AlertTiming.leadOptions(AlertKind.destination), [1, 2, 5, 10, 15, 30]);
    });
    test('defaults match the mockup (arrival 5, destination 10)', () {
      expect(AlertTiming.defaultLead(AlertKind.arrival), 5);
      expect(AlertTiming.defaultLead(AlertKind.destination), 10);
    });
  });

  group('arrivalFireAt', () {
    test('fires lead minutes before the ETA', () {
      final eta = DateTime(2026, 6, 10, 9, 41);
      expect(AlertTiming.arrivalFireAt(eta, 5), DateTime(2026, 6, 10, 9, 36));
      expect(AlertTiming.arrivalFireAt(eta, 1), DateTime(2026, 6, 10, 9, 40));
    });
  });

  group('destinationFireAt', () {
    test('boarding ETA + segments*90s − lead', () {
      final board = DateTime(2026, 6, 10, 9, 30);
      // 4 segments * 90s = 6 min → dest ETA 9:36; lead 2 min → 9:34.
      expect(
        AlertTiming.destinationFireAt(
            arrivalAtBoard: board, boardIndex: 2, destIndex: 6, leadMinutes: 2),
        DateTime(2026, 6, 10, 9, 34),
      );
    });
    test('clamps a negative segment count to zero', () {
      final board = DateTime(2026, 6, 10, 9, 30);
      expect(
        AlertTiming.destinationFireAt(
            arrivalAtBoard: board, boardIndex: 6, destIndex: 2, leadMinutes: 0),
        board,
      );
    });
  });

  group('notification copy', () {
    test('arrival', () {
      expect(AlertTiming.arrivalTitle('153'), 'Bus 153 arriving soon');
      expect(AlertTiming.arrivalBody('Farrer Rd Stn Exit B', 5),
          'Farrer Rd Stn Exit B · 5 min to arrival');
      expect(AlertTiming.arrivalBody('Farrer Rd Stn Exit B', 1),
          'Farrer Rd Stn Exit B · Arriving now');
    });
    test('destination', () {
      expect(AlertTiming.destinationTitle(), 'Your stop is next');
      expect(AlertTiming.destinationBody('Hougang Ctrl Int', 10),
          'Hougang Ctrl Int · Arriving in 10 min');
    });
    test('sheet summary', () {
      expect(
        AlertTiming.summary(
            kind: AlertKind.arrival,
            busNo: '153',
            stopName: 'Farrer Rd Stn Exit B',
            leadMinutes: 5),
        "We'll notify you 5 min before Bus 153 arrives at Farrer Rd Stn Exit B.",
      );
      expect(
        AlertTiming.summary(
            kind: AlertKind.destination,
            busNo: '165',
            stopName: 'Hougang Ctrl Int',
            leadMinutes: 10),
        "We'll notify you 10 min before Bus 165 reaches Hougang Ctrl Int.",
      );
    });
    test('labels', () {
      expect(AlertTiming.leadLabel(1), 'When bus is arriving');
      expect(AlertTiming.leadLabel(5), '5 minutes before');
      expect(AlertTiming.leadRowSubtitle(5), '5 min before arrival');
      expect(AlertTiming.leadRowSubtitle(1), 'When arriving');
    });
  });
}
