// LTA DataMall response DTOs + mappers to the domain models.
//
// Direct port of legacy/ios-native/Lyne/LTAModels.swift.
//
// We keep the LTA capitalised JSON keys (BusStopCode, ServiceNo …) inside
// `fromJson` constructors and expose Dart-idiomatic camelCase on the
// instance side. No json_serializable / code-gen — hand-rolled to keep the
// data layer dependency-free.

import 'dart:math' as math;
import 'models.dart';

// ─── Bus Arrival v3 ────────────────────────────────────────────

class LtaArrivalResponse {
  LtaArrivalResponse({required this.busStopCode, required this.services});

  final String busStopCode;
  final List<LtaArrivalService> services;

  factory LtaArrivalResponse.fromJson(Map<String, dynamic> j) =>
      LtaArrivalResponse(
        busStopCode: j['BusStopCode'] as String? ?? '',
        services: ((j['Services'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(LtaArrivalService.fromJson)
            .toList(),
      );
}

class LtaArrivalService {
  LtaArrivalService({
    required this.serviceNo,
    required this.operator_,
    required this.nextBus,
    required this.nextBus2,
    required this.nextBus3,
  });

  final String serviceNo;
  final String? operator_;
  final LtaNextBus nextBus;
  final LtaNextBus nextBus2;
  final LtaNextBus nextBus3;

  factory LtaArrivalService.fromJson(Map<String, dynamic> j) =>
      LtaArrivalService(
        serviceNo: j['ServiceNo'] as String? ?? '',
        operator_: j['Operator'] as String?,
        nextBus: LtaNextBus.fromJson(
            (j['NextBus'] as Map?)?.cast<String, dynamic>() ?? const {}),
        nextBus2: LtaNextBus.fromJson(
            (j['NextBus2'] as Map?)?.cast<String, dynamic>() ?? const {}),
        nextBus3: LtaNextBus.fromJson(
            (j['NextBus3'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  /// Build a domain Service. `destName` resolves DestinationCode → stop name.
  /// Matches legacy `toService(destName:)` exactly: if `nextBus2` has no
  /// arrival, the following ETA is `eta + 600s`.
  Service toService({required String destName, DateTime? now}) {
    final ref = now ?? DateTime.now();
    final eta = nextBus.arrivalDate == null
        ? 0
        : math.max(0, nextBus.arrivalDate!.difference(ref).inSeconds);
    final foll = nextBus2.arrivalDate == null
        ? eta + 600
        : math.max(0, nextBus2.arrivalDate!.difference(ref).inSeconds);
    return Service(
      no: serviceNo,
      dest: destName,
      etaSec: eta,
      followingSec: foll,
      load: _loadFromLta(nextBus.load),
      wab: (nextBus.feature ?? '').toUpperCase() == 'WAB',
      deck: _deckFromLta(nextBus.vehicleType),
      // LTA's Monitored flag: 1 = ETA derived from the bus's live GPS fix,
      // 0 = no GPS, ETA is just the timetable estimate (the root cause of
      // the "app said 30 min, bus came in 3" complaints). Treat an absent
      // value as monitored so we never cry wolf on missing data.
      monitored: (nextBus.monitored ?? 1) != 0,
      arrivalDate: nextBus.arrivalDate,
      followingDate: nextBus2.arrivalDate,
      thirdDate: nextBus3.arrivalDate,
    );
  }
}

class LtaNextBus {
  LtaNextBus({
    this.originCode,
    this.destinationCode,
    this.estimatedArrival,
    this.monitored,
    this.latitude,
    this.longitude,
    this.load,
    this.feature,
    this.vehicleType,
  });

  final String? originCode;
  final String? destinationCode;
  final String? estimatedArrival;

  /// LTA's `Monitored` flag — 1 when the ETA is computed from the bus's
  /// live GPS position, 0 when it falls back to the static timetable.
  final int? monitored;
  final String? latitude;
  final String? longitude;
  final String? load;
  final String? feature;
  final String? vehicleType;

  factory LtaNextBus.fromJson(Map<String, dynamic> j) => LtaNextBus(
        originCode: j['OriginCode'] as String?,
        destinationCode: j['DestinationCode'] as String?,
        estimatedArrival: j['EstimatedArrival'] as String?,
        monitored: (j['Monitored'] as num?)?.toInt(),
        latitude: j['Latitude'] as String?,
        longitude: j['Longitude'] as String?,
        load: j['Load'] as String?,
        feature: j['Feature'] as String?,
        vehicleType: j['Type'] as String?,
      );

  DateTime? get arrivalDate {
    final s = estimatedArrival;
    if (s == null || s.isEmpty) return null;
    return LtaDate.parse(s);
  }

  double? get lat => double.tryParse(latitude ?? '');
  double? get lon => double.tryParse(longitude ?? '');
  bool get hasData => arrivalDate != null;
}

// ─── Bulk reference datasets ───────────────────────────────────

class LtaBusStop {
  LtaBusStop({
    required this.busStopCode,
    required this.roadName,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  final String busStopCode;
  final String roadName;
  final String description;
  final double latitude;
  final double longitude;

  factory LtaBusStop.fromJson(Map<String, dynamic> j) => LtaBusStop(
        busStopCode: j['BusStopCode'] as String? ?? '',
        roadName: j['RoadName'] as String? ?? '',
        description: j['Description'] as String? ?? '',
        latitude: (j['Latitude'] as num?)?.toDouble() ?? 0,
        longitude: (j['Longitude'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'BusStopCode': busStopCode,
        'RoadName': roadName,
        'Description': description,
        'Latitude': latitude,
        'Longitude': longitude,
      };

  @override
  bool operator ==(Object other) =>
      other is LtaBusStop && other.busStopCode == busStopCode;
  @override
  int get hashCode => busStopCode.hashCode;
}

class LtaBusService {
  LtaBusService({
    required this.serviceNo,
    required this.operator_,
    required this.direction,
    required this.category,
    required this.originCode,
    required this.destinationCode,
    required this.loopDesc,
  });

  final String serviceNo;
  final String? operator_;
  final int direction;
  final String? category;
  final String? originCode;
  final String? destinationCode;
  final String? loopDesc;

  factory LtaBusService.fromJson(Map<String, dynamic> j) => LtaBusService(
        serviceNo: j['ServiceNo'] as String? ?? '',
        operator_: j['Operator'] as String?,
        direction: (j['Direction'] as num?)?.toInt() ?? 0,
        category: j['Category'] as String?,
        originCode: j['OriginCode'] as String?,
        destinationCode: j['DestinationCode'] as String?,
        loopDesc: j['LoopDesc'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'ServiceNo': serviceNo,
        'Operator': operator_,
        'Direction': direction,
        'Category': category,
        'OriginCode': originCode,
        'DestinationCode': destinationCode,
        'LoopDesc': loopDesc,
      };
}

class LtaBusRoute {
  LtaBusRoute({
    required this.serviceNo,
    required this.operator_,
    required this.direction,
    required this.stopSequence,
    required this.busStopCode,
    required this.distance,
    this.wdFirstBus,
    this.wdLastBus,
    this.satFirstBus,
    this.satLastBus,
    this.sunFirstBus,
    this.sunLastBus,
  });

  final String serviceNo;
  final String? operator_;
  final int direction;
  final int stopSequence;
  final String busStopCode;
  final double? distance;

  // First/last bus clock times at this stop, as `HHMM` strings ("0530",
  // "0015"). LTA emits "-" or an empty string when the service doesn't run
  // on that day-type; `_busTime` normalises both to null.
  final String? wdFirstBus;
  final String? wdLastBus;
  final String? satFirstBus;
  final String? satLastBus;
  final String? sunFirstBus;
  final String? sunLastBus;

  factory LtaBusRoute.fromJson(Map<String, dynamic> j) => LtaBusRoute(
        serviceNo: j['ServiceNo'] as String? ?? '',
        operator_: j['Operator'] as String?,
        direction: (j['Direction'] as num?)?.toInt() ?? 0,
        stopSequence: (j['StopSequence'] as num?)?.toInt() ?? 0,
        busStopCode: j['BusStopCode'] as String? ?? '',
        distance: (j['Distance'] as num?)?.toDouble(),
        wdFirstBus: _busTime(j['WD_FirstBus']),
        wdLastBus: _busTime(j['WD_LastBus']),
        satFirstBus: _busTime(j['SAT_FirstBus']),
        satLastBus: _busTime(j['SAT_LastBus']),
        sunFirstBus: _busTime(j['SUN_FirstBus']),
        sunLastBus: _busTime(j['SUN_LastBus']),
      );

  Map<String, dynamic> toJson() => {
        'ServiceNo': serviceNo,
        'Operator': operator_,
        'Direction': direction,
        'StopSequence': stopSequence,
        'BusStopCode': busStopCode,
        'Distance': distance,
        'WD_FirstBus': wdFirstBus,
        'WD_LastBus': wdLastBus,
        'SAT_FirstBus': satFirstBus,
        'SAT_LastBus': satLastBus,
        'SUN_FirstBus': sunFirstBus,
        'SUN_LastBus': sunLastBus,
      };
}

/// Normalise an LTA bus-time cell: a 4-digit `HHMM` string, or null when the
/// field is missing, blank, or the literal "-" that means "no service".
String? _busTime(Object? raw) {
  final s = (raw as String?)?.trim() ?? '';
  if (s.isEmpty || s == '-' || s.length != 4) return null;
  return s;
}

// ─── ISO-8601 (+08:00) date parsing ───────────────────────────
//
// LTA sometimes returns trailing-`Z` UTC, sometimes +08:00 local with or
// without fractional seconds. Dart's DateTime.parse accepts ISO-8601 with
// optional fractional seconds and a `Z` or `±HH:MM` offset, which covers
// every shape LTA emits. We return parsed-as-UTC-then-toLocal so timezone
// comparisons against `DateTime.now()` work both on device and in tests.

abstract class LtaDate {
  static DateTime? parse(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}

// ─── LTA → domain enum mappers (private to this file) ─────────

Load _loadFromLta(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'SDA':
      return Load.sda;
    case 'LSD':
      return Load.lsd;
    default:
      return Load.sea;
  }
}

Deck _deckFromLta(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'DD':
      return Deck.dd;
    case 'BD':
      return Deck.bd;
    default:
      return Deck.sd;
  }
}
