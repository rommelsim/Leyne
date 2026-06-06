// Regression tests for the Bus-view route-progress math (BusProgress).
//
// These pin the five bugs fixed on 2026-06-06:
//   1/3/4 — pin vs. text disagreement: the bus index must be grounded in the
//           real GPS fix (nearest stop, clamped to your stop), and only fall
//           back to the ETA estimate when there is no fix.
//   2     — the timeline must run to the terminus (lead is 2 before the bus).
//   5     — the green connector marks only track the bus has covered; the
//           boarding stop stays grey and the green ends exactly at the bus.

import XCTest
import CoreLocation
@testable import Leyne

final class BusProgressTests: XCTestCase {

    // ─── busIndex: GPS-grounded with ETA fallback (bugs 1/3/4) ───
    func testBusIndexClampsGPSToYourStop() {
        // A fix whose nearest stop is *past* you never renders past you.
        XCTAssertEqual(BusProgress.busIndex(youIndex: 5, gpsNearest: 9,
                                            etaSec: 0, elapsedSec: 0), 5)
    }

    func testBusIndexGPSBeatsETA() {
        // Real position (stop 3) wins even when the ETA says "arriving" (which
        // alone would place the bus at your stop). This is the "arriving now
        // but the bus is 1.3 km away" bug.
        XCTAssertEqual(BusProgress.busIndex(youIndex: 5, gpsNearest: 3,
                                            etaSec: 0, elapsedSec: 0), 3)
    }

    func testBusIndexETAFallbackWhenNoFix() {
        // 270 s ≈ 3 stops back from stop 5 → stop 2.
        XCTAssertEqual(BusProgress.busIndex(youIndex: 5, gpsNearest: nil,
                                            etaSec: 270, elapsedSec: 0), 2)
        // Arriving → at your stop.
        XCTAssertEqual(BusProgress.busIndex(youIndex: 5, gpsNearest: nil,
                                            etaSec: 0, elapsedSec: 0), 5)
    }

    func testBusIndexAgesETAByElapsed() {
        // 270 s ETA, 180 s elapsed → ~90 s left → 1 stop back → stop 4.
        XCTAssertEqual(BusProgress.busIndex(youIndex: 5, gpsNearest: nil,
                                            etaSec: 270, elapsedSec: 180), 4)
    }

    func testBusIndexAtOrigin() {
        XCTAssertEqual(BusProgress.busIndex(youIndex: 0, gpsNearest: nil,
                                            etaSec: 999, elapsedSec: 0), 0)
    }

    // ─── nearestIndex ───
    func testNearestIndexSnapsToClosestStop() {
        let stops = [
            CLLocationCoordinate2D(latitude: 1.30, longitude: 103.80),
            CLLocationCoordinate2D(latitude: 1.31, longitude: 103.80),
            CLLocationCoordinate2D(latitude: 1.32, longitude: 103.80),
        ]
        XCTAssertEqual(BusProgress.nearestIndex(
            stops: stops, to: CLLocationCoordinate2D(latitude: 1.319, longitude: 103.80)), 2)
        XCTAssertEqual(BusProgress.nearestIndex(
            stops: stops, to: CLLocationCoordinate2D(latitude: 1.301, longitude: 103.80)), 0)
        XCTAssertNil(BusProgress.nearestIndex(
            stops: [], to: CLLocationCoordinate2D(latitude: 1.3, longitude: 103.8)))
    }

    // ─── timelineLead: segment reaches the terminus (bug 2) ───
    func testTimelineLeadStartsTwoBeforeTheBus() {
        XCTAssertEqual(BusProgress.timelineLead(busIndex: 6, youIndex: 10, stopsCount: 30), 4)
    }

    func testTimelineLeadFallsBackToYourStop() {
        XCTAssertEqual(BusProgress.timelineLead(busIndex: nil, youIndex: 10, stopsCount: 30), 8)
    }

    func testTimelineLeadNeverNegative() {
        XCTAssertEqual(BusProgress.timelineLead(busIndex: 1, youIndex: 1, stopsCount: 30), 0)
    }

    // ─── stopState ───
    func testStopStateAssignsHereBoardPastNext() {
        XCTAssertEqual(BusProgress.stopState(idx: 3, busIndex: 3, youIndex: 6, canMarkBoard: true), .here)
        XCTAssertEqual(BusProgress.stopState(idx: 6, busIndex: 3, youIndex: 6, canMarkBoard: true), .board)
        XCTAssertEqual(BusProgress.stopState(idx: 1, busIndex: 3, youIndex: 6, canMarkBoard: true), .past)
        XCTAssertEqual(BusProgress.stopState(idx: 8, busIndex: 3, youIndex: 6, canMarkBoard: true), .next)
    }

    func testStopStateSuppressesBoardInFullRoute() {
        XCTAssertEqual(BusProgress.stopState(idx: 6, busIndex: 3, youIndex: 6, canMarkBoard: false), .next)
    }

    // ─── connector colours: green = track covered (bug 5) ───
    func testConnectorGreenOnlyThroughTheBus() {
        XCTAssertTrue(BusProgress.connectorIsGreen(.past))
        XCTAssertTrue(BusProgress.connectorIsGreen(.here))
        XCTAssertFalse(BusProgress.connectorIsGreen(.board))   // no detached green at your stop
        XCTAssertFalse(BusProgress.connectorIsGreen(.next))
        XCTAssertFalse(BusProgress.connectorIsGreen(.alight))
    }

    func testLowerConnectorGreysAtTheBus() {
        XCTAssertFalse(BusProgress.lowerConnectorIsGreen(.here))  // green ends at the bus
        XCTAssertTrue(BusProgress.lowerConnectorIsGreen(.past))
    }
}
