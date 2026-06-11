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

import '../data/alert_timing.dart';
import '../data/data_store.dart' show ArrivalState, ArrivalStateKind;
import '../data/models.dart';
import '../state/app_model.dart' show Pin;
import '../state/bus_alert.dart';

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

  /// Separate low-importance channel for the ongoing "live tracking"
  /// notification (the Android stand-in for an iOS Live Activity). Low
  /// importance + silent so the per-tick ETA updates never buzz.
  static const String _trackChannelId = 'leyne.tracking';
  static const String _trackChannelName = 'Live tracking';
  static const String _trackChannelDescription =
      'An ongoing notification that follows a bus you are tracking.';
  static const String _trackIdPrefix = 'track.';
  // Fixed id — only one tracker runs at a time (mirrors iOS's single Live
  // Activity), so re-`show()`ing this id updates the existing notification.
  static const int _ongoingNotifId = 0x7e1ea0;

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

    // Silent, low-importance channel for the ongoing live-tracking
    // notification — updates must not vibrate or ping every tick.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _trackChannelId,
        _trackChannelName,
        description: _trackChannelDescription,
        importance: Importance.low,
        enableVibration: false,
        playSound: false,
      ),
    );
  }

  // ─── Ongoing "live tracking" notification (Live Activity analog) ──
  //
  // Shows a persistent, silent notification that follows one bus's ETA.
  // Re-call [showOngoing] with a fresh `etaSec` to update it in place
  // (the fixed id + `onlyAlertOnce` keep it quiet). Updates are driven
  // from AppModel's 1 s tick, so the countdown stays live WHILE THE APP
  // IS RUNNING. A fully background tracker (updates after the OS suspends
  // the isolate) would need a native foreground service — not built yet;
  // the `ongoing` flag still pins it in the shade until the bus arrives
  // or the user stops tracking.

  /// Show or update the ongoing tracker. Pass `finished: true` when the
  /// bus has arrived — that flips it to a dismissable, non-ongoing final
  /// state ("Arriving now") instead of a live countdown.
  Future<void> showOngoing({
    required String busNo,
    required String dest,
    required String stopCode,
    required String stopName,
    required int etaSec,
    bool finished = false,
  }) async {
    if (!_initialized) return;
    // Floor to whole minutes so the ongoing notification matches the app's
    // `fmtEta` (etaSec ~/ 60). Using ceil read one minute higher than the bus
    // screen for the same ETA; sub-minute now reads "Arriving now" like the
    // app's "Arr".
    final mins = etaSec ~/ 60;
    final body = (etaSec <= 0 || mins == 0)
        ? 'Arriving now · $stopName'
        : 'Arrives in $mins min · $stopName';
    try {
      await _plugin.show(
        _ongoingNotifId,
        'Bus $busNo → $dest',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _trackChannelId,
            _trackChannelName,
            channelDescription: _trackChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: !finished,
            autoCancel: finished,
            onlyAlertOnce: true,
            showWhen: false,
            category: AndroidNotificationCategory.transport,
            ticker: 'Tracking bus $busNo',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        payload: '$_trackIdPrefix$stopCode.$busNo',
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[notif] ongoing show failed: $e');
      }
    }
  }

  /// Cancels the ongoing tracker.
  Future<void> stopOngoing() async {
    if (!_initialized) return;
    await _plugin.cancel(_ongoingNotifId);
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
    if (!_initialized) return;
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

  // ─── Configurable BusAlert scheduling (notifications redesign) ─────────
  //
  // The single source of truth is AppModel._alerts. `scheduleAlerts` re-arms
  // every `arrival` alert from the live ETA on each coarse tick, and sweeps
  // any of our pending requests whose alert no longer exists. `destination`
  // alerts carry a precomputed absolute fire time (no per-stop LTA times to
  // recompute from), so they're scheduled once via [scheduleDestinationAlert]
  // when the alert is upserted and are NOT re-armed here — the sweep below
  // preserves them.
  //
  // Payload identifiers reuse the prefixes so the existing _idPrefix /
  // _alightIdPrefix orphan sweeps stay correct:
  //   arrival     → `arrival.<stopCode>.<busNo>`   (= old per-service id)
  //   destination → `alight.<busNo>.<stopCode>`    (= old alight id shape)

  static int _notifIdFor(String identifier) => identifier.hashCode & 0x7fffffff;

  // Arrival alerts fire at two fixed leads (3 min + 1 min), so the identifier
  // carries the lead so the two requests are distinct and swept independently.
  // The tap payload is the same string; main.dart parses parts[1]/[2] (stop /
  // bus) and ignores any trailing lead segment, so routing is unaffected.
  static String _arrivalIdentifier(BusAlert a, int lead) =>
      '$_idPrefix${a.stopCode}.${a.busNo}.$lead';

  static String _destinationIdentifier(BusAlert a) =>
      '$_alightIdPrefix${a.busNo}.${a.stopCode}';

  /// Re-arm all `arrival` alerts from the live arrivals store, and sweep any
  /// of our pending requests no longer backed by an alert. `destination`
  /// alerts already pending (scheduled at upsert time) are left intact.
  Future<void> scheduleAlerts(
    List<BusAlert> alerts,
    Map<String, ArrivalState> arrivals,
  ) async {
    if (!_initialized) return;
    final now = DateTime.now();

    // The identifiers we want to keep alive: every destination alert's id +
    // every arrival alert whose live ETA still places its fire time ahead.
    final keepIds = <String>{};

    // (Re)schedule arrival alerts off the live ETA.
    for (final a in alerts) {
      if (a.kind != AlertKind.arrival) {
        keepIds.add(_destinationIdentifier(a));
        continue;
      }
      final arrivalDate = _liveArrivalDate(arrivals, a.stopCode, a.busNo);
      if (arrivalDate == null) continue;
      // Fixed dual reminder — 3 min before AND 1 min before (AlertTiming
      // .arrivalLeads). Each lead is its own scheduled notification with a
      // distinct identifier so they fire (and get swept) independently. A lead
      // whose fire time has already passed (the bus is already closer than that
      // lead) is skipped; the nearer reminder still fires.
      for (final lead in AlertTiming.arrivalLeads) {
        final fireAt = AlertTiming.arrivalFireAt(arrivalDate, lead);
        if (!fireAt.isAfter(now.add(const Duration(seconds: 1)))) continue;
        final identifier = _arrivalIdentifier(a, lead);
        keepIds.add(identifier);
        await _zonedSchedule(
          identifier: identifier,
          fireAt: fireAt,
          title: AlertTiming.arrivalTitle(a.busNo, lead),
          body: AlertTiming.arrivalBody(a.stopName, lead),
          groupKey: 'leyne.arrivals.${a.stopCode}',
        );
      }
    }

    // Orphan sweep — cancel any pending request we own (arrival OR destination
    // payload prefix) that isn't in keepIds.
    final pending = await _plugin.pendingNotificationRequests();
    for (final r in pending) {
      final payload = r.payload;
      if (payload == null) continue;
      final owned =
          payload.startsWith(_idPrefix) || payload.startsWith(_alightIdPrefix);
      if (!owned) continue;
      if (!keepIds.contains(payload)) {
        await _plugin.cancel(r.id);
      }
    }
  }

  /// Schedule a single `destination` alert at the precomputed [fireAt] (the
  /// Bus view computes it via AlertTiming.destinationFireAt at set time).
  /// Replaces any earlier request with the same identifier. Past/near-now
  /// fire times are nudged ~1 s into the future so they still deliver.
  Future<void> scheduleDestinationAlert(BusAlert a, DateTime fireAt) async {
    if (!_initialized) return;
    await _zonedSchedule(
      identifier: _destinationIdentifier(a),
      fireAt: fireAt,
      title: AlertTiming.destinationTitle(),
      body: AlertTiming.destinationBody(a.stopName, a.leadMinutes),
      groupKey: 'leyne.destination',
    );
  }

  /// Cancel the pending request(s) backing [a] (used when an alert is removed).
  /// Arrival alerts have two pending requests (one per fixed lead) to cancel.
  Future<void> cancelAlert(BusAlert a) async {
    if (!_initialized) return;
    if (a.kind == AlertKind.arrival) {
      for (final lead in AlertTiming.arrivalLeads) {
        await _plugin.cancel(_notifIdFor(_arrivalIdentifier(a, lead)));
      }
    } else {
      await _plugin.cancel(_notifIdFor(_destinationIdentifier(a)));
    }
  }

  /// Live arrival time for [busNo] at [stopCode] from the arrivals store, or
  /// null when the stop isn't loaded or the service isn't currently arriving.
  DateTime? _liveArrivalDate(
    Map<String, ArrivalState> arrivals,
    String stopCode,
    String busNo,
  ) {
    final state = arrivals[stopCode];
    if (state == null || state.kind != ArrivalStateKind.loaded) return null;
    for (final s in state.services) {
      if (s.no == busNo) return s.arrivalDate;
    }
    return null;
  }

  /// Shared zonedSchedule body for the configurable alerts. Idempotent by
  /// identifier (same id → same notif id → replaces).
  Future<void> _zonedSchedule({
    required String identifier,
    required DateTime fireAt,
    required String title,
    required String body,
    required String groupKey,
  }) async {
    final now = DateTime.now();
    final effective = fireAt.isAfter(now.add(const Duration(seconds: 1)))
        ? fireAt
        : now.add(const Duration(seconds: 1));
    final tzFire = tz.TZDateTime.from(effective, tz.local);
    try {
      await _plugin.zonedSchedule(
        _notifIdFor(identifier),
        title,
        body,
        tzFire,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            groupKey: groupKey,
            ticker: title,
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
        print('[notif] schedule $identifier failed: $e');
      }
    }
  }

  /// Schedules a one-shot heads-up at `fireAt` so the user knows the bus
  /// is approaching their alight stop. Replaces any prior alight alert.
  /// If `fireAt` is in the past or within ~1 s, fires immediately (the
  /// user picked a stop the bus is already at the 2-stop threshold for).
  ///
  /// The identifier (also the payload) uses the alight stop CODE, not
  /// the user-facing name — names like "Opp Blk 211" contain characters
  /// that would make the payload awkward to parse if it ever became
  /// load-bearing for routing.
  Future<void> scheduleAlightAlert({
    required String busNo,
    required String alightStopCode,
    required String alightStopName,
    required DateTime fireAt,
  }) async {
    if (!_initialized) return;
    await cancelAlightAlerts();

    final identifier = '$_alightIdPrefix$busNo.$alightStopCode';
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
    if (!_initialized) return;
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
          // walkMin == 0 means "no location fix yet", not "user is
          // already at the stop". The old "head down" suffix assumed
          // the latter and read wrong when location was unknown — drop
          // it and just show the label.
          body: card.walkMin > 0
              ? '${card.label} · ${card.walkMin} min walk'
              : card.label,
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
