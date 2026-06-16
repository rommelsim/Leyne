// Background alerts refresh — WorkManager entrypoint.
//
// Android's WorkManager calls `callbackDispatcher` in an isolate that is
// SEPARATE from the main Flutter isolate. The running app's singletons
// (DataStore.shared, AppModel.shared, NotificationsService.shared) live in
// the main isolate and are NOT accessible here. This file therefore
// constructs the minimal set of objects needed to:
//   1. Init flutter_local_notifications (one `show()` call — no tz/AlarmManager).
//   2. Call LtaService.shared.trainServiceAlerts() to get the current alerts.
//   3. Diff against a snapshot persisted in SharedPreferences (since the
//      in-memory _trainAlerts list in DataStore is not available).
//   4. Fire `NotificationsService.shared.notifyTrainDisruption(...)` for each
//      newly-appeared line, gated on the `lyne.notifications` pref.
//
// The WorkManager task is registered at app startup in main.dart and runs
// approximately every 15 minutes (Android's OS-enforced minimum).
// Exact timing is up to the OS scheduler / Doze / battery optimisations.
//
// CAVEAT: because this is a new Flutter engine instance, the `http` client
// and LtaService re-initialise from scratch each task run. This is fine —
// the task is infrequent and short-lived. The API key is read from
// LtaConfig which is a compile-time const, so no async pref load is needed
// for authentication.

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/lta_models.dart';
import '../data/lta_service.dart';
import 'notifications.dart';

/// The WorkManager task name — must match the registration in main.dart.
const kAlertsRefreshTask = 'leyne.alertsRefresh';

/// SharedPreferences key used to persist the last-known set of disrupted
/// line codes across isolates (the in-memory DataStore is not shared).
const _kBgAlertIdsKey = 'lyne.bg.alertIds';

/// Top-level callback invoked by WorkManager in the background isolate.
/// Must be annotated `@pragma('vm:entry-point')` so the Dart tree-shaker
/// keeps it reachable from native code.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kAlertsRefreshTask) return true; // unknown task — ack

    // Every background isolate needs this before calling any Flutter plugin.
    WidgetsFlutterBinding.ensureInitialized();

    // Init notifications plugin in this isolate so show() works.
    await NotificationsService.shared.init();

    final prefs = await SharedPreferences.getInstance();

    // Gate: only skip when the user explicitly turned notifications off.
    // Default ON when unset, matching AppModel (so a new user who never set a
    // bus alert still gets background disruption pushes — the iOS parity fix).
    final notifEnabled = prefs.getBool('lyne.notifications') ?? true;
    if (!notifEnabled) return true;

    // Load the last-persisted disrupted line codes so we can diff.
    final raw = prefs.getStringList(_kBgAlertIdsKey) ?? const <String>[];
    final previousIds = raw.toSet();

    try {
      final api = LtaService.shared;
      final r = await api.trainServiceAlerts();

      if (r.status != 2) {
        // No disruptions — persist empty set and return.
        await prefs.setStringList(_kBgAlertIdsKey, const []);
        return true;
      }

      final currentIds = r.affectedSegments.map((s) => s.line).toSet();

      // Notify for lines that are new since the last background run.
      for (final seg in r.affectedSegments) {
        if (!previousIds.contains(seg.line)) {
          final title = '${_shortLabel(seg.line)} · disrupted';
          // Build a one-sentence summary matching DataStore._trainAlertSummary.
          final detail = _summary(seg.line, r.messages);
          await NotificationsService.shared.notifyTrainDisruption(
            lineCode: seg.line,
            title: title,
            detail: detail,
          );
        }
      }

      // Persist the current set for the next run's diff.
      await prefs.setStringList(_kBgAlertIdsKey, currentIds.toList());
    } catch (_) {
      // Network failure — leave the persisted snapshot untouched so the
      // next successful run can still diff correctly.
    }

    return true; // ack to WorkManager — false would retry immediately
  });
}

// ─── Helpers (mirrors DataStore / MRTLine logic, kept local to avoid
//     importing the full app dependency graph into the background isolate) ───

/// Short human-readable label for a LTA line code, e.g. "NEL" → "NE Line".
/// Mirrors iOS MRTLine.shortLabel(forLta:) and Dart MRTLine.shortLabelForLta.
String _shortLabel(String ltaCode) {
  switch (ltaCode.toUpperCase()) {
    case 'EWL':
      return 'East–West Line';
    case 'NSL':
      return 'NS Line';
    case 'NEL':
      return 'NE Line';
    case 'CCL':
      return 'Circle Line';
    case 'DTL':
      return 'Downtown Line';
    case 'TEL':
      return 'Thomson–East Coast Line';
    default:
      return ltaCode;
  }
}

/// One-sentence disruption summary from the LTA messages list.
/// Mirrors DataStore._trainAlertSummary.
String _summary(String lineCode, List<LtaTrainMessage> messages) {
  final raw =
      messages
          .firstWhere(
            (m) => m.content.contains(lineCode),
            orElse: () =>
                messages.isEmpty
                    ? const LtaTrainMessage(content: '')
                    : messages.first,
          )
          .content
          .replaceAll('\n', ' ')
          .trim();
  if (raw.isEmpty) return 'Service disruption · tap to dismiss';
  final dot = raw.indexOf('.');
  final head = dot > 0 ? raw.substring(0, dot) : raw;
  return '$head · tap to dismiss';
}
