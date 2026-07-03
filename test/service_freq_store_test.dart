// ServiceFreqStore / ServiceFreq tests — band formatting, first-row-wins
// indexing, paginated fetch, and the disk-cache round trip (fresh cache
// short-circuits the network; stale cache refetches).
//
// Uses a minimal _FakeHttpClient (mirrors the _NullHttpClient /
// _FakeLtaService pattern in data_store_arrivals_test.dart) so no real
// network calls are made, and SharedPreferences.setMockInitialValues for the
// disk-cache layer.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/data/lta_config.dart';
import 'package:lyne/data/service_freq_store.dart';

// ─── Fake http client — serves one JSON page per call, in order ──────────
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.pages);

  final List<List<Map<String, dynamic>>> pages;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final page = calls < pages.length
        ? pages[calls]
        : const <Map<String, dynamic>>[];
    calls++;
    final body = jsonEncode({'value': page});
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

/// A client that fails the test if it's ever called — used to assert a
/// fresh disk cache short-circuits the network entirely.
class _UnreachableHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    fail('network must not be reached when a fresh cache is present');
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────

Map<String, dynamic> _dto(
  String no, {
  String? category,
  String? amPeak,
  String? amOffpeak,
  String? pmPeak,
  String? pmOffpeak,
}) => {
  'ServiceNo': no,
  'Category': category,
  'AM_Peak_Freq': amPeak,
  'AM_Offpeak_Freq': amOffpeak,
  'PM_Peak_Freq': pmPeak,
  'PM_Offpeak_Freq': pmOffpeak,
};

const _cacheKey = 'lyne.serviceFreq.cache.v1';

String _cachePayload(List<Map<String, dynamic>> items, DateTime savedAt) =>
    jsonEncode({'savedAt': savedAt.millisecondsSinceEpoch, 'items': items});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServiceFreq.band', () {
    test('a range formats with an en-dash + " min"', () {
      expect(ServiceFreq.band('8-12'), '8–12 min');
    });

    test('blank / null maps to an em-dash', () {
      expect(ServiceFreq.band(''), '—');
      expect(ServiceFreq.band(null), '—');
    });

    test('"-" maps to an em-dash', () {
      expect(ServiceFreq.band('-'), '—');
    });

    test('surrounding whitespace is trimmed before checking', () {
      expect(ServiceFreq.band('  10-15  '), '10–15 min');
    });
  });

  group('ServiceFreq.fromJson / toJson', () {
    test('round-trips every field', () {
      final freq = ServiceFreq.fromJson(
        _dto(
          '88',
          category: 'TRUNK',
          amPeak: '6-9',
          amOffpeak: '10-15',
          pmPeak: '5-8',
          pmOffpeak: '12-20',
        ),
      );
      expect(freq.serviceNo, '88');
      expect(freq.category, 'TRUNK');
      expect(freq.amPeak, '6-9');
      expect(freq.amOffpeak, '10-15');
      expect(freq.pmPeak, '5-8');
      expect(freq.pmOffpeak, '12-20');
      expect(ServiceFreq.fromJson(freq.toJson()), freq);
    });

    test('missing columns parse to null, not throw', () {
      final freq = ServiceFreq.fromJson({'ServiceNo': '5'});
      expect(freq.serviceNo, '5');
      expect(freq.category, isNull);
      expect(freq.amPeak, isNull);
    });
  });

  group('ServiceFreqStore index build (first row wins)', () {
    test('keeps the first row seen for a duplicate serviceNo', () {
      const items = [
        ServiceFreq(serviceNo: '10', amPeak: '8-12'),
        ServiceFreq(serviceNo: '10', amPeak: '99-99'), // direction 2
        ServiceFreq(serviceNo: '11', amPeak: '5-7'),
      ];
      final index = ServiceFreqStore.indexFromForTest(items);
      expect(index['10']?.amPeak, '8-12');
      expect(index['11']?.amPeak, '5-7');
      expect(index.length, 2);
    });
  });

  group('ServiceFreqStore.freq — network + pagination', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('pages until a short page, then indexes and caches to disk', () async {
      // A full first page forces a second $skip fetch; the second page is
      // short, ending the loop (mirrors LtaService._fetchAllPaged's
      // termination rule).
      final page1 = List.generate(
        LtaConfig.pageSize,
        (i) => _dto('S$i', amPeak: '5-9'),
      );
      final page2 = [_dto('LAST', amPeak: '10-20')];
      final client = _FakeHttpClient([page1, page2]);
      final store = ServiceFreqStore(client: client);

      final freq = await store.freq('LAST');
      expect(freq?.amPeak, '10-20');
      expect(
        client.calls,
        2,
        reason: 'must fetch a second page after a full first page',
      );

      // The index was written to disk — a fresh store instance (with a
      // client that must not be touched) reads it back.
      final store2 = ServiceFreqStore(client: _UnreachableHttpClient());
      final cached = await store2.freq('S0');
      expect(cached?.amPeak, '5-9');
    });

    test('returns null for a service number absent from the dataset', () async {
      final client = _FakeHttpClient([
        [_dto('7', amPeak: '8-12')],
      ]);
      final store = ServiceFreqStore(client: client);
      expect(await store.freq('999'), isNull);
    });

    test('concurrent freq() calls dedupe onto one fetch', () async {
      final client = _FakeHttpClient([
        [_dto('7', amPeak: '8-12')],
      ]);
      final store = ServiceFreqStore(client: client);

      final results = await Future.wait([
        store.freq('7'),
        store.freq('7'),
        store.freq('7'),
      ]);

      expect(results.every((f) => f?.amPeak == '8-12'), isTrue);
      expect(client.calls, 1, reason: 'concurrent callers share one fetch');
    });
  });

  group('ServiceFreqStore.freq — disk cache freshness', () {
    test('a fresh cache short-circuits the network entirely', () async {
      SharedPreferences.setMockInitialValues({
        _cacheKey: _cachePayload([_dto('42', amPeak: '3-6')], DateTime.now()),
      });

      final store = ServiceFreqStore(client: _UnreachableHttpClient());
      final freq = await store.freq('42');
      expect(freq?.amPeak, '3-6');
    });

    test(
      'a stale (>7d) cache is ignored and the network is refetched',
      () async {
        SharedPreferences.setMockInitialValues({
          _cacheKey: _cachePayload(
            [_dto('42', amPeak: 'STALE')],
            DateTime.now().subtract(
              LtaConfig.referenceCacheMaxAge + const Duration(days: 1),
            ),
          ),
        });

        final client = _FakeHttpClient([
          [_dto('42', amPeak: 'FRESH')],
        ]);
        final store = ServiceFreqStore(client: client);
        final freq = await store.freq('42');
        expect(freq?.amPeak, 'FRESH');
        expect(client.calls, 1);
      },
    );
  });
}
