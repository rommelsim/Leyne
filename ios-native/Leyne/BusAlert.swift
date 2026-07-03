// BusAlert — one persisted notification request the user set up.
//
//   • arrival     — "tell me when Bus N reaches MY stop". `stopCode` is the
//                   boarding stop; `boardStopCode == stopCode`.
//   • destination — "tell me when Bus N reaches MY destination". `stopCode`
//                   is the chosen alight stop; `boardStopCode` is the stop the
//                   bus was opened from (so we can recompute the fire time
//                   from the boarding ETA + per-segment estimate).
//
// `id` is derived (kind + bus + stop) so upsert/remove are by-identity — one
// alert per (kind, bus, stop) combo, and re-setting it replaces in place.

import Foundation

struct BusAlert: Codable, Identifiable, Equatable {
    var kind: AlertKind
    var busNo: String
    var stopCode: String      // arrival: boarding stop; destination: alight stop
    var stopName: String
    var dest: String          // headsign for display (may be "")
    var boardStopCode: String // destination: stop the bus was opened from; arrival: == stopCode
    var leadMinutes: Int
    /// Paused flag, stored inverted-and-optional so alerts persisted before
    /// this field existed decode as active (missing key → nil → enabled).
    /// Toggle OFF pauses the alert in place; it does NOT delete it.
    var disabled: Bool? = nil

    var enabled: Bool { !(disabled ?? false) }

    var id: String { "\(kind.rawValue):\(busNo)@\(stopCode)" }
}
