// AlertTiming — pure timing + copy rules for the two notification alert types,
// factored out so they can be unit-tested without a notification host. The
// TIMING logic mirrors the Flutter side (lib/data/alert_timing.dart) exactly.
// The arrival notification COPY diverged from Android as of the
// design-greendark voice pass — see the note above arrivalTitle/arrivalBody.
//
//   • arrival     — fire `lead` minutes before the bus reaches YOUR stop.
//   • destination — fire `lead` minutes before the bus is estimated to reach
//                   your chosen alight stop (~90 s per route segment past the
//                   boarding stop; LTA gives no per-stop times, so this is an
//                   estimate surfaced with the quiet "~" cue).

import Foundation

enum AlertKind: String, Codable, Equatable { case arrival, destination }

extension Load {
    /// Confident, concrete crowd clause for the final-call notification body
    /// (e.g. "Seats are available"). Matches the voice of the in-app crowd
    /// word (`Load.label`) but phrased as a sentence fragment.
    var notificationClause: String {
        switch self {
        case .sea: return "Seats are available"
        case .sda: return "Standing room only"
        case .lsd: return "It's crowded — expect to stand"
        }
    }
}

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
    //
    // "Departly green-dark" voice pass (design-greendark): confident and
    // concrete, no emoji clutter — the title states the fact ("Bus 14 is
    // arriving" / "Bus 14 is 3 min away"), the body gives the one instruction
    // that matters right now.
    //
    // Crowd is woven into the body ONLY on the 1-min final call, never the
    // 3-min heads-up. Both leads have `load` plumbed through from the same
    // live `Service` the ETA came from (see NotificationsManager
    // .scheduleArrivalAlerts), so the data isn't missing at 3 min out — it's
    // withheld on purpose: occupancy on a bus still 3 minutes away is exactly
    // the kind of fast-changing read that's stale by the time it matters,
    // the same reasoning this file already applied to omitting a stops-away
    // count from arrival bodies. At 1 min out the snapshot is close enough to
    // fire time to say it plainly.
    //
    // No stops-away count in the body, at either lead: scheduleArrivalAlerts
    // only computes an ETA at schedule time, not a live GPS stops-away figure
    // (that's Live Activity/Dynamic Island territory, which DOES push a real
    // `stopsAway`). Saying "2 stops away" here would be inventing a number
    // this call site doesn't have.

    /// Notification title — states the fact, front-loaded so it's scannable
    /// at a glance.
    static func arrivalTitle(_ busNo: String, leadMinutes: Int) -> String {
        leadMinutes <= 1 ? "Bus \(busNo) is arriving"
                         : "Bus \(busNo) is \(leadMinutes) min away"
    }

    /// Notification body — WHICH bus this is (destination) and WHERE you catch
    /// it (stop), with crowd woven in when known (final call only — see the
    /// note above) and a direct action on the final call.
    ///
    /// The 3-min body used to be a bare "Heading to <stop>." — left over from
    /// the greendark voice pass, and the last surface still speaking it
    /// (owner 2026-07-25, "notification is using old code"). Two problems: it
    /// read as if YOU were heading there, and it repeated the stop the title
    /// already implied while omitting the one thing that disambiguates a bus
    /// number — its destination. The app's own board says "Bus 165 · to
    /// Clementi Int" everywhere; the notification now says the same.
    static func arrivalBody(stopName: String, leadMinutes: Int,
                            dest: String? = nil, load: Load? = nil) -> String {
        // `dest` is absent on legacy/unresolved rows — the clause is dropped
        // rather than guessed, same rule the rest of this file follows.
        let route = dest.map { "to \($0) · " } ?? ""
        guard leadMinutes <= 1 else { return "\(route)\(stopName)" }
        let crowd = load.map { " \($0.notificationClause)." } ?? ""
        return "\(route)\(stopName).\(crowd) Head to the stop now."
    }

    static func destinationTitle() -> String { "Your stop is next" }

    static func destinationBody(destName: String, leadMinutes: Int) -> String {
        leadMinutes <= 1 ? "\(destName) · Arriving now"
                         : "\(destName) · Arriving in \(leadMinutes) min"
    }
}
