// DataStore arrival tests — refreshNearbyServices semantics and the
// value-equality notify guard added in the Part-A perf fix.
//
// Uses a minimal _FakeLtaService (defined below) injected via the
// DataStore(api:) constructor parameter, so no real network calls are made.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lyne/data/data_store.dart';
import 'package:lyne/data/lta_models.dart';
import 'package:lyne/data/lta_service.dart';

// ─── Null http client (fake never reaches the network) ───────────────────
class _NullHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnsupportedError('_NullHttpClient should never be called');
  }
}

// ─── Minimal fake LtaService ──────────────────────────────────────────────
//
// Callers pre-load `stopsResult`, `servicesResult`, and queue arrival
// responses per stop code. All methods resolve synchronously on the next
// event-loop turn.

class _FakeLtaService extends LtaService {
  _FakeLtaService() : super(client: _NullHttpClient());

  List<LtaBusStop> stopsResult = const [];

  // stopCode → queued responses; each call pops the first entry.
  final Map<String, List<LtaArrivalResponse>> _arrivalQueue = {};

  void queueArrival(String code, LtaArrivalResponse resp) {
    (_arrivalQueue[code] ??= []).add(resp);
  }

  @override
  Future<List<LtaBusStop>> busStops() async => stopsResult;

  @override
  Future<List<LtaBusService>> busServices() async => [];

  @override
  Future<List<LtaBusRoute>> busRoutes() async => [];

  @override
  Future<LtaArrivalResponse> busArrival(String stopCode,
      {String? serviceNo}) async {
    final queue = _arrivalQueue[stopCode];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0);
    return LtaArrivalResponse(busStopCode: stopCode, services: []);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

LtaBusStop _stop(String code, double lat, double lon) => LtaBusStop(
      busStopCode: code,
      roadName: 'Road $code',
      description: 'Stop $code',
      latitude: lat,
      longitude: lon,
    );

/// Minimal arrival response: one service arriving in [etaSec] seconds.
LtaArrivalResponse _arrResp(String stopCode, String serviceNo, int etaSec) {
  final arrival =
      DateTime.now().add(Duration(seconds: etaSec)).toUtc().toIso8601String();
  return LtaArrivalResponse.fromJson({
    'BusStopCode': stopCode,
    'Services': [
      {
        'ServiceNo': serviceNo,
        'NextBus': {
          'EstimatedArrival': arrival,
          'Monitored': 1,
          'Load': 'SEA',
          'Feature': 'WAB',
          'Type': 'SD',
        },
        'NextBus2': {'EstimatedArrival': ''},
        'NextBus3': {'EstimatedArrival': ''},
      }
    ],
  });
}

// ─── Tests ────────────────────────────────────────────────────────────────

void main() {
  // ─── _refreshNearbyServices semantics ────────────────────────
  group('_refreshNearbyServices via prefetch', () {
    test('nearby stop services snapshot updates after arrivals load', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [
        _stop('A', 1.3521, 103.8198), // closer to (1.352, 103.82)
        _stop('B', 1.3530, 103.8210),
      ];
      fake.queueArrival('A', _arrResp('A', '88', 120));
      fake.queueArrival('B', _arrResp('B', '99', 300));

      final store = DataStore(api: fake);
      await store.bootstrap();
      store.updateNearby(1.3521, 103.8198);
      await Future<void>.delayed(Duration.zero);

      // A is closer → ranks first.
      expect(store.nearby.isNotEmpty, isTrue);
      expect(store.nearby.first.stopCode, 'A');

      // Services snapshot on nearby A must be populated.
      final nearbyA = store.nearby.firstWhere((n) => n.stopCode == 'A');
      expect(nearbyA.services, isNotEmpty,
          reason: 'services snapshot must update after arrivals load');
      expect(nearbyA.services.first.no, '88');
    });

    test('haversine rank order is preserved after multiple arrival refreshes',
        () async {
      final fake = _FakeLtaService();
      // Distances from (1.35, 103.82): A=~0m, B=~100m, C=~500m
      fake.stopsResult = [
        _stop('A', 1.35000, 103.82000),
        _stop('B', 1.35090, 103.82000),
        _stop('C', 1.35450, 103.82000),
      ];
      fake.queueArrival('A', _arrResp('A', '10', 60));
      fake.queueArrival('B', _arrResp('B', '20', 180));
      fake.queueArrival('C', _arrResp('C', '30', 360));

      final store = DataStore(api: fake);
      await store.bootstrap();
      store.updateNearby(1.35000, 103.82000);
      await Future<void>.delayed(Duration.zero);

      final order1 = store.nearby.map((n) => n.stopCode).toList();
      expect(order1, ['A', 'B', 'C']);

      // Queue fresh arrivals and force-refresh.
      fake.queueArrival('A', _arrResp('A', '10', 55));
      fake.queueArrival('B', _arrResp('B', '20', 170));
      fake.queueArrival('C', _arrResp('C', '30', 350));

      for (final n in store.nearby) {
        store.ensureArrivals(n.stopCode, force: true, silent: true);
      }
      await Future<void>.delayed(Duration.zero);

      final order2 = store.nearby.map((n) => n.stopCode).toList();
      expect(order2, order1,
          reason: 'haversine rank must be stable across arrival refreshes');
    });
  });

  // ─── Notify guard (Part A) ────────────────────────────────────
  group('notifyListeners guard — only fires on real change', () {
    test('repeated identical arrivals do NOT trigger extra notifies', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('Z', 1.35, 103.82)];
      fake.queueArrival('Z', _arrResp('Z', '55', 200));

      final store = DataStore(api: fake);
      await store.bootstrap();
      store.updateNearby(1.35, 103.82);
      await Future<void>.delayed(Duration.zero);

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // First force-refresh.
      fake.queueArrival('Z', _arrResp('Z', '55', 200));
      store.ensureArrivals('Z', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);
      final countAfterFirst = notifyCount;

      // Second fetch — identical etaSec → must NOT fire an extra notify.
      fake.queueArrival('Z', _arrResp('Z', '55', 200));
      store.ensureArrivals('Z', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, countAfterFirst,
          reason:
              'identical arrivals must not trigger extra notifyListeners');
    });

    test('changed etaSec DOES trigger notify', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('W', 1.35, 103.82)];
      fake.queueArrival('W', _arrResp('W', '88', 180));

      final store = DataStore(api: fake);
      await store.bootstrap();
      store.updateNearby(1.35, 103.82);
      await Future<void>.delayed(Duration.zero);

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // First fetch — sets state (eta=180).
      fake.queueArrival('W', _arrResp('W', '88', 180));
      store.ensureArrivals('W', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);
      final after1 = notifyCount;

      // Second fetch — different etaSec (180 → 120).
      fake.queueArrival('W', _arrResp('W', '88', 120));
      store.ensureArrivals('W', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(after1),
          reason: 'changed etaSec must trigger notifyListeners');
    });

    test('loading → loaded transition always notifies', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('V', 1.35, 103.82)];
      fake.queueArrival('V', _arrResp('V', '7', 90));

      final store = DataStore(api: fake);
      await store.bootstrap();

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // First ensureArrivals: publishes loading state (1 notify) then
      // completes the fetch (loading→loaded: 1 more notify).
      store.ensureArrivals('V');
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThanOrEqualTo(1),
          reason: 'loading→loaded must notify');
    });

    test('empty → loaded transition notifies', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('U', 1.35, 103.82)];

      final store = DataStore(api: fake);
      await store.bootstrap();

      // First fetch: no queued response → empty state.
      store.ensureArrivals('U', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(store.arrivals['U']?.kind, ArrivalStateKind.empty);

      // Now queue a real arrival.
      fake.queueArrival('U', _arrResp('U', '65', 150));

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      store.ensureArrivals('U', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThanOrEqualTo(1),
          reason: 'empty→loaded must notify');
    });

    test('empty response twice does NOT trigger extra notify', () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('T', 1.35, 103.82)];

      final store = DataStore(api: fake);
      await store.bootstrap();

      // First fetch → empty.
      store.ensureArrivals('T', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(store.arrivals['T']?.kind, ArrivalStateKind.empty);

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // Second fetch → still empty.
      store.ensureArrivals('T', force: true, silent: true);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, 0,
          reason: 'empty→empty must not trigger extra notifyListeners');
    });
  });

  // ─── awaitable refreshArrivals path ──────────────────────────
  group('refreshArrivals awaitable path', () {
    test('future completes even when state unchanged (notify guard must not block it)',
        () async {
      final fake = _FakeLtaService();
      fake.stopsResult = [_stop('Q', 1.35, 103.82)];
      fake.queueArrival('Q', _arrResp('Q', '88', 180));

      final store = DataStore(api: fake);
      await store.bootstrap();

      // First load via refreshArrivals.
      await store.refreshArrivals('Q');
      expect(store.arrivals['Q']?.kind, ArrivalStateKind.loaded);

      // Identical second response.
      fake.queueArrival('Q', _arrResp('Q', '88', 180));

      var completed = false;
      await store.refreshArrivals('Q').then((_) => completed = true);
      expect(completed, isTrue,
          reason:
              'refreshArrivals future must complete even when state unchanged');
    });
  });
}
