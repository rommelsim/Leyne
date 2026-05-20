// Shared between the app (ActivityKit) and the LyneWidgets extension
// (ActivityConfiguration). Keep dependency-free so the widget can compile it.

import ActivityKit
import Foundation

struct LyneActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Whole-minute ETA; <=0 means arriving/now.
        var etaMinutes: Int
        /// Human status, e.g. "Arrives in 3 min", "Now", "Bus is here".
        var status: String
        /// Real stops between the bus and your stop; -1 if unknown.
        var stopsAway: Int
        var arrived: Bool
    }

    var busNo: String
    var dest: String
    var stopName: String
    var stopCode: String
}
