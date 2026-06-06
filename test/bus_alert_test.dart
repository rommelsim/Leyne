// Tests for the notifications-redesign model + AppModel CRUD:
//   • BusAlert JSON round-trip + id stability,
//   • AppModel upsert / remove / alertFor,
//   • the toggleTracked shim (one arrival path) + isTracked reflecting alerts.
//
// AppModel.forTesting() is used so the 1 s tick timer doesn't run. The
// permission_handler / flutter_local_notifications channels are stubbed
// because rescheduleIfNeeded (driven from upsert/remove) reaches them.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/data/alert_timing.dart';
import 'package:lyne/state/app_model.dart';
import 'package:lyne/state/bus_alert.dart';

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
            return 1;
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

  group('BusAlert model', () {
    test('JSON round-trip preserves every field', () {
      final a = BusAlert(
        kind: AlertKind.destination,
        busNo: '158',
        stopCode: '17009',
        stopName: 'Clementi Int',
        dest: 'Boon Lay',
        boardStopCode: '17171',
        leadMinutes: 10,
      );
      final b = BusAlert.fromJson(a.toJson());
      expect(b.kind, AlertKind.destination);
      expect(b.busNo, '158');
      expect(b.stopCode, '17009');
      expect(b.stopName, 'Clementi Int');
      expect(b.dest, 'Boon Lay');
      expect(b.boardStopCode, '17171');
      expect(b.leadMinutes, 10);
      expect(b, equals(a)); // == by id
    });

    test('id is stable and kind-scoped', () {
      const id = 'arrival:88@53061';
      expect(BusAlert.makeId(AlertKind.arrival, '88', '53061'), id);
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      );
      expect(a.id, id);
      // Same bus+stop, different kind → different id.
      expect(BusAlert.makeId(AlertKind.destination, '88', '53061'),
          isNot(id));
    });

    test('boardStopCode defaults to stopCode', () {
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      );
      expect(a.boardStopCode, '53061');
    });
  });

  group('AppModel alert CRUD', () {
    test('upsert adds, then replaces by id', () async {
      final m = AppModel.forTesting();
      await m.load();
      expect(m.alerts, isEmpty);

      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop A',
        leadMinutes: 5,
      ));
      expect(m.alerts.length, 1);
      expect(m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061')
          ?.leadMinutes, 5);

      // Same id → replaces, not appends.
      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop A',
        leadMinutes: 15,
      ));
      expect(m.alerts.length, 1);
      expect(m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061')
          ?.leadMinutes, 15);
    });

    test('remove + removeAlertsFor', () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'A',
        leadMinutes: 5,
      ));
      await m.upsertAlert(BusAlert(
        kind: AlertKind.destination,
        busNo: '88',
        stopCode: '99999',
        stopName: 'B',
        leadMinutes: 10,
      ));
      expect(m.alerts.length, 2);

      await m.removeAlertsFor(
          kind: AlertKind.arrival, busNo: '88', stopCode: '53061');
      expect(m.alerts.length, 1);
      expect(m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061'),
          isNull);

      await m.removeAlert(BusAlert.makeId(AlertKind.destination, '88', '99999'));
      expect(m.alerts, isEmpty);
    });

    test('alerts survive a load() round-trip', () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.destination,
        busNo: '158',
        stopCode: '17009',
        stopName: 'Clementi Int',
        dest: 'Boon Lay',
        boardStopCode: '17171',
        leadMinutes: 30,
      ));

      final m2 = AppModel.forTesting();
      await m2.load();
      expect(m2.alerts.length, 1);
      final a = m2.alerts.first;
      expect(a.kind, AlertKind.destination);
      expect(a.busNo, '158');
      expect(a.stopName, 'Clementi Int');
      expect(a.boardStopCode, '17171');
      expect(a.leadMinutes, 30);
    });
  });

  group('alerts vs pin tracking (independent)', () {
    test('an arrival alert does not pin/track; pinning does not alert', () async {
      final m = AppModel.forTesting();
      await m.load();
      m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      ));
      expect(
          m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061'),
          isNotNull);
      expect(m.isPinned('53061'), isFalse); // alert ≠ pin
      expect(m.isTracked(code: '53061', busNo: '88'),
          isFalse); // alert ≠ card visibility

      m.togglePin('53061'); // pin the card (all shown)
      expect(m.isTracked(code: '53061', busNo: '88'),
          isTrue); // nil tracked = all
      expect(
          m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061'),
          isNotNull); // alert untouched
    });
  });

  group('Legacy migration', () {
    test('tracked subset → arrival alerts (lead 1) on first load', () async {
      SharedPreferences.setMockInitialValues({
        'lyne.pins':
            '[{"code":"83139","nickname":"Work","tracked":["15","88"]}]',
      });
      final m = AppModel.forTesting();
      await m.load();
      expect(m.alerts.length, 2);
      for (final no in ['15', '88']) {
        final a =
            m.alertFor(kind: AlertKind.arrival, busNo: no, stopCode: '83139');
        expect(a, isNotNull, reason: 'bus $no should migrate');
        expect(a!.leadMinutes, 1);
      }
    });

    test('present alerts key skips migration', () async {
      SharedPreferences.setMockInitialValues({
        'lyne.pins':
            '[{"code":"83139","nickname":"Work","tracked":["15"]}]',
        'lyne.alerts': '[]',
      });
      final m = AppModel.forTesting();
      await m.load();
      expect(m.alerts, isEmpty);
    });
  });
}
