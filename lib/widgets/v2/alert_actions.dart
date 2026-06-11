// One-tap arrival-alert toggle + Undo — replaces the old multi-step
// "Notify me when" sheet + confirmation flow. Setting an alert is now instant
// and reversible: tap to arm, tap again to remove, or hit Undo on the snackbar.
// Shared by the Home and Stop screens so the behaviour is identical.

import 'package:flutter/material.dart';

import '../../data/alert_timing.dart';
import '../../state/app_model.dart';
import '../../state/bus_alert.dart';

/// Toggle the arrival alert for [busNo] at [stopCode] in a single tap, showing
/// an Undo snackbar. Returns the new state (true = alert now on).
///
/// Adding an alert also enables notifications + requests permission on first use
/// (see AppModel.upsertAlert) — tapping "Notify" IS the opt-in.
Future<bool> toggleArrivalAlert({
  required String busNo,
  required String stopCode,
  required String stopName,
  String dest = '',
}) async {
  final m = AppModel.shared;
  final existing =
      m.alertFor(kind: AlertKind.arrival, busNo: busNo, stopCode: stopCode);
  if (existing != null) {
    await m.removeAlert(existing.id);
    _alertSnack(
      'Alert off for Bus $busNo',
      onUndo: () =>
          _addArrivalAlert(busNo, stopCode, stopName, dest),
    );
    return false;
  }
  await _addArrivalAlert(busNo, stopCode, stopName, dest);
  _alertSnack(
    "We'll alert you 3 & 1 min before Bus $busNo",
    onUndo: () => m.removeAlertsFor(
      kind: AlertKind.arrival,
      busNo: busNo,
      stopCode: stopCode,
    ),
  );
  return true;
}

Future<void> _addArrivalAlert(
  String busNo,
  String stopCode,
  String stopName,
  String dest,
) =>
    AppModel.shared.upsertAlert(BusAlert(
      kind: AlertKind.arrival,
      busNo: busNo,
      stopCode: stopCode,
      stopName: stopName,
      dest: dest,
      // Lead is fixed (3 min + 1 min, see AlertTiming.arrivalLeads).
      leadMinutes: 1,
    ));

/// Floating snackbar with an Undo action, shown via the app-wide messenger so it
/// works from any screen (including over a just-popped route).
void _alertSnack(String message, {required VoidCallback onUndo}) {
  final messenger = lyneMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}
