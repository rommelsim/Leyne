// Tests for ForecastWindow — the pure windowing + timezone-safe extraction
// behind SoftMrtStationScreen's crowd forecast card.
//
// Regression coverage for the 2026-07-03 owner report: the MRT station
// screen's forecast slots showed times like "12:30pm" while the header's
// "Updated 8pm" stamp (~7:53pm actual) was correct. Root cause: LTA's
// PCDForecast `Start` timestamps carry an explicit "+08:00" offset, which
// Dart's `DateTime.parse` folds into a UTC-flagged `DateTime` — reading
// `.hour`/`.minute` straight off that yields the UTC wall-clock (an 8-hour
// miss for Singapore), not a mocked/hardcoded value.

import 'package:flutter_test/flutter_test.dart';
import 'package:lyne/data/data_store.dart' show CrowdLevel;
import 'package:lyne/data/forecast_window.dart';
import 'package:lyne/data/lta_models.dart';

LtaStationForecastInterval _iv(DateTime start, String level) =>
    LtaStationForecastInterval(start: start, crowdLevel: level);

void main() {
  group('timezone safety (the regression)', () {
    test('localStart is converted off the raw UTC-flagged parse result, not '
        'the raw instant', () {
      // LTA's real Start format: an ISO-8601 string with an explicit
      // "+08:00" offset (see ios-native/Leyne/LTAModels.swift's shape
      // comment). Dart's DateTime.parse marks the result isUtc: true.
      final raw = LtaDate.parse('2026-07-03T20:30:00+08:00')!;
      expect(
        raw.isUtc,
        isTrue,
        reason:
            'sanity-check of documented DateTime.parse behavior for an '
            'explicit-offset ISO string — if this ever flips, the whole '
            'premise of the bug (and this test) changes',
      );

      final points = ForecastWindow.build([
        _iv(raw, 'l'),
      ], now: raw.subtract(const Duration(minutes: 10)));

      expect(points, hasLength(1));
      // The bug: reading .hour/.minute off `raw` directly returns the UTC
      // wall-clock (12:30), not Singapore's (20:30). Asserting isUtc: false
      // here catches a regression to "localStart: iv.start" regardless of
      // which timezone the test happens to run in — .toLocal() always
      // clears the UTC flag; a raw parsed-with-offset DateTime never does.
      expect(points.single.localStart.isUtc, isFalse);
      // And it must still be the same instant — just relabelled, not
      // shifted to a different moment in time.
      expect(points.single.localStart.isAtSameMomentAs(raw), isTrue);
    });

    test(
      'a UTC-flagged instant passed straight through remains recoverable',
      () {
        // Belt-and-braces: build() should tolerate an interval whose `start`
        // is already `.toLocal()`d (e.g. from a future caller) without double
        // conversion breaking anything — .toLocal() on a local DateTime is a
        // no-op in Dart.
        final local = DateTime(2026, 7, 3, 20, 30);
        final points = ForecastWindow.build([_iv(local, 'm')], now: local);
        expect(points.single.localStart, local);
      },
    );
  });

  group('windowing (anchored on "now")', () {
    test('marks the bracketing slot as isNow, anchoring the front of the '
        'window, and keeps the series ordered', () {
      final base = DateTime(2026, 7, 3, 18, 0);
      final intervals = [
        for (var i = 0; i < 8; i++)
          _iv(base.add(Duration(minutes: 30 * i)), 'l'),
      ]..shuffle(); // order shouldn't matter — build() sorts internally.

      // "now" sits inside the 18:30–19:00 slot (bracketed by index 1).
      final now = base.add(const Duration(minutes: 45));
      final points = ForecastWindow.build(intervals, now: now);
      final expectedNow = base.add(const Duration(minutes: 30));

      final nowPoints = points.where((p) => p.isNow).toList();
      expect(nowPoints, hasLength(1));
      expect(nowPoints.single.localStart, expectedNow);

      // The bracketing ("last past interval") slot anchors the front of the
      // window — mirrors WSMrtStationView.swift loadForecast()'s "from the
      // last past interval through the next five".
      expect(points.first.localStart, expectedNow);
      expect(points.first.isNow, isTrue);

      // Sorted ascending regardless of input order.
      for (var i = 1; i < points.length; i++) {
        expect(points[i].localStart.isAfter(points[i - 1].localStart), isTrue);
      }
    });

    test('caps the window at windowSize entries', () {
      final base = DateTime(2026, 7, 3, 0, 0);
      final intervals = [
        for (var i = 0; i < 20; i++)
          _iv(base.add(Duration(minutes: 30 * i)), 'l'),
      ];
      final now = base.add(const Duration(hours: 2)); // slot index 4
      final points = ForecastWindow.build(intervals, now: now);
      expect(points, hasLength(6));
    });

    test('still anchors the final slot while now is inside its half-hour '
        'window', () {
      final base = DateTime(2026, 7, 3, 6, 0);
      final intervals = [
        for (var i = 0; i < 4; i++)
          _iv(base.add(Duration(minutes: 30 * i)), 'l'),
      ];
      // 10 minutes into the last slot (07:30–08:00) — service still running.
      final now = base.add(const Duration(minutes: 30 * 3 + 10));
      final points = ForecastWindow.build(intervals, now: now);
      expect(points, isNotEmpty);
      expect(points.last.localStart, intervals.last.start);
      expect(points.last.isNow, isTrue);
    });

    test('yields an EMPTY window once now is past the final slot\'s end — a '
        'closed station must not show a stale tail flagged "now"', () {
      final base = DateTime(2026, 7, 3, 6, 0);
      final intervals = [
        for (var i = 0; i < 4; i++)
          _iv(base.add(Duration(minutes: 30 * i)), 'l'),
      ];
      final now = base.add(const Duration(hours: 5)); // well past the series
      expect(ForecastWindow.build(intervals, now: now), isEmpty);
    });

    test('empty intervals yields an empty window', () {
      expect(ForecastWindow.build(const [], now: DateTime.now()), isEmpty);
    });

    test('carries the crowd level through untouched', () {
      final base = DateTime(2026, 7, 3, 12, 0);
      final points = ForecastWindow.build([
        _iv(base, 'h'),
        _iv(base.add(const Duration(minutes: 30)), 'm'),
      ], now: base);
      expect(points.first.level, CrowdLevel.high);
      expect(points[1].level, CrowdLevel.moderate);
    });
  });
}
