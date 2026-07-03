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

  group('BusAlert pause/resume (disabled/enabled)', () {
    test('a freshly-created alert is enabled by default', () {
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      );
      expect(a.disabled, isNull);
      expect(a.enabled, isTrue);
    });

    test('old JSON with no disabled key decodes as enabled (back-compat)', () {
      final b = BusAlert.fromJson(const {
        'kind': 'arrival',
        'busNo': '88',
        'stopCode': '53061',
        'stopName': 'Stop',
        'leadMinutes': 5,
      });
      expect(b.disabled, isNull);
      expect(b.enabled, isTrue);
    });

    test('withEnabled(false) pauses; withEnabled(true) resumes to null', () {
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      );
      final paused = a.withEnabled(false);
      expect(paused.disabled, isTrue);
      expect(paused.enabled, isFalse);
      // id/identity untouched by pausing.
      expect(paused.id, a.id);
      expect(paused, equals(a));

      final resumed = paused.withEnabled(true);
      expect(resumed.disabled, isNull); // back to the "never paused" shape
      expect(resumed.enabled, isTrue);
    });

    test('toJson omits disabled when null, includes it when set', () {
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      );
      expect(a.toJson().containsKey('disabled'), isFalse);
      expect(a.withEnabled(false).toJson()['disabled'], isTrue);
    });

    test('disabled round-trips through JSON', () {
      final a = BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop',
        leadMinutes: 5,
      ).withEnabled(false);
      final b = BusAlert.fromJson(a.toJson());
      expect(b.disabled, isTrue);
      expect(b.enabled, isFalse);
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

  group('AppModel alert pause/resume', () {
    test('setAlertEnabled(false) pauses in place — alert is not removed', () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.arrival,
        busNo: '88',
        stopCode: '53061',
        stopName: 'Stop A',
        leadMinutes: 5,
      ));
      final id = BusAlert.makeId(AlertKind.arrival, '88', '53061');

      await m.setAlertEnabled(id, false);
      expect(m.alerts.length, 1); // still present
      expect(m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061')
          ?.enabled, isFalse);

      await m.setAlertEnabled(id, true);
      expect(m.alertFor(kind: AlertKind.arrival, busNo: '88', stopCode: '53061')
          ?.enabled, isTrue);
    });

    test('setAlertEnabled is a no-op for an unknown id', () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.setAlertEnabled('does-not-exist', false);
      expect(m.alerts, isEmpty);
    });

    test('paused state survives a load() round-trip', () async {
      final m = AppModel.forTesting();
      await m.load();
      await m.upsertAlert(BusAlert(
        kind: AlertKind.destination,
        busNo: '158',
        stopCode: '17009',
        stopName: 'Clementi Int',
        boardStopCode: '17171',
        leadMinutes: 10,
      ));
      await m.setAlertEnabled(
          BusAlert.makeId(AlertKind.destination, '158', '17009'), false);

      final m2 = AppModel.forTesting();
      await m2.load();
      expect(m2.alerts.single.enabled, isFalse);
    });
  });

  group('AppModel reorderAlerts', () {
    test('reorders alerts to the given id order and persists', () async {
      final m = AppModel.forTesting();
      await m.load();
      for (final no in ['15', '88', '21']) {
        await m.upsertAlert(BusAlert(
          kind: AlertKind.arrival,
          busNo: no,
          stopCode: '53061',
          stopName: 'Stop',
          leadMinutes: 5,
        ));
      }
      expect(m.alerts.map((a) => a.busNo).toList(), ['15', '88', '21']);

      final newOrder = [
        BusAlert.makeId(AlertKind.arrival, '21', '53061'),
        BusAlert.makeId(AlertKind.arrival, '15', '53061'),
        BusAlert.makeId(AlertKind.arrival, '88', '53061'),
      ];
      m.reorderAlerts(newOrder);
      expect(m.alerts.map((a) => a.busNo).toList(), ['21', '15', '88']);

      final m2 = AppModel.forTesting();
      await m2.load();
      expect(m2.alerts.map((a) => a.busNo).toList(), ['21', '15', '88']);
    });

    test('ids absent from newIds keep their relative order, appended after',
        () async {
      final m = AppModel.forTesting();
      await m.load();
      for (final no in ['15', '88', '21']) {
        await m.upsertAlert(BusAlert(
          kind: AlertKind.arrival,
          busNo: no,
          stopCode: '53061',
          stopName: 'Stop',
          leadMinutes: 5,
        ));
      }
      // Only reorder within a subset (e.g. one section of a sectioned UI) —
      // '88' is left out and should land after the reordered pair.
      m.reorderAlerts([
        BusAlert.makeId(AlertKind.arrival, '21', '53061'),
        BusAlert.makeId(AlertKind.arrival, '15', '53061'),
      ]);
      expect(m.alerts.map((a) => a.busNo).toList(), ['21', '15', '88']);
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
