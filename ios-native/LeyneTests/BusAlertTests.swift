// Tests for BusAlert (Codable + id) and the AppModel alert CRUD surface.
// AppModel is @MainActor, so every test that touches it is annotated.

import XCTest
@testable import Leyne

final class BusAlertTests: XCTestCase {

    // MARK: BusAlert model

    func testCodableRoundTrip() throws {
        let a = BusAlert(kind: .destination, busNo: "165", stopCode: "11389",
                         stopName: "Hougang Ctrl Int", dest: "Bishan Int",
                         boardStopCode: "59009", leadMinutes: 10)
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(BusAlert.self, from: data)
        XCTAssertEqual(a, back)
    }

    func testIdStabilityAndShape() {
        let arr = BusAlert(kind: .arrival, busNo: "153", stopCode: "80071",
                           stopName: "X", dest: "", boardStopCode: "80071",
                           leadMinutes: 5)
        XCTAssertEqual(arr.id, "arrival:153@80071")
        let dest = BusAlert(kind: .destination, busNo: "153", stopCode: "80071",
                            stopName: "X", dest: "", boardStopCode: "11009",
                            leadMinutes: 5)
        XCTAssertEqual(dest.id, "destination:153@80071")
        // Same kind+bus+stop ⇒ same id regardless of lead/board/name.
        let arr2 = BusAlert(kind: .arrival, busNo: "153", stopCode: "80071",
                            stopName: "Y", dest: "Z", boardStopCode: "80071",
                            leadMinutes: 15)
        XCTAssertEqual(arr.id, arr2.id)
    }

    // MARK: AppModel CRUD

    @MainActor
    private func freshModel() -> AppModel {
        // Start from a clean alert store so persisted state from earlier
        // runs doesn't bleed in.
        UserDefaults.standard.removeObject(forKey: "leyne.alerts")
        let m = AppModel()
        m.alerts = []
        return m
    }

    @MainActor
    func testUpsertAppendsThenReplaces() {
        let m = freshModel()
        let a = BusAlert(kind: .arrival, busNo: "12", stopCode: "100",
                         stopName: "Stop A", dest: "", boardStopCode: "100",
                         leadMinutes: 5)
        m.upsertAlert(a)
        XCTAssertEqual(m.alerts.count, 1)
        XCTAssertEqual(m.alert(kind: .arrival, busNo: "12", stopCode: "100")?.leadMinutes, 5)

        // Same id, new lead ⇒ replace in place (no duplicate).
        var a2 = a
        a2.leadMinutes = 10
        m.upsertAlert(a2)
        XCTAssertEqual(m.alerts.count, 1)
        XCTAssertEqual(m.alert(kind: .arrival, busNo: "12", stopCode: "100")?.leadMinutes, 10)
    }

    @MainActor
    func testDistinctKindsCoexist() {
        let m = freshModel()
        m.upsertAlert(BusAlert(kind: .arrival, busNo: "9", stopCode: "200",
                               stopName: "B", dest: "", boardStopCode: "200",
                               leadMinutes: 5))
        m.upsertAlert(BusAlert(kind: .destination, busNo: "9", stopCode: "200",
                               stopName: "B", dest: "", boardStopCode: "200",
                               leadMinutes: 10))
        XCTAssertEqual(m.alerts.count, 2)
        XCTAssertNotNil(m.alert(kind: .arrival, busNo: "9", stopCode: "200"))
        XCTAssertNotNil(m.alert(kind: .destination, busNo: "9", stopCode: "200"))
    }

    @MainActor
    func testRemoveById() {
        let m = freshModel()
        let a = BusAlert(kind: .arrival, busNo: "5", stopCode: "300",
                         stopName: "C", dest: "", boardStopCode: "300",
                         leadMinutes: 2)
        m.upsertAlert(a)
        m.removeAlert(id: a.id)
        XCTAssertTrue(m.alerts.isEmpty)
        XCTAssertNil(m.alert(kind: .arrival, busNo: "5", stopCode: "300"))
    }

    @MainActor
    func testRemoveByKindBusStop() {
        let m = freshModel()
        m.upsertAlert(BusAlert(kind: .arrival, busNo: "7", stopCode: "400",
                               stopName: "D", dest: "", boardStopCode: "400",
                               leadMinutes: 5))
        m.removeAlerts(kind: .arrival, busNo: "7", stopCode: "400")
        XCTAssertNil(m.alert(kind: .arrival, busNo: "7", stopCode: "400"))
    }

    // Alerts and pinned-card visibility are INDEPENDENT concepts: setting an
    // alert must not pin/track the card, and pinning must not create an alert.
    @MainActor
    func testAlertsAreIndependentOfPinTracking() {
        let m = freshModel()
        m.upsertAlert(BusAlert(kind: .arrival, busNo: "21", stopCode: "500",
                               stopName: "E", dest: "", boardStopCode: "500",
                               leadMinutes: 5))
        XCTAssertNotNil(m.alert(kind: .arrival, busNo: "21", stopCode: "500"))
        XCTAssertFalse(m.isPinned("500"))                      // alert ≠ pin
        XCTAssertFalse(m.isTracked(code: "500", busNo: "21"))  // alert ≠ card visibility

        m.togglePin(code: "500")                                // pin the card (all shown)
        XCTAssertTrue(m.isTracked(code: "500", busNo: "21"))    // nil tracked = all
        XCTAssertNotNil(m.alert(kind: .arrival, busNo: "21", stopCode: "500")) // alert untouched
    }
}
