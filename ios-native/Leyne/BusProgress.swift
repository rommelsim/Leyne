// BusProgress — pure route-progress math for the Bus view, factored out of
// SoftBusView so it can be unit-tested without a SwiftUI host.
//
// These are the rules behind "where is the bus on its route", which the map
// pin, the approaching card, the live-position callout and the route timeline
// all share — so they can never disagree. (That disagreement was the class of
// bug that drew a pin 1.3 km away while the text claimed "0 stops away".)
//
// Mirrors lib/data/bus_progress.dart on the Flutter side — keep the two in step.

import Foundation
import CoreLocation

enum BusProgress {

    /// Index of the route stop nearest to `coord`, or nil for an empty list.
    static func nearestIndex(stops: [CLLocationCoordinate2D],
                             to coord: CLLocationCoordinate2D) -> Int? {
        guard !stops.isEmpty else { return nil }
        return stops.enumerated().min(by: {
            haversine($0.element.latitude, $0.element.longitude,
                      coord.latitude, coord.longitude)
                < haversine($1.element.latitude, $1.element.longitude,
                            coord.latitude, coord.longitude)
        })?.offset
    }

    /// The bus's route index. Prefer the GPS-derived nearest stop (clamped to
    /// your stop, since the approaching bus is always behind you); otherwise
    /// estimate from the ETA (~90 s/stop, aged by `elapsedSec`). Returns 0 at
    /// the origin (`youIndex <= 0`).
    static func busIndex(youIndex: Int,
                         gpsNearest: Int?,
                         etaSec: Int,
                         elapsedSec: Double) -> Int {
        guard youIndex > 0 else { return 0 }
        if let n = gpsNearest { return min(max(0, n), youIndex) }
        let eta = max(0, Double(etaSec) - elapsedSec)
        let back = min(Double(youIndex), eta / 90.0)
        return min(max(0, Int((Double(youIndex) - back).rounded())), youIndex)
    }

    /// First stop kept in the timeline: two before the bus (or your stop when
    /// the bus is unknown), clamped. The segment then runs to the terminus so
    /// the route visibly leads to its destination instead of stopping at you.
    static func timelineLead(busIndex: Int?, youIndex: Int, stopsCount: Int) -> Int {
        guard stopsCount > 0 else { return 0 }
        let pivot = min(busIndex ?? youIndex, youIndex)
        return max(0, min(pivot - 2, stopsCount - 1))
    }

    /// State of stop `idx` given the bus + boarding positions. `canMarkBoard`
    /// is false in full-route (bus search) mode, where there is no your-stop.
    static func stopState(idx: Int, busIndex: Int?, youIndex: Int,
                          canMarkBoard: Bool) -> RouteStopState {
        if let b = busIndex, idx == b { return .here }
        if canMarkBoard, idx == youIndex { return .board }
        if idx < (busIndex ?? -1) { return .past }
        return .next
    }

    /// Whether a stop's connector is "green" — track the bus has already
    /// covered. Only passed stops and the bus's own stop; the boarding/alight
    /// stop is ahead of the bus, so it stays grey (no detached green segment).
    static func connectorIsGreen(_ state: RouteStopState) -> Bool {
        switch state {
        case .past, .here:           return true
        case .board, .alight, .next: return false
        }
    }

    /// The bus row's lower half greys out — the bus hasn't travelled past its
    /// own stop — so the green trail ends exactly at the bus.
    static func lowerConnectorIsGreen(_ state: RouteStopState) -> Bool {
        state != .here && connectorIsGreen(state)
    }
}
