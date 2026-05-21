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
