// DataStore cold-start ordering tests.
//
// Tests the two orderings of bootstrap() vs updateNearby() to ensure nearby
// stops are always populated and arrival prefetch fires regardless of order.
//
// (a) updateNearby arrives BEFORE bootstrap completes:
//     stops still empty → nearby stays empty → once bootstrap completes
//     with _lastLoc already set, nearby populates and arrival prefetch fires.
//
// (b) bootstrap completes FIRST with no location, THEN updateNearby arrives:
//     nearby populates synchronously + arrival prefetch fires.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lyne/data/data_store.dart';
import 'package:lyne/data/lta_models.dart';
import 'package:lyne/data/lta_service.dart';

// ─── Null http client ─────────────────────────────────────────────────────
class _NullHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnsupportedError('_NullHttpClient should never be called');
  }
}

// ─── Controllable fake LtaService ────────────────────────────────────────
// `bootstrapGate` is a Completer that blocks busStops/busServices until the
// test releases it, letting tests control the relative timing.
class _ControllableFake extends LtaService {
  _ControllableFake() : super(client: _NullHttpClient());

  final Completer<void> bootstrapGate = Completer<void>();
  List<LtaBusStop> stopsResult = const [];
  final Map<String, List<LtaArrivalResponse>> _arrivalQueue = {};

  void queueArrival(String code, LtaArrivalResponse resp) {
    (_arrivalQueue[code] ??= []).add(resp);
  }

  @override
  Future<List<LtaBusStop>> busStops() async {
    await bootstrapGate.future;
    return stopsResult;
  }

  @override
  Future<List<LtaBusService>> busServices() async {
    await bootstrapGate.future;
    return [];
  }

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
  // ─── Ordering (a): updateNearby BEFORE bootstrap finishes ─────────────
  group('Cold-start (a): updateNearby before bootstrap completes', () {
    test('nearby is empty while bootstrap is still loading', () async {
      final fake = _ControllableFake();
      fake.stopsResult = [_stop('A', 1.3521, 103.8198)];
      fake.queueArrival('A', _arrResp('A', '7', 90));

      final store = DataStore(api: fake);
      unawaited(store.bootstrap()); // blocks on gate

      // Location fix arrives while stops haven't loaded yet.
      store.updateNearby(1.3521, 103.8198);

      expect(store.nearby, isEmpty,
          reason: 'nearby must stay empty while bootstrap is blocked');
    });

    test('nearby populates after bootstrap unblocks with _lastLoc already set',
        () async {
      final fake = _ControllableFake();
      fake.stopsResult = [
        _stop('A', 1.3521, 103.8198),
        _stop('B', 1.3600, 103.8300),
      ];
      fake.queueArrival('A', _arrResp('A', '7', 90));
      fake.queueArrival('B', _arrResp('B', '14', 180));

      final store = DataStore(api: fake);
      final bootstrapFuture = store.bootstrap(); // blocked

      store.updateNearby(1.3521, 103.8198);
      expect(store.nearby, isEmpty, reason: 'still loading');

      // Release bootstrap.
      fake.bootstrapGate.complete();
      await bootstrapFuture;

      expect(store.nearby, isNotEmpty,
          reason: 'bootstrap finishing with _lastLoc set must populate nearby');
      expect(store.nearby.first.stopCode, 'A',
          reason: 'A is closest to the given location');

      // Let arrival prefetch resolve.
      await Future<void>.delayed(Duration.zero);

      final nearbyA = store.nearby.firstWhere((n) => n.stopCode == 'A');
      expect(nearbyA.services, isNotEmpty,
          reason: 'prefetch must fire and populate services after bootstrap');
    });

    test('arrivals are fetched for nearby stops after bootstrap unblocks',
        () async {
      final fake = _ControllableFake();
      fake.stopsResult = [_stop('C', 1.35, 103.82)];
      fake.queueArrival('C', _arrResp('C', '88', 120));

      final store = DataStore(api: fake);
      final bootstrapFuture = store.bootstrap();

      store.updateNearby(1.35, 103.82);
      fake.bootstrapGate.complete();
      await bootstrapFuture;
      await Future<void>.delayed(Duration.zero);

      expect(store.arrivals['C']?.kind, ArrivalStateKind.loaded,
          reason: 'prefetch must resolve arrivals for nearby stop C');
    });
  });

  // ─── Ordering (b): bootstrap finishes first, then updateNearby ────────
  group('Cold-start (b): bootstrap completes first, then updateNearby', () {
    test('nearby populates immediately when updateNearby called after bootstrap',
        () async {
      final fake = _ControllableFake();
      fake.stopsResult = [
        _stop('D', 1.3521, 103.8198),
        _stop('E', 1.3600, 103.8300),
      ];
      fake.queueArrival('D', _arrResp('D', '65', 150));
      fake.queueArrival('E', _arrResp('E', '99', 240));

      final store = DataStore(api: fake);
      fake.bootstrapGate.complete();
      await store.bootstrap();

      expect(store.nearby, isEmpty, reason: 'no location set yet');

      store.updateNearby(1.3521, 103.8198);

      // _recomputeNearby is synchronous — nearby is populated now.
      expect(store.nearby, isNotEmpty,
          reason: 'nearby must populate synchronously on updateNearby after bootstrap');
      expect(store.nearby.first.stopCode, 'D');
    });

    test('prefetch fires and arrivals resolve after updateNearby', () async {
      final fake = _ControllableFake();
      fake.stopsResult = [_stop('F', 1.35, 103.82)];
      fake.queueArrival('F', _arrResp('F', '33', 80));

      final store = DataStore(api: fake);
      fake.bootstrapGate.complete();
      await store.bootstrap();

      store.updateNearby(1.35, 103.82);
      await Future<void>.delayed(Duration.zero);

      expect(store.arrivals['F']?.kind, ArrivalStateKind.loaded,
          reason: 'prefetch must fire after updateNearby and resolve arrivals');
    });

    test('second updateNearby re-ranks by new location', () async {
      final fake = _ControllableFake();
      // G at 1.35, H at 1.36 — start near G.
      fake.stopsResult = [
        _stop('G', 1.3500, 103.82),
        _stop('H', 1.3600, 103.82),
      ];

      final store = DataStore(api: fake);
      fake.bootstrapGate.complete();
      await store.bootstrap();

      store.updateNearby(1.3500, 103.82); // near G
      expect(store.nearby.first.stopCode, 'G');

      store.updateNearby(1.3600, 103.82); // near H
      expect(store.nearby.first.stopCode, 'H',
          reason: 'second updateNearby must re-rank by the new location');
    });

    test('notifyListeners fires on updateNearby', () async {
      final fake = _ControllableFake();
      fake.stopsResult = [_stop('I', 1.35, 103.82)];

      final store = DataStore(api: fake);
      fake.bootstrapGate.complete();
      await store.bootstrap();

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      store.updateNearby(1.35, 103.82);

      expect(notifyCount, greaterThanOrEqualTo(1),
          reason: 'updateNearby with new data must call notifyListeners');
    });
  });
}
