// BusProgress — pure route-progress math for the Bus view, factored out of
// SoftBusScreen so it can be unit-tested without a widget host.
//
// These are the rules behind "where is the bus on its route", which the map
// pin, the approaching card, the live-position callout and the route timeline
// all share — so they can never disagree. (That disagreement was the class of
// bug that drew a pin 1.3 km away while the text claimed "0 stops away".)
//
// Mirrors ios-native/Leyne/BusProgress.swift — keep the two in step.

import 'geo.dart';
import '../widgets/v2/route_timeline.dart';

class BusProgress {
  const BusProgress._();

  /// Index of the route stop nearest to [c], or null for an empty list.
  static int? nearestIndex(
      List<({double lat, double lon})> stops, ({double lat, double lon}) c) {
    if (stops.isEmpty) return null;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < stops.length; i++) {
      final d = haversine(stops[i].lat, stops[i].lon, c.lat, c.lon);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// The bus's route index. Prefer the GPS-derived nearest stop (clamped to
  /// your stop, since the approaching bus is always behind you); otherwise
  /// estimate from the ETA (~90 s/stop, aged by [elapsedSec]). Returns 0 at
  /// the origin ([youIndex] <= 0).
  static int busIndex({
    required int youIndex,
    int? gpsNearest,
    required int etaSec,
    required double elapsedSec,
  }) {
    if (youIndex <= 0) return 0;
    if (gpsNearest != null) return gpsNearest.clamp(0, youIndex);
    final eta = (etaSec - elapsedSec).clamp(0.0, double.infinity);
    final back = (eta / 90.0).clamp(0.0, youIndex.toDouble());
    return (youIndex - back).round().clamp(0, youIndex);
  }

  /// First stop kept in the timeline: two before the bus (or your stop when the
  /// bus is unknown), clamped. The segment then runs to the terminus so the
  /// route visibly leads to its destination instead of stopping at you.
  static int timelineLead({
    int? busIndex,
    required int youIndex,
    required int stopsCount,
  }) {
    if (stopsCount <= 0) return 0;
    final pivot =
        busIndex == null ? youIndex : (busIndex < youIndex ? busIndex : youIndex);
    return (pivot - 2).clamp(0, stopsCount - 1);
  }

  /// State of stop [idx] given the bus + boarding positions. [canMarkBoard] is
  /// false in full-route (bus search) mode, where there is no your-stop.
  static SoftRouteStopState stopState({
    required int idx,
    int? busIndex,
    required int youIndex,
    required bool canMarkBoard,
  }) {
    if (busIndex != null && idx == busIndex) return SoftRouteStopState.here;
    if (canMarkBoard && idx == youIndex) return SoftRouteStopState.board;
    if (idx < (busIndex ?? -1)) return SoftRouteStopState.past;
    return SoftRouteStopState.next;
  }

  /// Whether a stop's connector is "green" — track the bus has already covered.
  /// Only passed stops and the bus's own stop; the boarding/alight stop is
  /// ahead of the bus, so it stays grey (no detached green segment).
  static bool connectorIsGreen(SoftRouteStopState s) =>
      s == SoftRouteStopState.past || s == SoftRouteStopState.here;

  /// The bus row's lower half greys out — the bus hasn't travelled past its own
  /// stop — so the green trail ends exactly at the bus.
  static bool lowerConnectorIsGreen(SoftRouteStopState s) =>
      s != SoftRouteStopState.here && connectorIsGreen(s);
}
