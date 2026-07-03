// BusAlert — one configured notification alert (the persisted unit behind
// the notifications-redesign). Two kinds, mirroring AlertTiming.AlertKind:
//
//   • arrival     — "notify me when my bus reaches MY STOP". Set from the Stop
//                   view; re-armed each tick from the live ETA at the boarding
//                   stop, `lead` minutes before.
//   • destination — "notify me when my bus reaches MY DESTINATION". Set from
//                   the Bus view; fires `lead` minutes before the bus is
//                   estimated to reach the chosen alight stop. The Bus view
//                   computes the absolute fireAt at set time (no per-stop LTA
//                   times to recompute from), so the model itself stores only
//                   the identity — see NotificationsService.scheduleDestinationAlert.
//
// Kept deliberately small: identity is `<kind>:<busNo>@<stopCode>` so the same
// bus+stop pair upserts in place, and equality / hashCode key off that id.

import '../data/alert_timing.dart';

class BusAlert {
  BusAlert({
    required this.kind,
    required this.busNo,
    required this.stopCode,
    required this.stopName,
    required this.leadMinutes,
    this.dest = '',
    String? boardStopCode,
    this.disabled,
  }) : boardStopCode = boardStopCode ?? stopCode;

  /// The alert kind — arrival (at your boarding stop) or destination (at your
  /// chosen alight stop).
  final AlertKind kind;

  /// Service number, e.g. "88", "158", "21A".
  final String busNo;

  /// The stop the alert fires for: the boarding stop for `arrival`, the alight
  /// stop for `destination`.
  final String stopCode;

  /// Display name for [stopCode].
  final String stopName;

  /// Headsign ("Towards …") for display — may be empty.
  final String dest;

  /// The stop the bus was opened from. For `destination` this is the boarding
  /// stop whose live ETA grounds the destination fire-time estimate; for
  /// `arrival` it equals [stopCode].
  final String boardStopCode;

  /// Lead time in minutes — fire this many minutes before the estimated arrival.
  final int leadMinutes;

  /// Paused flag, stored inverted-and-optional so alerts persisted before
  /// this field existed decode as active (missing key → null → enabled).
  /// Toggling OFF pauses the alert in place; it does NOT delete it. Mirrors
  /// iOS BusAlert.disabled exactly (ios-native/Leyne/BusAlert.swift).
  final bool? disabled;

  /// True unless explicitly paused. Old persisted alerts (no `disabled`
  /// key) decode as enabled.
  bool get enabled => !(disabled ?? false);

  /// Stable identity: `<kind>:<busNo>@<stopCode>`.
  static String makeId(AlertKind kind, String busNo, String stopCode) =>
      '${kind.name}:$busNo@$stopCode';

  String get id => makeId(kind, busNo, stopCode);

  BusAlert copyWith({
    AlertKind? kind,
    String? busNo,
    String? stopCode,
    String? stopName,
    String? dest,
    String? boardStopCode,
    int? leadMinutes,
    bool? disabled,
  }) =>
      BusAlert(
        kind: kind ?? this.kind,
        busNo: busNo ?? this.busNo,
        stopCode: stopCode ?? this.stopCode,
        stopName: stopName ?? this.stopName,
        dest: dest ?? this.dest,
        boardStopCode: boardStopCode ?? this.boardStopCode,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        disabled: disabled ?? this.disabled,
      );

  /// Returns a copy with [disabled] set to reflect `on`: null when resuming
  /// (so a resumed alert is indistinguishable from one that was never
  /// paused), `true` when pausing. [copyWith]'s `??` convention can't
  /// express "clear back to null", so pause/resume goes through this
  /// instead — see AppModel.setAlertEnabled.
  BusAlert withEnabled(bool on) => BusAlert(
        kind: kind,
        busNo: busNo,
        stopCode: stopCode,
        stopName: stopName,
        dest: dest,
        boardStopCode: boardStopCode,
        leadMinutes: leadMinutes,
        disabled: on ? null : true,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'busNo': busNo,
        'stopCode': stopCode,
        'stopName': stopName,
        'dest': dest,
        'boardStopCode': boardStopCode,
        'leadMinutes': leadMinutes,
        if (disabled != null) 'disabled': disabled,
      };

  factory BusAlert.fromJson(Map<String, dynamic> j) => BusAlert(
        kind: AlertKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => AlertKind.arrival,
        ),
        busNo: j['busNo'] as String,
        stopCode: j['stopCode'] as String,
        stopName: (j['stopName'] as String?) ?? '',
        dest: (j['dest'] as String?) ?? '',
        boardStopCode: (j['boardStopCode'] as String?) ?? j['stopCode'] as String,
        leadMinutes: (j['leadMinutes'] as num?)?.toInt() ?? 1,
        disabled: j['disabled'] as bool?,
      );

  @override
  bool operator ==(Object other) => other is BusAlert && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
