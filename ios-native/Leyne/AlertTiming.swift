// AlertTiming — pure timing + copy rules for the two notification alert types,
// factored out so they can be unit-tested without a notification host and kept
// identical to the Flutter side (lib/data/alert_timing.dart).
//
//   • arrival     — fire `lead` minutes before the bus reaches YOUR stop.
//   • destination — fire `lead` minutes before the bus is estimated to reach
//                   your chosen alight stop (~90 s per route segment past the
//                   boarding stop; LTA gives no per-stop times, so this is an
//                   estimate surfaced with the quiet "~" cue).

import Foundation

enum AlertKind: String, Codable, Equatable { case arrival, destination }

enum AlertTiming {

    /// Estimated travel time between adjacent stops (no per-stop LTA times).
    static let perStopSec = 90

    /// Fixed lead times for arrival alerts: two notifications, 3 min and 1 min
    /// before the bus reaches the stop. Stored/used instead of a user-chosen lead.
    static let arrivalLeads = [3, 1]

    /// Subtitle shown in ManageAlertsView and the active-alert card for arrival rows.
    static let arrivalRowSubtitle = "3 & 1 min before arrival"

    /// Lead-time choices offered in the "Notify me when" sheet. Destination
    /// alerts add a 30-min option (you may want a long head start to pack up).
    /// Arrival alerts no longer present a picker — `arrivalLeads` is fixed.
    static func leadOptions(_ kind: AlertKind) -> [Int] {
        kind == .destination ? [1, 2, 5, 10, 15, 30] : [1, 2, 5, 10, 15]
    }

    /// Pre-selected lead when first opening the sheet (matches the mockup).
    static func defaultLead(_ kind: AlertKind) -> Int {
        kind == .destination ? 10 : 5
    }

    /// At-my-stop fire time: `lead` minutes before the live ETA.
    static func arrivalFireAt(_ arrivalAtStop: Date, leadMinutes: Int) -> Date {
        arrivalAtStop.addingTimeInterval(TimeInterval(-leadMinutes * 60))
    }

    /// At-destination fire time: `lead` minutes before the bus is estimated to
    /// reach the destination — the boarding ETA plus one `perStop` per segment
    /// from the boarding stop to the destination.
    static func destinationFireAt(arrivalAtBoard: Date, boardIndex: Int,
                                  destIndex: Int, leadMinutes: Int,
                                  perStop: Int = perStopSec) -> Date {
        let segs = max(0, destIndex - boardIndex)
        return arrivalAtBoard.addingTimeInterval(
            TimeInterval(segs * perStop - leadMinutes * 60))
    }

    // ── Sheet labels ─────────────────────────────────────────────

    static func leadLabel(_ lead: Int) -> String {
        lead <= 1 ? "When bus is arriving" : "\(lead) minutes before"
    }

    static func leadSubLabel(_ lead: Int) -> String {
        lead <= 1 ? "~ 1 min before" : "~ \(lead) min before"
    }

    static func leadRowSubtitle(_ lead: Int) -> String {
        lead <= 1 ? "When arriving" : "\(lead) min before arrival"
    }

    static func summary(kind: AlertKind, busNo: String, stopName: String,
                        leadMinutes: Int) -> String {
        if kind == .arrival {
            return "We'll notify you 3 min and again 1 min before Bus \(busNo) arrives at \(stopName)."
        }
        let lead = leadMinutes <= 1 ? "when" : "\(leadMinutes) min before"
        return "We'll notify you \(lead) Bus \(busNo) reaches \(stopName)."
    }

    // ── Notification copy ────────────────────────────────────────

    /// Notification title — leading icon + bus + how-soon, front-loaded so it's
    /// scannable at a glance. The icon differs by lead: a clock for the 3-min
    /// heads-up, a bus pulling in for the 1-min final call.
    static func arrivalTitle(_ busNo: String, leadMinutes: Int) -> String {
        leadMinutes <= 1 ? "🚍 Bus \(busNo) — arriving now"
                         : "🕒 Bus \(busNo) — \(leadMinutes) min away"
    }

    /// Notification body — the stop, with a "get ready" nudge on the final call.
    static func arrivalBody(stopName: String, leadMinutes: Int) -> String {
        leadMinutes <= 1 ? "Get ready — \(stopName)" : "Heading to \(stopName)"
    }

    static func destinationTitle() -> String { "Your stop is next" }

    static func destinationBody(destName: String, leadMinutes: Int) -> String {
        leadMinutes <= 1 ? "\(destName) · Arriving now"
                         : "\(destName) · Arriving in \(leadMinutes) min"
    }
}
