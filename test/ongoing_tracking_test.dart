// Tests for the new alert/tracking logic added in the Android parity work:
//   • the ongoing "live tracking" notification lifecycle (toggleOngoing) and
//     its bug fixes (clear-on-disable, replace-different-bus),
//   • setAllTracked master-toggle edge cases,
//   • rescheduleIfNeeded gating.
//
// AppModel.forTesting() is used so the 1 s tick timer doesn't run. The
// permission_handler / flutter_local_notifications platform channels are
// stubbed because setNotificationsEnabled / clearAll reach them.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/state/app_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannels() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
          case 'checkServiceStatus':
            return 1; // granted
          case 'requestPermissions':
            return {for (final p in (call.arguments as List).cast<int>()) p: 1};
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        switch (call.method) {
          case 'initialize':
          case 'requestNotificationsPermission':
          case 'requestExactAlarmsPermission':
            return true;
          case 'pendingNotificationRequests':
          case 'getActiveNotifications':
            return <Map<String, Object?>>[];
          default:
            return null;
        }
      },
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockChannels();
  });

  group('Ongoing tracker lifecycle', () {
    test('activates for a key; the same tap deactivates', () async {
      final m = AppModel.forTesting();
      await m.load();
      expect(m.isOngoingActive(busNo: '65', stopCode: '53061'), isFalse);
      expect(m.ongoingKey, isNull);

      await m.toggleOngoing(busNo: '65', stopCode: '53061', stopName: 'Stop');
      expect(m.ongoingKey, '65@53061');
      expect(m.isOngoingActive(busNo: '65', stopCode: '53061'), isTrue);

      await m.toggleOngoing(busNo: '65', stopCode: '53061', stopName: 'Stop');
      expect(m.ongoingKey, isNull);
      expect(m.isOngoingActive(busNo: '65', stopCode: '53061'), isFalse);
    });

    test('starting a different bus replaces the previous tracker (one at a time)',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.toggleOngoing(busNo: '65', stopCode: '53061', stopName: 'Stop');
      await m.toggleOngoing(busNo: '88', stopCode: '53061', stopName: 'Stop');
      expect(m.ongoingKey, '88@53061');
      expect(m.isOngoingActive(busNo: '65', stopCode: '53061'), isFalse);
      expect(m.isOngoingActive(busNo: '88', stopCode: '53061'), isTrue);
    });

    test('disabling notifications stops the tracker (regression: leak fix)',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.toggleOngoing(busNo: '65', stopCode: '53061', stopName: 'Stop');
      expect(m.ongoingKey, isNotNull);

      await m.setNotificationsEnabled(false);
      expect(m.ongoingKey, isNull,
          reason: 'an ongoing tracker must not survive notifications being '
              'turned off — it could never fire');
    });
  });

  group('setAllTracked master toggle', () {
    test('tracked:true on an unpinned stop pins it tracking all', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.setAllTracked(code: 'X', allNos: ['10', '14'], tracked: true);
      expect(m.isPinned('X'), isTrue);
      expect(m.allTracked('X'), isTrue);
    });

    test('tracked:true promotes a partial-subset pin back to all', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.toggleTracked(code: 'X', busNo: '10', allNos: ['10', '14', '16']);
      expect(m.allTracked('X'), isFalse); // tracking only 10
      m.setAllTracked(code: 'X', allNos: ['10', '14', '16'], tracked: true);
      expect(m.allTracked('X'), isTrue);
    });

    test('tracked:false on a pinned stop unpins it', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.togglePin('X');
      expect(m.isPinned('X'), isTrue);
      m.setAllTracked(code: 'X', allNos: ['10'], tracked: false);
      expect(m.isPinned('X'), isFalse);
    });

    test('tracked:false on an unpinned stop is a no-op (no spurious pin)',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      m.setAllTracked(code: 'X', allNos: ['10'], tracked: false);
      expect(m.isPinned('X'), isFalse);
    });
  });

  group('rescheduleIfNeeded', () {
    test('completes without throwing when notifications are off', () async {
      final m = AppModel.forTesting();
      await m.load();
      expect(m.notificationsEnabled, isFalse);
      await expectLater(m.rescheduleIfNeeded(), completes);
    });
  });
}
