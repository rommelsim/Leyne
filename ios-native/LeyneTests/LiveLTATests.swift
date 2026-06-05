// Live integration — hits real LTA DataMall with the configured key.
// Skips (does not fail) if the network/LTA is unreachable in CI.

import XCTest
@testable import Leyne

final class LiveLTATests: XCTestCase {

    func testLiveBusStopsAndArrivals() async throws {
        let api = LTAService.shared

        // 1) Bulk reference dataset returns a real, large stop list.
        let stops: [LTABusStop]
        do {
            stops = try await api.busStops()
        } catch {
            throw XCTSkip("LTA/network unavailable: \(error)")
        }
        XCTAssertGreaterThan(stops.count, 3000, "Singapore has 5000+ bus stops")
        let bishan = stops.first { $0.BusStopCode == "53009" }
        XCTAssertNotNil(bishan, "Bishan Int (53009) should exist")
        XCTAssertFalse(bishan?.Description.isEmpty ?? true)
        XCTAssertTrue((1.0...1.5).contains(bishan?.Latitude ?? 0))   // within SG

        // 2) Live arrivals for a busy stop parse into domain Services.
        let resp = try await api.busArrival(stopCode: "53009")
        XCTAssertEqual(resp.BusStopCode, "53009")
        // Stop may be quiet at odd hours, but the call must succeed & decode.
        for svc in resp.Services where svc.NextBus.hasData {
            XCTAssertFalse(svc.ServiceNo.isEmpty)
            XCTAssertNotNil(svc.NextBus.arrivalDate)
            let mapped = svc.toService(destName: "x")
            XCTAssertGreaterThanOrEqual(mapped.etaSec, 0)
        }
    }

    func testLiveBusServices() async throws {
        do {
            let svcs = try await LTAService.shared.busServices()
            XCTAssertGreaterThan(svcs.count, 300, "SG has hundreds of services")
            XCTAssertTrue(svcs.contains { $0.ServiceNo == "88" })
        } catch {
            throw XCTSkip("LTA/network unavailable: \(error)")
        }
    }
}
