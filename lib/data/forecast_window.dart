// ForecastWindow — pure windowing + timezone-safe extraction for a station's
// PCDForecast series. Factored out of SoftMrtStationScreen so it can be unit
// tested without a widget host (see test/forecast_window_test.dart) and so
// the timezone fix below lives in exactly one place.
//
// Windowing mirrors ios-native/Leyne/WhereSia/WSMrtStationView.swift
// loadForecast() exactly: the visible slice is one interval back from "now"
// (so the active slot anchors the chart) through the next several.
//
// Timezone bug this guards against (owner-reported 2026-07-03):
// LTA's PCDForecast `Start` timestamps carry an explicit "+08:00" offset,
// e.g. "2025-01-01T20:30:00+08:00" (see the shape comment atop
// ios-native/Leyne/LTAModels.swift). Dart's `DateTime.parse` folds any
// string with an explicit numeric offset into a UTC-flagged `DateTime` —
// its `.hour`/`.minute` then read the UTC wall-clock, not Singapore's. A
// 20:30 SGT slot reads back as "12:30" (an 8-hour miss — exactly the gap
// between an "Updated 8pm" stamp and forecast bars labelled "12:30pm").
// Swift's `Date` has no such footgun: it's always a bare instant, and
// `DateFormatter` renders in the device's local zone by default, so the iOS
// reference never hit this. [ForecastWindowPoint.localStart] applies
// `.toLocal()` once, here, so every caller gets a safe wall-clock value —
// do not read `.hour`/`.minute` off a raw `LtaStationForecastInterval.start`
// without going through this (or your own `.toLocal()`) first.

import 'data_store.dart' show CrowdLevel, StationCrowd;
import 'lta_models.dart' show LtaStationForecastInterval;

/// One slot in the visible forecast window.
class ForecastWindowPoint {
  const ForecastWindowPoint({
    required this.localStart,
    required this.level,
    required this.isNow,
  });

  /// This slot's start time, converted to the device's local timezone.
  /// Safe to read `.hour`/`.minute` directly.
  final DateTime localStart;

  final CrowdLevel level;

  /// True for the one slot whose `[start, nextStart)` window contains the
  /// `now` the window was built with.
  final bool isNow;
}

/// Pure forecast-window selector — no Flutter/BuildContext dependency.
abstract class ForecastWindow {
  const ForecastWindow._();

  /// Builds the visible window from a station's raw forecast intervals,
  /// anchored on [now]: one slot back from the first upcoming interval
  /// (`Start >= now`) through the next [windowSize] - 1 slots.
  ///
  /// Returns an EMPTY window once [now] is past the end of the final slot
  /// (start + 30 min) — the service day is over, and the previous "always
  /// show the tail" fallback flagged the last slot as "now" on a closed
  /// station (owner-reported on iOS, 2026-07-04; fixed on both platforms).
  /// While [now] is still inside the final slot, that slot anchors the
  /// window as before.
  static List<ForecastWindowPoint> build(
    List<LtaStationForecastInterval> intervals, {
    required DateTime now,
    int windowSize = 6,
  }) {
    if (intervals.isEmpty) return const [];
    final sorted = [...intervals]..sort((a, b) => a.start.compareTo(b.start));

    var upcomingIdx = sorted.indexWhere((iv) => !iv.start.isBefore(now));
    if (upcomingIdx == -1) {
      // Whole series is in the past. Anchor on the final slot only while
      // its half-hour window still covers `now`; afterwards the station is
      // closed (or about to be) — show nothing rather than a stale tail.
      final lastEnd = sorted.last.start.add(const Duration(minutes: 30));
      if (!now.isBefore(lastEnd)) return const [];
      upcomingIdx = sorted.length - 1;
    }
    final start = (upcomingIdx - 1).clamp(0, sorted.length - 1);
    final end = (start + windowSize).clamp(start, sorted.length);

    final points = <ForecastWindowPoint>[];
    for (var i = start; i < end; i++) {
      final iv = sorted[i];
      final nextStart = i + 1 < sorted.length ? sorted[i + 1].start : null;
      final isNow =
          !iv.start.isAfter(now) &&
          (nextStart == null || nextStart.isAfter(now));
      points.add(
        ForecastWindowPoint(
          localStart: iv.start.toLocal(),
          level: StationCrowd.levelFrom(iv.crowdLevel),
          isNow: isNow,
        ),
      );
    }
    return points;
  }
}
