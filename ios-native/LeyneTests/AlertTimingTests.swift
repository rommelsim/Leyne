// Tests for AlertTiming — the timing + copy rules behind the two alert types.
// Mirrors test/alert_timing_test.dart.

import XCTest
@testable import Leyne

final class AlertTimingTests: XCTestCase {

    func testLeadOptionsAndDefaults() {
        XCTAssertEqual(AlertTiming.leadOptions(.arrival), [1, 2, 5, 10, 15])
        XCTAssertEqual(AlertTiming.leadOptions(.destination), [1, 2, 5, 10, 15, 30])
        XCTAssertEqual(AlertTiming.defaultLead(.arrival), 5)
        XCTAssertEqual(AlertTiming.defaultLead(.destination), 10)
    }

    func testArrivalFireAt() {
        let eta = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AlertTiming.arrivalFireAt(eta, leadMinutes: 5),
                       eta.addingTimeInterval(-300))
        XCTAssertEqual(AlertTiming.arrivalFireAt(eta, leadMinutes: 1),
                       eta.addingTimeInterval(-60))
    }

    func testDestinationFireAt() {
        let board = Date(timeIntervalSince1970: 1_000_000)
        // 4 segments * 90s = 360s; lead 2 min = 120s → +240s.
        XCTAssertEqual(
            AlertTiming.destinationFireAt(arrivalAtBoard: board, boardIndex: 2,
                                          destIndex: 6, leadMinutes: 2),
            board.addingTimeInterval(240))
        // Negative segment count clamps to zero.
        XCTAssertEqual(
            AlertTiming.destinationFireAt(arrivalAtBoard: board, boardIndex: 6,
                                          destIndex: 2, leadMinutes: 0),
            board)
    }

    func testCopy() {
        XCTAssertEqual(AlertTiming.arrivalTitle("153"), "Bus 153 arriving soon")
        XCTAssertEqual(
            AlertTiming.arrivalBody(stopName: "Farrer Rd Stn Exit B", leadMinutes: 5),
            "Farrer Rd Stn Exit B · 5 min to arrival")
        XCTAssertEqual(
            AlertTiming.arrivalBody(stopName: "X", leadMinutes: 1), "X · Arriving now")
        XCTAssertEqual(AlertTiming.destinationTitle(), "Your stop is next")
        XCTAssertEqual(
            AlertTiming.destinationBody(destName: "Hougang Ctrl Int", leadMinutes: 10),
            "Hougang Ctrl Int · Arriving in 10 min")
        XCTAssertEqual(
            AlertTiming.summary(kind: .arrival, busNo: "153",
                                stopName: "Farrer Rd Stn Exit B", leadMinutes: 5),
            "We'll notify you 5 min before Bus 153 arrives at Farrer Rd Stn Exit B.")
        XCTAssertEqual(
            AlertTiming.summary(kind: .destination, busNo: "165",
                                stopName: "Hougang Ctrl Int", leadMinutes: 10),
            "We'll notify you 10 min before Bus 165 reaches Hougang Ctrl Int.")
    }

    func testLabels() {
        XCTAssertEqual(AlertTiming.leadLabel(1), "When bus is arriving")
        XCTAssertEqual(AlertTiming.leadLabel(5), "5 minutes before")
        XCTAssertEqual(AlertTiming.leadRowSubtitle(5), "5 min before arrival")
        XCTAssertEqual(AlertTiming.leadRowSubtitle(1), "When arriving")
    }
}
