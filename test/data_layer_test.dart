// Data layer unit tests — direct ports of legacy/ios-native/LyneTests/
// LyneCoreTests.swift (the parts that aren't UI/AppModel-specific). Same
// expectations, same edge cases, same JSON fixtures.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/data/data_store.dart';
import 'package:lyne/data/geo.dart';
import 'package:lyne/data/lta_models.dart';
import 'package:lyne/data/models.dart';
import 'package:lyne/data/search_logic.dart';

void main() {
  // ─── ETA rounding (LTA guide §2: round DOWN; <1 min → "Arr") ──
  group('fmtEta', () {
    test('rounds down to whole minutes', () {
      expect(fmtEta(229).big, '3'); // 3:49 → "3 min"
      expect(fmtEta(127).big, '2'); // 2:07 → "2 min"
      expect(fmtEta(600).big, '10');
    });

    test('one-minute window is live', () {
      final one = fmtEta(119); // 1:59 → "1 min", live
      expect(one.big, '1');
      expect(one.live, isTrue);
    });

    test('<1 min becomes Arr/now', () {
      final arr = fmtEta(59); // 0:59 → "Arr"
      expect(arr.big, 'Arr');
      expect(arr.live, isTrue);
      expect(fmtEta(0).big, 'Arr');
      expect(fmtEta(-10).big, 'Arr');
    });
  });

  // ─── Query-kind detection ─────────────────────────────────
  group('detectQueryKind', () {
    test('recognises bus, stopcode, postal, block, text, empty', () {
      expect(detectQueryKind('88').kind, 'bus');
      expect(detectQueryKind('410W').kind, 'bus');
      expect(detectQueryKind('NR1').kind, 'bus');
      expect(detectQueryKind('53061').kind, 'stopcode');
      expect(detectQueryKind('560123').kind, 'postal');
      expect(detectQueryKind('blk 230').kind, 'block');
      expect(detectQueryKind('Bishan MRT').kind, 'text');
      expect(detectQueryKind('').kind, 'empty');
    });
  });

  // ─── Haversine distance ───────────────────────────────────
  group('haversine', () {
    test('identical points return 0', () {
      expect(haversine(1.3, 103.8, 1.3, 103.8), closeTo(0, 0.001));
    });

    test('~1 deg latitude ≈ 111 km', () {
      expect(
        haversine(1.0, 103.8, 2.0, 103.8),
        closeTo(111195, 1500),
      );
    });

    test('Bishan MRT → Bishan Int (~300 m)', () {
      final d = haversine(1.350758, 103.848298, 1.350955, 103.849516);
      expect(d, greaterThan(50));
      expect(d, lessThan(400));
    });
  });

  // ─── LTA date parsing (+08:00) ────────────────────────────
  group('LtaDate.parse', () {
    test('parses ISO-8601 with +08:00', () {
      expect(LtaDate.parse('2024-08-14T16:41:48+08:00'), isNotNull);
      expect(LtaDate.parse('2026-05-18T13:42:06+08:00'), isNotNull);
    });

    test('returns null on empty / garbage', () {
      expect(LtaDate.parse(''), isNull);
      expect(LtaDate.parse('not-a-date'), isNull);
    });
  });

  // ─── Load / Deck mapping ──────────────────────────────────
  group('Load / Deck mapping', () {
    test('SEA / SDA / LSD map correctly; blank defaults to seats', () {
      // Use the parsed nextBus.load through toService() to validate the
      // mapper; it's private to lta_models.dart so we exercise it via
      // the public surface.
      Service mapWith(String load, String type) {
        final svc = LtaArrivalService.fromJson({
          'ServiceNo': '88',
          'NextBus': {
            'EstimatedArrival': '2099-01-01T00:00:00+08:00',
            'Load': load,
            'Type': type,
            'Feature': 'WAB',
          },
          'NextBus2': {'EstimatedArrival': ''},
          'NextBus3': {'EstimatedArrival': ''},
        });
        return svc.toService(destName: 'X');
      }

      expect(mapWith('SEA', 'SD').load, Load.sea);
      expect(mapWith('SDA', 'SD').load, Load.sda);
      expect(mapWith('LSD', 'SD').load, Load.lsd);
      expect(mapWith('', 'SD').load, Load.sea);

      expect(mapWith('SEA', 'DD').deck, Deck.dd);
      expect(mapWith('SEA', 'SD').deck, Deck.sd);
      expect(mapWith('SEA', 'BD').deck, Deck.bd);
      expect(mapWith('SEA', '').deck, Deck.sd);
    });
  });

  // ─── Bus Arrival v3 JSON (sample from the LTA guide) ──────
  group('LtaArrivalResponse.fromJson', () {
    test('parses NextBus 1/2/3 and toService maps faithfully', () {
      final json = jsonDecode('''
      {
        "odata.metadata": "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival",
        "BusStopCode": "83139",
        "Services": [
          {
            "ServiceNo": "15", "Operator": "GAS",
            "NextBus":  { "OriginCode":"77009","DestinationCode":"77131","EstimatedArrival":"2024-08-14T16:41:48+08:00","Monitored":1,"Latitude":"1.3154","Longitude":"103.9059","VisitNumber":"1","Load":"SEA","Feature":"WAB","Type":"SD" },
            "NextBus2": { "OriginCode":"77009","DestinationCode":"77131","EstimatedArrival":"2024-08-14T16:49:22+08:00","Monitored":1,"Latitude":"1.330","Longitude":"103.903","VisitNumber":"1","Load":"SDA","Feature":"WAB","Type":"DD" },
            "NextBus3": { "OriginCode":"","DestinationCode":"","EstimatedArrival":"","Monitored":0,"Latitude":"","Longitude":"","VisitNumber":"","Load":"","Feature":"","Type":"" }
          }
        ]
      }
      ''') as Map<String, dynamic>;

      final resp = LtaArrivalResponse.fromJson(json);
      expect(resp.busStopCode, '83139');
      expect(resp.services, hasLength(1));

      final svc = resp.services[0];
      expect(svc.serviceNo, '15');
      expect(svc.nextBus.hasData, isTrue);
      expect(svc.nextBus3.hasData, isFalse); // blank → no data

      final mapped = svc.toService(destName: 'Bukit Panjang Int');
      expect(mapped.no, '15');
      expect(mapped.dest, 'Bukit Panjang Int');
      expect(mapped.load, Load.sea);
      expect(mapped.deck, Deck.sd);
      expect(mapped.wab, isTrue);
      expect(mapped.arrivalDate, isNotNull);
      expect(mapped.followingDate, isNotNull);
      expect(mapped.thirdDate, isNull); // NextBus3 blank
    });

    test('toService falls back to eta+600s when NextBus2 has no arrival', () {
      final json = jsonDecode('''
      {
        "BusStopCode": "1",
        "Services": [{
          "ServiceNo": "10",
          "NextBus": {"EstimatedArrival":"2099-01-01T00:05:00+08:00","Load":"SEA","Type":"SD","Feature":""},
          "NextBus2": {"EstimatedArrival":""},
          "NextBus3": {"EstimatedArrival":""}
        }]
      }''') as Map<String, dynamic>;
      final svc = LtaArrivalResponse.fromJson(json).services.first;
      final now = DateTime.parse('2099-01-01T00:00:00+08:00');
      final mapped = svc.toService(destName: 'X', now: now);
      expect(mapped.etaSec, 300); // 5 minutes
      expect(mapped.followingSec, 900); // 5 min + 600s fallback
    });
  });

  // ─── Reference dataset JSON ───────────────────────────────
  group('Reference dataset parsing', () {
    test('LtaBusStop.fromJson reads numeric lat/lon', () {
      final j = jsonDecode('''
      {"BusStopCode":"01012","RoadName":"Victoria St","Description":"Hotel Grand Pacific","Latitude":1.29685,"Longitude":103.853}
      ''') as Map<String, dynamic>;
      final s = LtaBusStop.fromJson(j);
      expect(s.busStopCode, '01012');
      expect(s.description, 'Hotel Grand Pacific');
      expect(s.latitude, closeTo(1.29685, 1e-5));
    });

    test('LtaBusRoute.fromJson reads StopSequence', () {
      final j = jsonDecode('''
      {"ServiceNo":"107M","Operator":"SBST","Direction":1,"StopSequence":28,"BusStopCode":"01219","Distance":10.3}
      ''') as Map<String, dynamic>;
      final r = LtaBusRoute.fromJson(j);
      expect(r.serviceNo, '107M');
      expect(r.stopSequence, 28);
      expect(r.busStopCode, '01219');
    });
  });

  // ─── journeySegment trims the route correctly ─────────────
  // The reported "weird waypoint" bug: drawing the whole 40–60-stop route
  // with straight lines made a tangle. The fix slices to bus→you ± a small
  // approach window. Same assertions as the iOS test.
  group('journeySegment', () {
    final stops = List<RouteStopLive>.generate(
      40,
      (i) => RouteStopLive(
          code: '$i', name: 'S$i', lat: i.toDouble(), lon: 0, seq: i),
    );

    test('bus 10, you 15 → slices [10..16] only', () {
      final seg = journeySegment(
          RouteInfo(stops: stops, youIndex: 15, busIndex: 10));
      expect(seg.first.code, '10');
      expect(seg.last.code, '16');
      expect(seg.length, 7);
    });

    test('bus GPS unknown → bounded approach window (you-6 … you+1)', () {
      final seg = journeySegment(RouteInfo(stops: stops, youIndex: 15));
      expect(seg.first.code, '9');
      expect(seg.last.code, '16');
    });

    test('bus already past you → still includes your stop, still bounded', () {
      final seg = journeySegment(
          RouteInfo(stops: stops, youIndex: 5, busIndex: 30));
      expect(seg.length, lessThanOrEqualTo(8));
      expect(seg.any((s) => s.code == '5'), isTrue);
    });

    test('empty route is safe', () {
      expect(journeySegment(RouteInfo(stops: const [], youIndex: 0)), isEmpty);
    });
  });

  // ─── fmtDistance ──────────────────────────────────────────
  group('fmtDistance', () {
    test('< 1km in metres, >= 1km in km with one decimal', () {
      expect(fmtDistance(0), '0m');
      expect(fmtDistance(420), '420m');
      expect(fmtDistance(999), '999m');
      expect(fmtDistance(1000), '1.0km');
      expect(fmtDistance(1234), '1.2km');
    });
  });

  // ─── Monitored flag → live-GPS vs timetable estimate ──────
  group('Service.monitored', () {
    Service mapWith(Object? monitored) {
      final svc = LtaArrivalService.fromJson({
        'ServiceNo': '88',
        'NextBus': {
          'EstimatedArrival': '2099-01-01T00:00:00+08:00',
          'Load': 'SEA',
          'Type': 'SD',
          'Monitored': ?monitored,
        },
        'NextBus2': {'EstimatedArrival': ''},
        'NextBus3': {'EstimatedArrival': ''},
      });
      return svc.toService(destName: 'X');
    }

    test('Monitored 1 → live (monitored true)', () {
      expect(mapWith(1).monitored, isTrue);
    });
    test('Monitored 0 → timetable estimate (monitored false)', () {
      expect(mapWith(0).monitored, isFalse);
    });
    test('absent Monitored defaults to true — never cry wolf', () {
      expect(mapWith(null).monitored, isTrue);
    });
  });

  // ─── Bus operating hours (first / last bus) ───────────────
  group('LtaBusRoute first/last bus', () {
    test('parses WD/SAT/SUN times and normalises "-" to null', () {
      final j = jsonDecode('''
      {"ServiceNo":"88","Operator":"SBST","Direction":1,"StopSequence":3,
       "BusStopCode":"01219","Distance":1.2,
       "WD_FirstBus":"0530","WD_LastBus":"0015",
       "SAT_FirstBus":"0600","SAT_LastBus":"0000",
       "SUN_FirstBus":"-","SUN_LastBus":""}
      ''') as Map<String, dynamic>;
      final r = LtaBusRoute.fromJson(j);
      expect(r.wdFirstBus, '0530');
      expect(r.wdLastBus, '0015');
      expect(r.satFirstBus, '0600');
      expect(r.satLastBus, '0000');
      expect(r.sunFirstBus, isNull); // "-" → no service
      expect(r.sunLastBus, isNull); // "" → no service
    });
  });

  group('fmtClock', () {
    test('24h formatting', () {
      expect(fmtClock('0530'), '05:30');
      expect(fmtClock('0015'), '00:15');
      expect(fmtClock('2345'), '23:45');
    });
    test('12h formatting', () {
      expect(fmtClock('0530', use24h: false), '5:30 AM');
      expect(fmtClock('0015', use24h: false), '12:15 AM');
      expect(fmtClock('1305', use24h: false), '1:05 PM');
      expect(fmtClock('1200', use24h: false), '12:00 PM');
    });
  });

  group('lastBusGone', () {
    test('before last bus → not gone', () {
      final now = DateTime(2026, 5, 21, 22, 0); // 22:00
      expect(lastBusGone('0530', '2330', now), isFalse);
    });
    test('after last bus → gone', () {
      final now = DateTime(2026, 5, 21, 23, 45); // 23:45
      expect(lastBusGone('0530', '2330', now), isTrue);
    });
    test('past-midnight last bus: 00:30 is still within service', () {
      final now = DateTime(2026, 5, 21, 0, 30); // 00:30
      expect(lastBusGone('0530', '0100', now), isFalse);
    });
    test('past-midnight last bus: 02:00 is after a 01:00 last bus', () {
      final now = DateTime(2026, 5, 21, 2, 0); // 02:00
      expect(lastBusGone('0530', '0100', now), isTrue);
    });
  });
}
