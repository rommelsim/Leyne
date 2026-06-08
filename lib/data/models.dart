// Domain models — the shapes used by the UI.
//
// Ported from legacy/ios-native/Lyne/Models.swift. The LTA-side DTOs and
// the LTA → domain mappers live in `lta_models.dart`. This file has no
// LTA imports so it's safe to use from anywhere in the UI layer.

/// Bus load level — three buckets matching LTA's SEA/SDA/LSD codes.
enum Load {
  /// Seats Available.
  sea('Seats'),

  /// Standing Available.
  sda('Standing'),

  /// Limited Standing Available — crowded.
  lsd('Crowded');

  const Load(this.label);
  final String label;
}

/// Bus body type.
enum Deck {
  dd('Double-deck'),
  sd('Single-deck'),
  bd('Bendy');

  const Deck(this.word);
  final String word;
}

/// One service at a stop with live arrival data.
class Service {
  Service({
    required this.no,
    required this.dest,
    required this.etaSec,
    required this.followingSec,
    required this.load,
    required this.wab,
    required this.deck,
    this.monitored = true,
    this.busLat,
    this.busLon,
    this.arrivalDate,
    this.followingDate,
    this.thirdDate,
  });

  /// Service number — '88', '410W', 'NR1', etc. Acts as the stable id.
  final String no;

  /// Destination stop name (resolved from DestinationCode via DataStore).
  final String dest;

  /// Seconds until next bus arrives. Recomputed from arrivalDate on each tick.
  final int etaSec;

  /// Seconds until the bus *after* the next one (NextBus2).
  final int followingSec;

  final Load load;

  /// Wheelchair-accessible bus (LTA's `Feature: WAB`).
  final bool wab;

  final Deck deck;

  /// True when the ETA comes from the bus's live GPS fix; false when LTA
  /// fell back to the static timetable (shown as an "≈ scheduled" estimate).
  final bool monitored;

  /// The next bus's live GPS position from LTA's NextBus feed, when present.
  /// Null when LTA reports no coordinate (timetable-only / no signal). Used
  /// to plot the bus on the map and to sort a stop's arrivals by distance.
  final double? busLat;
  final double? busLon;

  /// Absolute arrival instants — UI ticks use these to recompute etaSec
  /// against `DateTime.now()` for a smooth countdown.
  final DateTime? arrivalDate;
  final DateTime? followingDate;
  final DateTime? thirdDate;

  String get id => no;
}

/// A pinned card on the Home screen (user-pinned stop).
class CardModel {
  CardModel({
    required this.id,
    required this.label,
    required this.stopName,
    required this.stopCode,
    required this.walkMin,
    required this.services,
    this.initialSelectedNo,
  });

  final String id;
  final String label;
  final String stopName;
  final String stopCode;
  final int walkMin;
  final List<Service> services;

  /// When a card is opened by tapping a specific bus row from another screen.
  final String? initialSelectedNo;
}

/// One row in the Nearby list (also reused by postal-code radius search).
class NearbyStop {
  NearbyStop({
    required this.id,
    required this.stopName,
    required this.stopCode,
    required this.lat,
    required this.lon,
    required this.distanceM,
    required this.walkMin,
    required this.services,
  });

  final String id;
  final String stopName;
  final String stopCode;
  final double lat;
  final double lon;
  final int distanceM;
  final int walkMin;
  final List<Service> services;
}

/// Search query classifier output.
class DetectedKind {
  const DetectedKind(this.kind, this.label);
  final String kind;
  final String label;
}

// ─── ETA formatting (cards.jsx fmtETA) ─────────────────────────────────

/// Rendered ETA pieces. `big` is the headline, `small` is the unit, `live`
/// flips on the green/animated treatment in the UI for very-near buses.
class Eta {
  const Eta({required this.big, required this.small, required this.live});
  final String big;
  final String small;
  final bool live;
}

/// `<1 min` → "Arr / now", 0 → "Arr / now". Matches legacy iOS exactly.
Eta fmtEta(int sec) {
  if (sec <= 0) return const Eta(big: 'Arr', small: 'now', live: true);
  final m = sec ~/ 60;
  if (m == 0) return const Eta(big: 'Arr', small: 'now', live: true);
  return Eta(big: '$m', small: 'min', live: m <= 1);
}

/// '420m', '1.2km'. Same rounding as legacy fmtDistance.
String fmtDistance(int metres) =>
    metres < 1000 ? '${metres}m' : '${(metres / 1000).toStringAsFixed(1)}km';

// ─── Natural service-number ordering ───────────────────────────────────

/// Natural ("Finder"-style) comparison so bus numbers order the way riders
/// expect: 2 < 10 < 53 < 53M < 98 < 98A < 170 < NR7. Digit runs compare by
/// value; a shorter token sorts before its suffixed sibling ("53" < "53M");
/// digit runs sort before letter runs ("170" < "NR7"). Mirrors the iOS
/// `localizedStandardCompare` used on SoftStopView / SoftBusView.
int naturalCompare(String a, String b) {
  int ia = 0, ib = 0;
  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  while (ia < a.length && ib < b.length) {
    final ca = a.codeUnitAt(ia), cb = b.codeUnitAt(ib);
    if (isDigit(ca) && isDigit(cb)) {
      // Span both digit runs and compare them by numeric magnitude.
      var ja = ia, jb = ib;
      while (ja < a.length && isDigit(a.codeUnitAt(ja))) {
        ja++;
      }
      while (jb < b.length && isDigit(b.codeUnitAt(jb))) {
        jb++;
      }
      var sa = ia; // strip leading zeros for magnitude compare
      while (sa < ja - 1 && a.codeUnitAt(sa) == 0x30) {
        sa++;
      }
      var sb = ib;
      while (sb < jb - 1 && b.codeUnitAt(sb) == 0x30) {
        sb++;
      }
      final la = ja - sa, lb = jb - sb;
      if (la != lb) return la - lb; // more digits ⇒ larger number
      final cmp = a.substring(sa, ja).compareTo(b.substring(sb, jb));
      if (cmp != 0) return cmp;
      ia = ja;
      ib = jb;
    } else {
      if (ca != cb) return ca - cb; // '1'(0x31) < 'N'(0x4E) ⇒ digits first
      ia++;
      ib++;
    }
  }
  return (a.length - ia) - (b.length - ib);
}

// ─── Bus operating hours (BusRoutes WD/SAT/SUN first & last) ───────────

/// Minutes-since-midnight of an `HHMM` string. '0530' → 330.
int _minOfDay(String hhmm) =>
    (int.tryParse(hhmm.substring(0, 2)) ?? 0) * 60 +
    (int.tryParse(hhmm.substring(2)) ?? 0);

/// Format an `HHMM` bus time for display — '0905' → '09:05' (24h) or
/// '9:05 AM' (12h). 'use24h' matches the app-wide clock preference.
String fmtClock(String hhmm, {bool use24h = true}) {
  if (hhmm.length != 4) return hhmm;
  final h = (int.tryParse(hhmm.substring(0, 2)) ?? 0) % 24;
  final m = hhmm.substring(2);
  if (use24h) return '${h.toString().padLeft(2, '0')}:$m';
  final period = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $period';
}

/// True when the day's last bus has already departed, given the `first` and
/// `last` `HHMM` times and the current `now`. Handles routes whose last bus
/// runs past midnight (a `last` earlier than `first`, e.g. first 0530 /
/// last 0015).
bool lastBusGone(String first, String last, DateTime now) {
  final f = _minOfDay(first);
  var l = _minOfDay(last);
  if (l < f) l += 1440; // last bus runs past midnight
  var nowMin = now.hour * 60 + now.minute;
  // Small hours of a service that spans midnight: the current clock time
  // belongs to the previous service day — shift it onto the same scale.
  if (l >= 1440 && nowMin < f) nowMin += 1440;
  return nowMin > l;
}
