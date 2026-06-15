// AppModel unit tests — ports of the pin-logic invariants from
// legacy/ios-native/LyneTests/LyneCoreTests.swift (the LynePinTests
// class). Same expectations; tests use AppModel.forTesting() so the
// 1-second tick timer doesn't run during the suite.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/data/mrt_geo.dart';
import 'package:lyne/state/app_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Fresh prefs for each test so persisted pins don't leak across.
    SharedPreferences.setMockInitialValues({});
  });

  group('Pin toggle invariants', () {
    test('togglePin is symmetric', () async {
      final m = AppModel.forTesting();
      await m.load();
      expect(m.pins, isEmpty);
      expect(m.isPinned('53061'), isFalse);
      m.togglePin('53061');
      expect(m.isPinned('53061'), isTrue);
      m.togglePin('53061');
      expect(m.isPinned('53061'), isFalse);
      m.togglePin('53061'); // re-pin must work
      expect(m.isPinned('53061'), isTrue);
    });

    test('toggleTracked: unchecking the last bus unpins (pinned ⟺ ≥1 bus)',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      final all = ['10', '14', '16'];
      m.togglePin('77009'); // pin tracking all
      expect(m.isPinned('77009'), isTrue);

      m.toggleTracked(code: '77009', busNo: '10', allNos: all);
      m.toggleTracked(code: '77009', busNo: '14', allNos: all);
      // One left — still pinned, last bus still tracked.
      expect(m.isPinned('77009'), isTrue);
      expect(m.isTracked(code: '77009', busNo: '16'), isTrue);

      m.toggleTracked(code: '77009', busNo: '16', allNos: all);
      // Unchecked last → unpinned.
      expect(m.isPinned('77009'), isFalse);
      for (final b in all) {
        expect(m.isTracked(code: '77009', busNo: b), isFalse);
      }

      // Checking a bus on the now-unpinned stop re-pins it.
      m.toggleTracked(code: '77009', busNo: '10', allNos: all);
      expect(m.isPinned('77009'), isTrue);
      expect(m.isTracked(code: '77009', busNo: '10'), isTrue);
      expect(m.isTracked(code: '77009', busNo: '14'), isFalse);
    });

    test('uncheck single-service stop sticks (does not wrap to "all")',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('53061');
      expect(m.isTracked(code: '53061', busNo: '88'), isTrue);
      m.toggleTracked(code: '53061', busNo: '88', allNos: ['88']);
      expect(m.isTracked(code: '53061', busNo: '88'), isFalse);
      m.toggleTracked(code: '53061', busNo: '88', allNos: ['88']);
      expect(m.isTracked(code: '53061', busNo: '88'), isTrue);
    });

    test('uncheck all services on a stop does not wrap', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('X');
      final all = ['88', '156', '410'];
      for (final b in all) {
        m.toggleTracked(code: 'X', busNo: b, allNos: all);
      }
      for (final b in all) {
        expect(m.isTracked(code: 'X', busNo: b), isFalse);
      }
      m.toggleTracked(code: 'X', busNo: '88', allNos: all);
      expect(m.isTracked(code: 'X', busNo: '88'), isTrue);
      expect(m.isTracked(code: 'X', busNo: '156'), isFalse);
    });

    test('checking all services collapses back to "all" (tracked == null)',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('X');
      final all = ['88', '156'];
      m.toggleTracked(code: 'X', busNo: '88', allNos: all);
      m.toggleTracked(code: 'X', busNo: '88', allNos: all); // re-check
      m.toggleTracked(code: 'X', busNo: '156', allNos: all); // already in "all", flips off then on isn't direct here
      // Re-check 156 (was tracked) → after first toggle 156 is off, after second back on.
      m.toggleTracked(code: 'X', busNo: '156', allNos: all);
      expect(m.allTracked('X'), isTrue, reason: 'should normalise to null');
    });
  });

  group('Reorder', () {
    test('reorderPins applies new order; missing codes preserved at end',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('A');
      m.togglePin('B');
      m.togglePin('C');
      expect(m.pins.map((p) => p.code).toList(), ['A', 'B', 'C']);
      m.reorderPins(['C', 'A', 'B']);
      expect(m.pins.map((p) => p.code).toList(), ['C', 'A', 'B']);
      // A code not in the reorder list (D, which doesn't exist) is a no-op;
      // a known code missing from newCodes is preserved at the end.
      m.reorderPins(['A']);
      expect(m.pins.map((p) => p.code).toList(), ['A', 'C', 'B']);
    });
  });

  group('Saved MRT stations', () {
    MrtGeoStation station(String name, List<String> codes) =>
        MrtGeoStation(name: name, codes: codes, lat: 1.3, lon: 103.8);

    test('toggleMrtSaved is symmetric; isMrtSaved tracks membership', () async {
      final m = AppModel.forTesting();
      await m.load();
      final s = station('Bishan', ['NS17', 'CC15']);
      expect(m.savedMrtStations, isEmpty);
      expect(m.isMrtSaved(s), isFalse);
      m.toggleMrtSaved(s);
      expect(m.isMrtSaved(s), isTrue);
      expect(m.savedMrtStations.length, 1);
      m.toggleMrtSaved(s);
      expect(m.isMrtSaved(s), isFalse);
      expect(m.savedMrtStations, isEmpty);
    });

    test('removeMrtSaved removes only the matching station', () async {
      final m = AppModel.forTesting();
      await m.load();
      final a = station('Dhoby Ghaut', ['NS24', 'NE6', 'CC1']);
      final b = station('Bugis', ['EW12', 'DT14']);
      m.toggleMrtSaved(a);
      m.toggleMrtSaved(b);
      expect(m.savedMrtStations.length, 2);
      m.removeMrtSaved(a);
      expect(m.isMrtSaved(a), isFalse);
      expect(m.isMrtSaved(b), isTrue);
      expect(m.savedMrtStations.length, 1);
    });

    test('reorderSavedMrt applies new order; missing ids preserved at end',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      final a = station('A', ['NS1']);
      final b = station('B', ['NS2']);
      final c = station('C', ['NS3']);
      m.toggleMrtSaved(a);
      m.toggleMrtSaved(b);
      m.toggleMrtSaved(c);
      expect(m.savedMrtStations.map((s) => s.name).toList(), ['A', 'B', 'C']);
      m.reorderSavedMrt([c.id, a.id, b.id]);
      expect(m.savedMrtStations.map((s) => s.name).toList(), ['C', 'A', 'B']);
      // An id missing from the new order is preserved at the end.
      m.reorderSavedMrt([a.id]);
      expect(m.savedMrtStations.map((s) => s.name).toList(), ['A', 'C', 'B']);
    });

    test('saved stations survive a load() round-trip', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.toggleMrtSaved(station('Jurong East', ['NS1', 'EW24']));
      // A fresh model on the same prefs sees the saved station.
      final m2 = AppModel.forTesting();
      await m2.load();
      expect(m2.savedMrtStations.length, 1);
      expect(m2.savedMrtStations.first.name, 'Jurong East');
      expect(m2.savedMrtStations.first.codes, ['NS1', 'EW24']);
    });

    test('corrupt savedMrt JSON falls back to empty list (no crash)',
        () async {
      SharedPreferences.setMockInitialValues({'lyne.savedMrt': '{ not json'});
      final m = AppModel.forTesting();
      await m.load();
      expect(m.savedMrtStations, isEmpty);
    });
  });

  group('Recents', () {
    test('addRecent deduplicates case-insensitively, caps at 8, newest first',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      for (var i = 0; i < 12; i++) {
        m.addRecent('q$i');
      }
      m.addRecent('Q11'); // case-insensitive dup of 'q11'
      expect(m.recents.length, 8);
      expect(m.recents.first.toLowerCase(), 'q11');
    });
  });

  group('Persistence', () {
    test('pins survive a load() round-trip', () async {
      // Seed prefs with two pins, then construct a fresh AppModel and load.
      SharedPreferences.setMockInitialValues({
        'lyne.pins': '[{"code":"53009","nickname":"Home stop"},'
            '{"code":"83139","nickname":"Work","tracked":["15","88"]}]',
      });
      final m = AppModel.forTesting();
      await m.load();
      expect(m.pins.length, 2);
      expect(m.pins[0].code, '53009');
      expect(m.pins[0].nickname, 'Home stop');
      expect(m.pins[0].tracked, isNull); // omitted in JSON → null
      expect(m.pins[1].code, '83139');
      expect(m.pins[1].tracked, ['15', '88']);
    });

    test('rename persists', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('17171');
      m.rename('17171', 'Clementi');
      expect(m.pinForCode('17171')?.nickname, 'Clementi');
      // Second model on same prefs sees the renamed nickname.
      final m2 = AppModel.forTesting();
      await m2.load();
      expect(m2.pinForCode('17171')?.nickname, 'Clementi');
    });

    test('corrupt pins JSON falls back to empty list (no crash)', () async {
      SharedPreferences.setMockInitialValues({
        'lyne.pins': '{ not json',
      });
      final m = AppModel.forTesting();
      // ignore: invalid_use_of_visible_for_testing_member
      expect(() async => m.load(), returnsNormally);
      await m.load();
      expect(m.pins, isEmpty);
    });
  });

  // ─── What's New (changelog after an update) ─────────────────
  group('whatsNewVersion', () {
    test('fresh install (still onboarding) never shows What’s New',
        () async {
      SharedPreferences.setMockInitialValues({});
      final m = AppModel.forTesting();
      await m.load();
      m.setCurrentVersion('2.0.0'); // a version with a changelog entry
      expect(m.onboardingDone, isFalse);
      expect(m.whatsNewVersion, isNull);
    });

    test('returning user on a version with release notes sees it once',
        () async {
      // Onboarded before, no version ever recorded — the bootstrap case.
      SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
      final m = AppModel.forTesting();
      await m.load();
      m.setCurrentVersion('2.0.0');
      expect(m.whatsNewVersion, '2.0.0');

      m.markWhatsNewSeen();
      expect(m.whatsNewVersion, isNull); // acknowledged — won't show again
    });

    test('a version with no changelog entry shows nothing', () async {
      SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
      final m = AppModel.forTesting();
      await m.load();
      m.setCurrentVersion('0.0.1-no-such-entry');
      expect(m.whatsNewVersion, isNull);
    });

    test('finishOnboarding pins the version so it never back-fires',
        () async {
      SharedPreferences.setMockInitialValues({});
      final m = AppModel.forTesting();
      await m.load();
      m.setCurrentVersion('2.0.0');
      m.finishOnboarding(); // fresh user completes onboarding
      expect(m.onboardingDone, isTrue);
      expect(m.whatsNewVersion, isNull);
    });

    test('acknowledgement persists across a reload', () async {
      SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
      final m = AppModel.forTesting();
      await m.load();
      m.setCurrentVersion('2.0.0');
      m.markWhatsNewSeen();

      final m2 = AppModel.forTesting();
      await m2.load();
      m2.setCurrentVersion('2.0.0');
      expect(m2.whatsNewVersion, isNull);
    });
  });

  test('debug print suppressed', () {
    debugDefaultTargetPlatformOverride = null;
  });
}
