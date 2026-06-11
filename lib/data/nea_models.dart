// NEA / data.gov.sg weather response DTOs.
//
// Covers three endpoints used by WeatherStore:
//   • 2-hour forecast   — area name + lat/lon + short forecast text per area
//   • Air temperature   — station lat/lon + reading (°C)
//   • 24-hour forecast  — period-by-period general + time-of-day forecasts
//
// All parsing is hand-rolled (no code-gen) matching the pattern in lta_models.dart.
// Field names mirror the raw JSON keys exactly to make debugging against real
// responses straightforward.

/// Condition bucket — drives the monochrome backdrop gradient variant.
/// Derived from the NEA forecast text (not from a numeric code).
enum WeatherCondition {
  clear,
  cloudy,
  rain,
  night;

  /// Map the NEA 2-hour forecast description onto one of our buckets.
  /// NEA strings are title-case natural language, e.g. "Partly Cloudy",
  /// "Thundery Showers", "Heavy Rain", "Fair (Day)", "Fair & Warm".
  static WeatherCondition fromForecast(String text, {bool isNight = false}) {
    final lower = text.toLowerCase();
    if (lower.contains('thunder') ||
        lower.contains('rain') ||
        lower.contains('shower') ||
        lower.contains('drizzle')) {
      return WeatherCondition.rain;
    }
    if (lower.contains('cloudy') || lower.contains('overcast')) {
      return WeatherCondition.cloudy;
    }
    if (isNight) return WeatherCondition.night;
    return WeatherCondition.clear;
  }

  /// Human-readable label for the UI readout (e.g. "Thundery Showers" → "Showers").
  static String shortLabel(String rawForecast) {
    final lower = rawForecast.toLowerCase();
    if (lower.contains('thunder')) return 'Thundery';
    if (lower.contains('heavy rain')) return 'Heavy Rain';
    if (lower.contains('rain')) return 'Rainy';
    if (lower.contains('shower')) return 'Showers';
    if (lower.contains('drizzle')) return 'Drizzle';
    if (lower.contains('overcast')) return 'Overcast';
    if (lower.contains('cloudy')) return 'Cloudy';
    if (lower.contains('fair') && lower.contains('warm')) return 'Fair & Warm';
    if (lower.contains('fair')) return 'Fair';
    if (lower.contains('windy')) return 'Windy';
    if (lower.contains('hazy')) return 'Hazy';
    return rawForecast; // pass through anything we haven't mapped
  }
}

// ─── 2-hour forecast ──────────────────────────────────────────────────────────

class NeaAreaMetadata {
  const NeaAreaMetadata({
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String name;
  final double lat;
  final double lon;

  factory NeaAreaMetadata.fromJson(Map<String, dynamic> j) {
    final loc = j['label_location'] as Map<String, dynamic>? ?? {};
    return NeaAreaMetadata(
      name: j['name'] as String? ?? '',
      lat: (loc['latitude'] as num?)?.toDouble() ?? 0,
      lon: (loc['longitude'] as num?)?.toDouble() ?? 0,
    );
  }
}

class NeaAreaForecast {
  const NeaAreaForecast({required this.area, required this.forecast});

  final String area;
  final String forecast;

  factory NeaAreaForecast.fromJson(Map<String, dynamic> j) => NeaAreaForecast(
        area: j['area'] as String? ?? '',
        forecast: j['forecast'] as String? ?? '',
      );
}

class NeaTwoHourResponse {
  const NeaTwoHourResponse({
    required this.areaMetadata,
    required this.forecasts,
  });

  final List<NeaAreaMetadata> areaMetadata;

  /// One forecast entry per area at items[0].
  final List<NeaAreaForecast> forecasts;

  factory NeaTwoHourResponse.fromJson(Map<String, dynamic> j) {
    final meta = ((j['area_metadata'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NeaAreaMetadata.fromJson)
        .toList(growable: false);

    final items = (j['items'] as List?) ?? const [];
    final first = items.isEmpty ? null : items.first as Map<String, dynamic>?;
    final rawForecasts =
        ((first?['forecasts'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final forecasts =
        rawForecasts.map(NeaAreaForecast.fromJson).toList(growable: false);

    return NeaTwoHourResponse(areaMetadata: meta, forecasts: forecasts);
  }
}

// ─── Air temperature ──────────────────────────────────────────────────────────

class NeaWeatherStation {
  const NeaWeatherStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  factory NeaWeatherStation.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>? ?? {};
    return NeaWeatherStation(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      lat: (loc['latitude'] as num?)?.toDouble() ?? 0,
      lon: (loc['longitude'] as num?)?.toDouble() ?? 0,
    );
  }
}

class NeaStationReading {
  const NeaStationReading({required this.stationId, required this.value});

  final String stationId;
  final double value;

  factory NeaStationReading.fromJson(Map<String, dynamic> j) =>
      NeaStationReading(
        stationId: j['station_id'] as String? ?? '',
        value: (j['value'] as num?)?.toDouble() ?? 0,
      );
}

class NeaAirTemperatureResponse {
  const NeaAirTemperatureResponse({
    required this.stations,
    required this.readings,
  });

  final List<NeaWeatherStation> stations;
  final List<NeaStationReading> readings;

  factory NeaAirTemperatureResponse.fromJson(Map<String, dynamic> j) {
    final metadata = j['metadata'] as Map<String, dynamic>? ?? {};
    final stations = ((metadata['stations'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NeaWeatherStation.fromJson)
        .toList(growable: false);

    final items = (j['items'] as List?) ?? const [];
    final first = items.isEmpty ? null : items.first as Map<String, dynamic>?;
    final rawReadings =
        ((first?['readings'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final readings =
        rawReadings.map(NeaStationReading.fromJson).toList(growable: false);

    return NeaAirTemperatureResponse(stations: stations, readings: readings);
  }
}

// ─── 24-hour forecast (optional rain-hint enrichment) ────────────────────────

/// One time-of-day period from the 24h forecast. Contains a general forecast
/// text for the whole island, which we use to derive a time hint like "rain
/// this afternoon" when it's currently clear but rain is forecast within 8 h.
class Nea24hPeriod {
  const Nea24hPeriod({
    required this.startHour,
    required this.endHour,
    required this.forecastText,
  });

  final int startHour; // hour-of-day in SGT (0–23)
  final int endHour;
  final String forecastText;

  factory Nea24hPeriod.fromJson(Map<String, dynamic> j) {
    final time = j['time'] as Map<String, dynamic>? ?? {};
    final startStr = time['start'] as String? ?? '';
    final endStr = time['end'] as String? ?? '';
    return Nea24hPeriod(
      startHour: _parseHour(startStr),
      endHour: _parseHour(endStr),
      forecastText: j['forecast'] as String? ?? '',
    );
  }

  static int _parseHour(String iso) {
    // NEA returns ISO-8601 strings like "2026-06-10T06:00:00+08:00"
    try {
      return DateTime.parse(iso).toLocal().hour;
    } catch (_) {
      return 0;
    }
  }
}

class Nea24hResponse {
  const Nea24hResponse({required this.periods});

  final List<Nea24hPeriod> periods;

  factory Nea24hResponse.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List?) ?? const [];
    final first = items.isEmpty ? null : items.first as Map<String, dynamic>?;
    final rawPeriods =
        ((first?['periods'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Nea24hResponse(
      periods: rawPeriods.map(Nea24hPeriod.fromJson).toList(growable: false),
    );
  }
}

// ─── Domain model ─────────────────────────────────────────────────────────────

/// The resolved, display-ready weather snapshot for the user's location.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.tempC,
    required this.forecastText,
    required this.condition,
    this.rainHint,
    required this.fetchedAt,
  });

  /// Air temperature from the nearest station, °C.
  final double tempC;

  /// Short human label derived from the 2-hour forecast ("Cloudy", "Showers"…).
  final String forecastText;

  final WeatherCondition condition;

  /// Near-term rain hint, null when no rain is expected soon.
  /// e.g. "rain expected" or "rain this afternoon".
  final String? rainHint;

  final DateTime fetchedAt;

  int get tempRounded => tempC.round();

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 15);
}
