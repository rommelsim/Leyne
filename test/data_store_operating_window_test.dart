// DataStore.operatingWindow tests — the additive accessor backing the
// Service Info screen's "First & last bus" card. Unlike busTimings (which
// picks one day type based on `now`), operatingWindow returns weekday /
// Saturday / Sunday-P.H. together in one call.
//
// Mirrors the _NullHttpClient / fake-LtaService(api:) pattern used across
// the other data_store_*_test.dart files.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lyne/data/data_store.dart';
import 'package:lyne/data/lta_models.dart';
import 'package:lyne/data/lta_service.dart';

class _NullHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnsupportedError('_NullHttpClient should never be called');
  }
}

class _FakeLtaService extends LtaService {
  _FakeLtaService() : super(client: _NullHttpClient());

  List<LtaBusRoute> routesResult = const [];

  @override
  Future<List<LtaBusStop>> busStops() async => const [];

  @override
  Future<List<LtaBusService>> busServices() async => const [];

  @override
  Future<List<LtaBusRoute>> busRoutes() async => routesResult;
}

LtaBusRoute _route(
  String serviceNo,
  String stopCode, {
  int direction = 1,
  int seq = 1,
  String? wdFirst,
  String? wdLast,
  String? satFirst,
  String? satLast,
  String? sunFirst,
  String? sunLast,
}) => LtaBusRoute(
  serviceNo: serviceNo,
  operator_: 'SBST',
  direction: direction,
  stopSequence: seq,
  busStopCode: stopCode,
  distance: 0,
  wdFirstBus: wdFirst,
  wdLastBus: wdLast,
  satFirstBus: satFirst,
  satLastBus: satLast,
  sunFirstBus: sunFirst,
  sunLastBus: sunLast,
);

void main() {
  group('DataStore.operatingWindow', () {
    test('returns null before the routes dataset has loaded', () {
      final store = DataStore(api: _FakeLtaService());
      expect(store.operatingWindow(serviceNo: '10', stopCode: 'A'), isNull);
    });

    test('returns all three day types together for a matching row', () async {
      final fake = _FakeLtaService();
      fake.routesResult = [
        _route(
          '10',
          'A',
          wdFirst: '0530',
          wdLast: '2330',
          satFirst: '0600',
          satLast: '2300',
          sunFirst: '0700',
          sunLast: '2200',
        ),
      ];
      final store = DataStore(api: fake);
      store.ensureRoutes();
      await Future<void>.delayed(Duration.zero);

      final window = store.operatingWindow(serviceNo: '10', stopCode: 'A');
      expect(window, isNotNull);
      expect(window!.firstWd, '0530');
      expect(window.lastWd, '2330');
      expect(window.firstSat, '0600');
      expect(window.lastSat, '2300');
      expect(window.firstSun, '0700');
      expect(window.lastSun, '2200');
    });

    test('day types the service does not run surface as null fields', () async {
      final fake = _FakeLtaService();
      // A weekday-only shuttle: no Saturday/Sunday times published.
      fake.routesResult = [_route('855', 'B', wdFirst: '0700', wdLast: '1900')];
      final store = DataStore(api: fake);
      store.ensureRoutes();
      await Future<void>.delayed(Duration.zero);

      final window = store.operatingWindow(serviceNo: '855', stopCode: 'B');
      expect(window, isNotNull);
      expect(window!.firstWd, '0700');
      expect(window.firstSat, isNull);
      expect(window.lastSat, isNull);
      expect(window.firstSun, isNull);
      expect(window.lastSun, isNull);
    });

    test(
      'returns null when the (service, stop) pair has no route row',
      () async {
        final fake = _FakeLtaService();
        fake.routesResult = [
          _route('10', 'A', wdFirst: '0530', wdLast: '2330'),
        ];
        final store = DataStore(api: fake);
        store.ensureRoutes();
        await Future<void>.delayed(Duration.zero);

        // Right service, wrong stop.
        expect(store.operatingWindow(serviceNo: '10', stopCode: 'Z'), isNull);
        // Right stop, wrong service.
        expect(store.operatingWindow(serviceNo: '99', stopCode: 'A'), isNull);
      },
    );

    test(
      'a service with two directions resolves the stop in either one',
      () async {
        final fake = _FakeLtaService();
        fake.routesResult = [
          _route('10', 'A', direction: 1, wdFirst: '0530', wdLast: '2330'),
          _route('10', 'Z', direction: 2, wdFirst: '0545', wdLast: '2345'),
        ];
        final store = DataStore(api: fake);
        store.ensureRoutes();
        await Future<void>.delayed(Duration.zero);

        expect(
          store.operatingWindow(serviceNo: '10', stopCode: 'A')?.firstWd,
          '0530',
        );
        expect(
          store.operatingWindow(serviceNo: '10', stopCode: 'Z')?.firstWd,
          '0545',
        );
      },
    );
  });
}
