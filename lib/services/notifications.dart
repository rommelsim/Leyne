// Arrival-alert notifications — schedules native Android system
// notifications (and iOS on the Flutter target if anyone runs that path)
// at absolute fire times, so a tracked bus's "1-minute warning" arrives
// on the Lock Screen even when Leyne is closed.
//
// Mirrors the iOS-native `NotificationsManager` in
// `ios-native/Leyne/AppModel.swift`: per-service identifier
// (`arrival.<stopCode>.<busNo>`), fire 60 s before the live arrival
// time, idempotent reschedule that cancels orphans whose underlying
// service is no longer tracked.
//
// Why zonedSchedule and not show(): we want delivery while the app is
// backgrounded or terminated. zonedSchedule registers the alarm with the
// Android system AlarmManager via flutter_local_notifications, which
// keeps firing across app lifecycles (and survives reboot via the boot
// receiver declared in AndroidManifest.xml).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import '../state/app_model.dart' show Pin;

/// Resolved status of the Android `POST_NOTIFICATIONS` permission. Drives
/// the warning row + Open Settings shortcut on NotificationsScreen.
enum NotifPermStatus { granted, denied, permanentlyDenied, notDetermined }

class NotificationsService {
  NotificationsService._();
  static final NotificationsService shared = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Single Android notification channel — `Arrival alerts`. Created once
  /// at init. iOS uses no channels; the per-notification settings (sound,
  /// importance) are passed via DarwinNotificationDetails at schedule
  /// time.
  static const String _channelId = 'leyne.arrivals';
  static const String _channelName = 'Arrival alerts';
  static const String _channelDescription =
      'Fires ~1 minute before a tracked bus reaches its stop.';

  /// Notification identifier prefix — used so the orphan sweep can skip
  /// any unrelated requests that happen to live in the pending queue.
  static const String _idPrefix = 'arrival.';

  /// Fire offset before the live arrival time (seconds). 60 matches the
  /// design's "1 min" framing.
  static const int _leadSec = 60;

  bool _initialized = false;

  /// Tap callback set by main() — receives the payload string from a
  /// tapped notification (e.g. `arrival.17249.282` or
  /// `alight.282.Clementi Int`) and drives the in-app navigation. Set
  /// before init() so the initial launch tap (from a cold start) lands.
  void Function(String payload)? onNotificationTapped;

  /// Idempotent. Loads the tz database (zonedSchedule converts wall-clock
  /// times → TZDateTime, which needs the tz dataset initialised once),
  /// then creates the Android notification channel + sets up the plugin.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tzdata.initializeTimeZones();
    // Use the device's local zone — sb has no tz override, so the OS
    // value (Asia/Singapore here) is what zonedSchedule converts against.
    try {
      tz.setLocalLocation(tz.getLocation(tz.local.name));
    } catch (_) {
      /* fall back to the package's UTC default — schedule still fires */
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      // We request permission separately via permission_handler so the
      // toggle drives the prompt at the moment the user opts in, not at
      // app launch. Set these to false to avoid the double-prompt.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onNotificationTapped?.call(payload);
      },
    );

    // Cold-start tap: if the user launched the app by tapping a
    // notification, the plugin queues the response and exposes it here
    // (vs. the live `onDidReceiveNotificationResponse` callback which
    // fires only when the app is already running). Replay it once.
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final payload = details?.notificationResponse?.payload;
      if (payload != null) {
        // Defer to next event-loop turn so main() finishes wiring the
        // navigator before we try to push a route onto it.
        Future.microtask(() => onNotificationTapped?.call(payload));
      }
    }

    // Pre-create the Android channel. Importance.high → heads-up banner,
    // matches what iOS's `.timeSensitive` interruption level achieves.
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );
  }

  /// Reads the system `POST_NOTIFICATIONS` permission state. Android
  /// 13+ requires the runtime permission; older versions return granted
  /// because there's no opt-in concept.
  Future<NotifPermStatus> currentStatus() async {
    final s = await Permission.notification.status;
    if (s.isGranted) return NotifPermStatus.granted;
    if (s.isPermanentlyDenied) return NotifPermStatus.permanentlyDenied;
    if (s.isDenied) return NotifPermStatus.denied;
    return NotifPermStatus.notDetermined;
  }

  /// Resolves the Android schedule mode to use for `zonedSchedule`.
  /// When `SCHEDULE_EXACT_ALARM` is granted (auto-granted on Android
  /// 12–13, user-granted via system Settings on Android 14+) we use
  /// the exact mode so heads-up alerts fire at the intended second —
  /// matching the immediacy of WhatsApp / SMS notifications. If the
  /// permission is denied we degrade gracefully to inexact, which
  /// fires within Android's Doze maintenance window (~minutes of slop).
  Future<AndroidScheduleMode> _scheduleMode() async {
    final s = await Permission.scheduleExactAlarm.status;
    return s.isGranted
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// On Android 14+, asking for `SCHEDULE_EXACT_ALARM` shoots the user
  /// into the system's "Alarms & reminders" Settings screen. Best
  /// effort: if the user denies, we fall back to inexact and the
  /// notification still fires — just batched. Returns true iff the
  /// permission is granted after the request resolves.
  Future<bool> requestExactAlarmAuthorization() async {
    final s = await Permission.scheduleExactAlarm.request();
    return s.isGranted;
  }

  /// Triggers the Android 13+ runtime permission prompt. Older Android
  /// versions resolve to granted with no UI.
  Future<bool> requestAuthorization() async {
    final s = await Permission.notification.request();
    return s.isGranted;
  }

  /// Cancels every pending arrival alert we own.
  Future<void> clearAll() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final r in pending) {
      // Our notification ids are integer hashes of "arrival.<stop>.<no>";
      // the payload string preserves the prefixed identifier so we can
      // skip orphans not owned by this service.
      if (r.payload != null && r.payload!.startsWith(_idPrefix)) {
        await _plugin.cancel(r.id);
      }
    }
  }

  // ─── On-bus alight alerts ─────────────────────────────────
  //
  // A separate category from arrival alerts. Arrival alerts fire BEFORE
  // boarding (bus approaching the user's stop); alight alerts fire
  // DURING the ride (user is on the bus, approaching their drop-off).
  // Single active ride at a time — `scheduleAlightAlert` cancels any
  // prior alight request before adding the new one.

  static const String _alightIdPrefix = 'alight.';

  /// Schedules a one-shot heads-up at `fireAt` so the user knows the bus
  /// is approaching their alight stop. Replaces any prior alight alert.
  /// If `fireAt` is in the past or within ~1 s, fires immediately (the
  /// user picked a stop the bus is already at the 2-stop threshold for).
  Future<void> scheduleAlightAlert({
    required String busNo,
    required String alightStopName,
    required DateTime fireAt,
  }) async {
    if (!_initialized) return;
    await cancelAlightAlerts();

    final identifier = '$_alightIdPrefix$busNo.$alightStopName';
    final notifId = identifier.hashCode & 0x7fffffff;
    final now = DateTime.now();
    final effectiveFireAt = fireAt.isAfter(now.add(const Duration(seconds: 1)))
        ? fireAt
        : now.add(const Duration(seconds: 1));
    final tzFire = tz.TZDateTime.from(effectiveFireAt, tz.local);

    try {
      await _plugin.zonedSchedule(
        notifId,
        'Alight at $alightStopName',
        'Bus $busNo is approaching your stop — get ready.',
        tzFire,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            groupKey: 'leyne.alight',
            ticker: 'Alight at $alightStopName',
          ),
          iOS: const DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        payload: identifier,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[notif] alight schedule failed: $e');
      }
    }
  }

  /// Cancels every pending alight alert we own.
  Future<void> cancelAlightAlerts() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final r in pending) {
      if (r.payload != null && r.payload!.startsWith(_alightIdPrefix)) {
        await _plugin.cancel(r.id);
      }
    }
  }

  /// Recomputes the desired schedule given the live pins + cards.
  /// Idempotent: requests with the same identifier replace earlier ones,
  /// and any pending arrival alert whose underlying service is no longer
  /// tracked gets cancelled.
  Future<void> scheduleArrivalAlerts({
    required List<Pin> pins,
    required List<CardModel> cards,
  }) async {
    if (!_initialized) return;
    final now = DateTime.now();
    final desired = <_DesiredAlert>[];

    for (final card in cards) {
      Pin? pin;
      for (final p in pins) {
        if (p.code == card.stopCode) { pin = p; break; }
      }
      if (pin == null) continue;
      final tracked = pin.tracked == null ? null : Set<String>.from(pin.tracked!);

      for (final s in card.services) {
        if (tracked != null && !tracked.contains(s.no)) continue;
        final arrives = s.arrivalDate;
        if (arrives == null) continue;
        final fireAt = arrives.subtract(const Duration(seconds: _leadSec));
        if (!fireAt.isAfter(now.add(const Duration(seconds: 1)))) continue;

        desired.add(_DesiredAlert(
          identifier: '$_idPrefix${card.stopCode}.${s.no}',
          fireAt: fireAt,
          title: 'Bus ${s.no} arriving in 1 min',
          body: card.walkMin > 0
              ? '${card.label} · ${card.walkMin} min walk'
              : '${card.label} · head down to the stop',
          stopCode: card.stopCode,
        ));
      }
    }

    final desiredIds = desired.map((d) => d.identifier).toSet();
    final pending = await _plugin.pendingNotificationRequests();
    for (final r in pending) {
      final payload = r.payload;
      if (payload == null || !payload.startsWith(_idPrefix)) continue;
      if (!desiredIds.contains(payload)) {
        await _plugin.cancel(r.id);
      }
    }

    for (final d in desired) {
      final notifId = d.identifier.hashCode & 0x7fffffff;
      final tzFire = tz.TZDateTime.from(d.fireAt, tz.local);
      try {
        await _plugin.zonedSchedule(
          notifId,
          d.title,
          d.body,
          tzFire,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
              groupKey: 'leyne.arrivals.${d.stopCode}',
              ticker: d.title,
            ),
            iOS: const DarwinNotificationDetails(
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          androidScheduleMode: await _scheduleMode(),
          payload: d.identifier,
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[notif] schedule ${d.identifier} failed: $e');
        }
      }
    }
  }
}

class _DesiredAlert {
  final String identifier;
  final DateTime fireAt;
  final String title;
  final String body;
  final String stopCode;
  const _DesiredAlert({
    required this.identifier,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.stopCode,
  });
}
