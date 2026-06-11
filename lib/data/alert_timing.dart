// AlertTiming — pure timing + copy rules for the two notification alert types,
// factored out so they can be unit-tested without a notification host and kept
// identical to the iOS side (ios-native/Leyne/AlertTiming.swift).
//
//   • arrival     — fire `lead` minutes before the bus reaches YOUR stop.
//   • destination — fire `lead` minutes before the bus is estimated to reach
//                   your chosen alight stop (~90 s per route segment past the
//                   boarding stop; LTA gives no per-stop times, so this is an
//                   estimate surfaced with the quiet "~" cue).

enum AlertKind { arrival, destination }

class AlertTiming {
  const AlertTiming._();

  /// Estimated travel time between adjacent stops (no per-stop LTA times).
  static const int perStopSec = 90;

  /// Fixed dual reminders for arrival alerts: notify 3 minutes before, then
  /// again 1 minute before the bus reaches the stop. The user no longer picks a
  /// lead time (QOL: "don't let the user choose — stick with 1 and 3 min").
  /// Ordered far → near so the scheduling/copy reads naturally.
  static const List<int> arrivalLeads = [3, 1];

  /// Row subtitle for an arrival alert now that the lead is fixed.
  static const String arrivalRowSubtitle = '3 & 1 min before arrival';

  /// Lead-time choices offered in the "Notify me when" sheet. Destination
  /// alerts add a 30-min option (you may want a long head start to pack up).
  static List<int> leadOptions(AlertKind kind) => kind == AlertKind.destination
      ? const [1, 2, 5, 10, 15, 30]
      : const [1, 2, 5, 10, 15];

  /// Pre-selected lead when first opening the sheet (matches the mockup).
  static int defaultLead(AlertKind kind) =>
      kind == AlertKind.destination ? 10 : 5;

  /// At-my-stop fire time: `lead` minutes before the live ETA.
  static DateTime arrivalFireAt(DateTime arrivalAtStop, int leadMinutes) =>
      arrivalAtStop.subtract(Duration(minutes: leadMinutes));

  /// At-destination fire time: `lead` minutes before the bus is estimated to
  /// reach the destination — the boarding ETA plus one [perStop] per segment
  /// from the boarding stop to the destination.
  static DateTime destinationFireAt({
    required DateTime arrivalAtBoard,
    required int boardIndex,
    required int destIndex,
    required int leadMinutes,
    int perStop = perStopSec,
  }) {
    final segs = (destIndex - boardIndex).clamp(0, 1 << 30);
    return arrivalAtBoard
        .add(Duration(seconds: segs * perStop))
        .subtract(Duration(minutes: leadMinutes));
  }

  // ── Sheet labels ──────────────────────────────────────────────────────────

  /// Primary label for a lead choice ("When bus is arriving" / "5 minutes before").
  static String leadLabel(int leadMinutes) =>
      leadMinutes <= 1 ? 'When bus is arriving' : '$leadMinutes minutes before';

  /// Dim sublabel under the lead choice ("~ 1 min before" / "~ 5 min before").
  static String leadSubLabel(int leadMinutes) =>
      leadMinutes <= 1 ? '~ 1 min before' : '~ $leadMinutes min before';

  /// Row subtitle on the inline toggle / manage list ("5 min before arrival").
  static String leadRowSubtitle(int leadMinutes) => leadMinutes <= 1
      ? 'When arriving'
      : '$leadMinutes min before arrival';

  /// Footer summary line in the sheet.
  static String summary({
    required AlertKind kind,
    required String busNo,
    required String stopName,
    required int leadMinutes,
  }) {
    if (kind == AlertKind.destination) {
      final lead = leadMinutes <= 1 ? 'when' : '$leadMinutes min before';
      return "We'll notify you $lead Bus $busNo reaches $stopName.";
    }
    // Arrival alerts now fire twice at fixed leads — see [arrivalLeads].
    return "We'll notify you 3 min and again 1 min before Bus $busNo "
        "arrives at $stopName.";
  }

  // ── Notification copy ───────────────────────────────────────────────────────

  /// Notification title — leading icon + bus + how-soon, front-loaded so it's
  /// scannable at a glance. The icon differs by lead: a clock for the 3-min
  /// heads-up, a bus pulling in for the 1-min final call.
  static String arrivalTitle(String busNo, int leadMinutes) => leadMinutes <= 1
      ? '🚍 Bus $busNo — arriving now'
      : '🕒 Bus $busNo — $leadMinutes min away';

  /// Notification body — the stop, with a "get ready" nudge on the final call.
  static String arrivalBody(String stopName, int leadMinutes) =>
      leadMinutes <= 1 ? 'Get ready — $stopName' : 'Heading to $stopName';

  static String destinationTitle() => 'Your stop is next';

  static String destinationBody(String destName, int leadMinutes) =>
      leadMinutes <= 1
          ? '$destName · Arriving now'
          : '$destName · Arriving in $leadMinutes min';
}
