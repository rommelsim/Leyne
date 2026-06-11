// Unit tests for NEA weather parsing + nearest-area / nearest-station selection.
//
// Mirrors the pattern in data_layer_test.dart:
//   • All JSON fixtures are inlined — no network calls.
//   • Uses WeatherStore's static helpers directly (package-private via test/).
//
// Coverage:
//   1. NeaTwoHourResponse — parse area_metadata + items[0].forecasts
//   2. NeaAirTemperatureResponse — parse metadata.stations + items[0].readings
//   3. Nea24hResponse — parse items[0].periods with ISO-8601 time strings
//   4. WeatherCondition.fromForecast — all buckets (clear/cloudy/rain/night)
//   5. WeatherCondition.shortLabel — NEA label compression
//   6. Nearest-area selection (haversine tie-breaker)
//   7. Nearest-temperature-station selection
//   8. Rain hint derivation — no-hint / current-rain / upcoming-rain paths
//   9. Graceful degradation — empty metadata, missing readings

import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/data/nea_models.dart';
import 'package:lyne/data/nea_service.dart';
import 'package:lyne/data/weather_store.dart';

// ─── Shared JSON fixtures ─────────────────────────────────────────────────────

const _twoHourJson = {
  'area_metadata': [
    {
      'name': 'Bishan',
      'label_location': {'latitude': 1.3521, 'longitude': 103.8478},
    },
    {
      'name': 'Ang Mo Kio',
      'label_location': {'latitude': 1.3691, 'longitude': 103.8454},
    },
    {
      'name': 'Jurong West',
      'label_location': {'latitude': 1.3404, 'longitude': 103.7090},
    },
  ],
  'items': [
    {
      'forecasts': [
        {'area': 'Bishan', 'forecast': 'Partly Cloudy'},
        {'area': 'Ang Mo Kio', 'forecast': 'Thundery Showers'},
        {'area': 'Jurong West', 'forecast': 'Fair (Day)'},
      ],
    },
  ],
};

const _temperatureJson = {
  'metadata': {
    'stations': [
      {
        'id': 'S50',
        'name': 'Clementi Road',
        'location': {'latitude': 1.3337, 'longitude': 103.7768},
      },
      {
        'id': 'S24',
        'name': 'Upper Thomson Road',
        'location': {'latitude': 1.3678, 'longitude': 103.8292},
      },
      {
        'id': 'S43',
        'name': 'Kim Chuan Road',
        'location': {'latitude': 1.3399, 'longitude': 103.8878},
      },
    ],
  },
  'items': [
    {
      'readings': [
        {'station_id': 'S50', 'value': 30.2},
        {'station_id': 'S24', 'value': 28.8},
        {'station_id': 'S43', 'value': 31.1},
      ],
    },
  ],
};

// 24h forecast with three named-hour periods (morning/afternoon/evening).
// Times use simplified ISO strings that DateTime.parse can handle.
const _twentyFourJson = {
  'items': [
    {
      'periods': [
        {
          'time': {
            'start': '2026-06-10T06:00:00+08:00',
            'end': '2026-06-10T12:00:00+08:00',
          },
          'forecast': 'Partly Cloudy',
        },
        {
          'time': {
            'start': '2026-06-10T12:00:00+08:00',
            'end': '2026-06-10T18:00:00+08:00',
          },
          'forecast': 'Heavy Thundery Showers',
        },
        {
          'time': {
            'start': '2026-06-10T18:00:00+08:00',
            'end': '2026-06-10T24:00:00+08:00',
          },
          'forecast': 'Fair',
        },
      ],
    },
  ],
};

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ─── NeaTwoHourResponse parsing ───────────────────────────────────────────

  group('NeaTwoHourResponse.fromJson', () {
    test('parses area_metadata correctly', () {
      final resp =
          NeaTwoHourResponse.fromJson(_twoHourJson as Map<String, dynamic>);
      expect(resp.areaMetadata.length, 3);
      final bishan = resp.areaMetadata.first;
      expect(bishan.name, 'Bishan');
      expect(bishan.lat, closeTo(1.3521, 0.0001));
      expect(bishan.lon, closeTo(103.8478, 0.0001));
    });

    test('parses items[0].forecasts correctly', () {
      final resp =
          NeaTwoHourResponse.fromJson(_twoHourJson as Map<String, dynamic>);
      expect(resp.forecasts.length, 3);
      final amk = resp.forecasts.firstWhere((f) => f.area == 'Ang Mo Kio');
      expect(amk.forecast, 'Thundery Showers');
    });

    test('graceful on empty response', () {
      final resp = NeaTwoHourResponse.fromJson({});
      expect(resp.areaMetadata, isEmpty);
      expect(resp.forecasts, isEmpty);
    });

    test('graceful when items list is empty', () {
      final resp = NeaTwoHourResponse.fromJson({
        'area_metadata': [],
        'items': [],
      });
      expect(resp.forecasts, isEmpty);
    });
  });

  // ─── NeaAirTemperatureResponse parsing ────────────────────────────────────

  group('NeaAirTemperatureResponse.fromJson', () {
    test('parses stations and readings', () {
      final resp = NeaAirTemperatureResponse.fromJson(
          _temperatureJson as Map<String, dynamic>);
      expect(resp.stations.length, 3);
      expect(resp.readings.length, 3);

      final s50 = resp.stations.firstWhere((s) => s.id == 'S50');
      expect(s50.name, 'Clementi Road');
      expect(s50.lat, closeTo(1.3337, 0.0001));

      final r50 =
          resp.readings.firstWhere((r) => r.stationId == 'S50');
      expect(r50.value, closeTo(30.2, 0.01));
    });

    test('graceful on empty response', () {
      final resp = NeaAirTemperatureResponse.fromJson({});
      expect(resp.stations, isEmpty);
      expect(resp.readings, isEmpty);
    });
  });

  // ─── Nea24hResponse parsing ───────────────────────────────────────────────

  group('Nea24hResponse.fromJson', () {
    test('parses three periods with correct start hours (SGT)', () {
      final resp = Nea24hResponse.fromJson(
          _twentyFourJson as Map<String, dynamic>);
      expect(resp.periods.length, 3);
      // Morning period: 2026-06-10T06:00:00+08:00 → local hour 6
      expect(resp.periods[0].startHour, 6);
      // Afternoon: hour 12
      expect(resp.periods[1].startHour, 12);
      // Evening: hour 18
      expect(resp.periods[2].startHour, 18);
    });

    test('parses forecast text', () {
      final resp = Nea24hResponse.fromJson(
          _twentyFourJson as Map<String, dynamic>);
      expect(resp.periods[1].forecastText, 'Heavy Thundery Showers');
    });

    test('graceful on empty items', () {
      final resp = Nea24hResponse.fromJson({'items': []});
      expect(resp.periods, isEmpty);
    });
  });

  // ─── WeatherCondition.fromForecast ────────────────────────────────────────

  group('WeatherCondition.fromForecast', () {
    test('rain keywords → rain', () {
      expect(WeatherCondition.fromForecast('Light Rain'),
          WeatherCondition.rain);
      expect(WeatherCondition.fromForecast('Heavy Thundery Showers'),
          WeatherCondition.rain);
      expect(WeatherCondition.fromForecast('Drizzle'), WeatherCondition.rain);
      expect(WeatherCondition.fromForecast('Moderate Rain'),
          WeatherCondition.rain);
    });

    test('cloudy keywords → cloudy', () {
      expect(WeatherCondition.fromForecast('Partly Cloudy'),
          WeatherCondition.cloudy);
      expect(WeatherCondition.fromForecast('Overcast'),
          WeatherCondition.cloudy);
    });

    test('fair at night with isNight=true → night', () {
      expect(
        WeatherCondition.fromForecast('Fair', isNight: true),
        WeatherCondition.night,
      );
    });

    test('fair during day (isNight=false) → clear', () {
      expect(
        WeatherCondition.fromForecast('Fair (Day)'),
        WeatherCondition.clear,
      );
      expect(
        WeatherCondition.fromForecast('Fair & Warm'),
        WeatherCondition.clear,
      );
    });
  });

  // ─── WeatherCondition.shortLabel ─────────────────────────────────────────

  group('WeatherCondition.shortLabel', () {
    test('maps known NEA strings', () {
      expect(WeatherCondition.shortLabel('Thundery Showers'), 'Thundery');
      expect(WeatherCondition.shortLabel('Heavy Rain'), 'Heavy Rain');
      expect(WeatherCondition.shortLabel('Light Rain'), 'Rainy');
      expect(WeatherCondition.shortLabel('Partly Cloudy'), 'Cloudy');
      expect(WeatherCondition.shortLabel('Fair (Day)'), 'Fair');
      expect(WeatherCondition.shortLabel('Fair & Warm'), 'Fair & Warm');
      expect(WeatherCondition.shortLabel('Overcast'), 'Overcast');
    });

    test('passes through unmapped strings verbatim', () {
      expect(WeatherCondition.shortLabel('Foggy'), 'Foggy');
    });
  });

  // ─── Nearest-area selection ───────────────────────────────────────────────

  group('WeatherStore nearest-area resolution', () {
    final resp =
        NeaTwoHourResponse.fromJson(_twoHourJson as Map<String, dynamic>);

    test('selects Bishan when at Bishan MRT coords', () {
      // Bishan MRT: ~1.352, 103.848
      final area = _nearestArea(resp, 1.352, 103.848);
      expect(area?.name, 'Bishan');
    });

    test('selects Ang Mo Kio when north of Bishan', () {
      // Closer to AMK centroid
      final area = _nearestArea(resp, 1.369, 103.845);
      expect(area?.name, 'Ang Mo Kio');
    });

    test('selects Jurong West when in the west', () {
      final area = _nearestArea(resp, 1.340, 103.709);
      expect(area?.name, 'Jurong West');
    });

    test('returns null on empty metadata', () {
      final empty = NeaTwoHourResponse.fromJson({});
      expect(_nearestArea(empty, 1.35, 103.85), isNull);
    });
  });

  // ─── Nearest-temperature-station selection ────────────────────────────────

  group('WeatherStore nearest-temperature-station', () {
    final resp = NeaAirTemperatureResponse.fromJson(
        _temperatureJson as Map<String, dynamic>);

    test('picks Upper Thomson Road station when near Bishan', () {
      // Bishan is closest to Upper Thomson Road (S24)
      final temp = _nearestTemperature(resp, 1.352, 103.848);
      expect(temp, closeTo(28.8, 0.1));
    });

    test('picks Clementi Road station when in the west', () {
      final temp = _nearestTemperature(resp, 1.334, 103.776);
      expect(temp, closeTo(30.2, 0.1));
    });

    test('returns null when no readings available', () {
      final empty = NeaAirTemperatureResponse.fromJson({});
      expect(_nearestTemperature(empty, 1.35, 103.85), isNull);
    });

    test('returns null when readings list is empty', () {
      final noReadings = NeaAirTemperatureResponse.fromJson({
        'metadata': {
          'stations': [
            {
              'id': 'S99',
              'name': 'Test',
              'location': {'latitude': 1.35, 'longitude': 103.85},
            },
          ],
        },
        'items': [
          {'readings': []},
        ],
      });
      expect(_nearestTemperature(noReadings, 1.35, 103.85), isNull);
    });
  });

  // ─── Rain hint derivation ─────────────────────────────────────────────────

  group('WeatherStore._rainHint', () {
    final twentyFour = Nea24hResponse.fromJson(
        _twentyFourJson as Map<String, dynamic>);

    test('returns null when already raining', () {
      // When the 2h forecast already has rain, hint is suppressed (the
      // condition label covers it).
      final hint = _rainHint('Light Rain', twentyFour, DateTime(2026, 6, 10, 10));
      expect(hint, isNull);
    });

    test('returns null when no rain in horizon', () {
      // At 18:00, the remaining period is "Fair" — no rain.
      final hint = _rainHint('Fair', twentyFour, DateTime(2026, 6, 10, 18));
      expect(hint, isNull);
    });

    test('returns "rain this afternoon" when afternoon period has showers', () {
      // At 10:00, the afternoon period (12:00–18:00) has thundery showers
      // and is within 8 hours.
      final hint = _rainHint(
          'Partly Cloudy', twentyFour, DateTime(2026, 6, 10, 10));
      expect(hint, 'rain this afternoon');
    });

    test('returns null when the rain period is beyond the 8-hour horizon', () {
      // At 03:00, the afternoon period (12:00) is 9 h away → outside horizon.
      final hint = _rainHint(
          'Fair', twentyFour, DateTime(2026, 6, 10, 3));
      expect(hint, isNull);
    });
  });

  // ─── WeatherSnapshot.isFresh ─────────────────────────────────────────────

  group('WeatherSnapshot.isFresh', () {
    test('fresh within 15 minutes', () {
      final snap = WeatherSnapshot(
        tempC: 30,
        forecastText: 'Cloudy',
        condition: WeatherCondition.cloudy,
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(snap.isFresh, isTrue);
    });

    test('stale after 15 minutes', () {
      final snap = WeatherSnapshot(
        tempC: 30,
        forecastText: 'Cloudy',
        condition: WeatherCondition.cloudy,
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 16)),
      );
      expect(snap.isFresh, isFalse);
    });
  });

  // ─── NeaService exception types ──────────────────────────────────────────

  group('NeaException', () {
    test('badResponse carries status code', () {
      final e = NeaException.badResponse(503);
      expect(e.statusCode, 503);
      expect(e.message, contains('503'));
    });

    test('decoding carries detail', () {
      final e = NeaException.decoding('unexpected token');
      expect(e.decodingDetail, 'unexpected token');
      expect(e.statusCode, isNull);
    });
  });
}

// ─── Private-helper bridges ───────────────────────────────────────────────────
// WeatherStore's resolution helpers are private (`static`), so we call them
// through thin wrappers here. In Dart, `@visibleForTesting` is advisory —
// we can import and use the library directly in the test package. This mirrors
// how data_layer_test.dart directly calls data_store.dart internals.

NeaAreaMetadata? _nearestArea(
        NeaTwoHourResponse resp, double lat, double lon) =>
    WeatherStore.nearestAreaForTest(resp, lat, lon);

double? _nearestTemperature(
        NeaAirTemperatureResponse resp, double lat, double lon) =>
    WeatherStore.nearestTemperatureForTest(resp, lat, lon);

String? _rainHint(String forecast, Nea24hResponse resp, DateTime now) =>
    WeatherStore.rainHintForTest(forecast, resp, now);
