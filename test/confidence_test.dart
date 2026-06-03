// Confidence system unit tests — Freshness.from and ArrivalConfidence.of.
//
// Uses the `now:` injection parameter on Freshness.from for full
// determinism (no wall-clock dependence). Mirrors the iOS
// ConfidenceTests.swift expectations.

import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/widgets/v2/confidence.dart';

void main() {
  // ─── Freshness.from ───────────────────────────────────────────
  group('Freshness.from', () {
    final anchor = DateTime(2026, 6, 3, 12, 0, 0); // deterministic "now"

    test('null lastRefresh → offline', () {
      expect(Freshness.from(null, now: anchor), Freshness.offline);
    });

    test('29 s ago → live (< 30 s threshold)', () {
      final last = anchor.subtract(const Duration(seconds: 29));
      expect(Freshness.from(last, now: anchor), Freshness.live);
    });

    test('exactly 30 s ago → stale (boundary: 30 s is NOT live)', () {
      final last = anchor.subtract(const Duration(seconds: 30));
      expect(Freshness.from(last, now: anchor), Freshness.stale);
    });

    test('299 s ago → stale (just under 5-min cutoff)', () {
      final last = anchor.subtract(const Duration(seconds: 299));
      expect(Freshness.from(last, now: anchor), Freshness.stale);
    });

    test('exactly 300 s ago → offline (boundary: 300 s is NOT stale)', () {
      final last = anchor.subtract(const Duration(seconds: 300));
      expect(Freshness.from(last, now: anchor), Freshness.offline);
    });

    test('0 s ago → live (just fetched)', () {
      expect(Freshness.from(anchor, now: anchor), Freshness.live);
    });
  });

  // ─── ArrivalConfidence.of — 2×3 matrix ───────────────────────
  // monitored × feed (live | stale | offline) = 6 cells.
  group('ArrivalConfidence.of', () {
    test('monitored=true + live feed → live', () {
      expect(
        ArrivalConfidence.of(monitored: true, feed: Freshness.live),
        ArrivalConfidence.live,
      );
    });

    test('monitored=true + stale feed → stale', () {
      expect(
        ArrivalConfidence.of(monitored: true, feed: Freshness.stale),
        ArrivalConfidence.stale,
      );
    });

    test('monitored=true + offline feed → stale (GPS data, just aged)', () {
      expect(
        ArrivalConfidence.of(monitored: true, feed: Freshness.offline),
        ArrivalConfidence.stale,
      );
    });

    test('monitored=false + live feed → unconfirmed (timetable regardless of freshness)', () {
      expect(
        ArrivalConfidence.of(monitored: false, feed: Freshness.live),
        ArrivalConfidence.unconfirmed,
      );
    });

    test('monitored=false + stale feed → unconfirmed', () {
      expect(
        ArrivalConfidence.of(monitored: false, feed: Freshness.stale),
        ArrivalConfidence.unconfirmed,
      );
    });

    test('monitored=false + offline feed → unconfirmed', () {
      expect(
        ArrivalConfidence.of(monitored: false, feed: Freshness.offline),
        ArrivalConfidence.unconfirmed,
      );
    });

    // ── Spot-checks: numeralOpacity and microcopy per level ──────

    test('live.numeralOpacity() == 1.0', () {
      expect(ArrivalConfidence.live.numeralOpacity(), 1.0);
    });

    test('stale.numeralOpacity() returns the stale parameter (default 0.5)', () {
      expect(ArrivalConfidence.stale.numeralOpacity(), 0.5);
      expect(ArrivalConfidence.stale.numeralOpacity(stale: 0.3), 0.3);
    });

    test('unconfirmed.numeralOpacity() == 0.42', () {
      expect(ArrivalConfidence.unconfirmed.numeralOpacity(), closeTo(0.42, 1e-9));
    });

    test('none.numeralOpacity() == 1.0 (em-dash uses full ink)', () {
      expect(ArrivalConfidence.none.numeralOpacity(), 1.0);
    });

    test('live.microcopy() with ageSec → "live · Ns ago"', () {
      expect(ArrivalConfidence.live.microcopy(ageSec: 5), 'live · 5s ago');
    });

    test('live.microcopy() without ageSec → "live"', () {
      expect(ArrivalConfidence.live.microcopy(), 'live');
    });

    test('stale.microcopy() with ageSec → "updated Ns ago"', () {
      expect(ArrivalConfidence.stale.microcopy(ageSec: 45), 'updated 45s ago');
    });

    test('unconfirmed.microcopy() → "scheduled · no live signal"', () {
      expect(ArrivalConfidence.unconfirmed.microcopy(), 'scheduled · no live signal');
    });

    test('none.microcopy() → "last bus gone"', () {
      expect(ArrivalConfidence.none.microcopy(), 'last bus gone');
    });
  });
}
