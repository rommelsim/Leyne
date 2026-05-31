// Shared between the app (ActivityKit) and the LyneWidgets extension
// (ActivityConfiguration). Keep dependency-free so the widget can compile it.

import ActivityKit
import Foundation

struct LeyneActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Whole-minute ETA; <=0 means arriving/now.
        var etaMinutes: Int
        /// Human status, e.g. "Arrives in 3 min", "Now", "Bus is here".
        var status: String
        /// Real stops between the bus and your stop; -1 if unknown.
        var stopsAway: Int
        var arrived: Bool
        /// LTA GPS flag for this arrival. False = scheduled-only ("ghost
        /// bus"); the lock screen / Dynamic Island soften the ETA and show a
        /// SCHEDULED marker so a timetable guess never reads as confident
        /// live tracking. Defaults true so existing call sites are unaffected.
        var monitored: Bool = true
    }

    var busNo: String
    var dest: String
    var stopName: String
    var stopCode: String
}
