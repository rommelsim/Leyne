// Parity with Flutter test/route_mrt_test.dart — guards the Swift resolveMrtStation
// against Swift-specific regex/casing divergence from the Dart implementation.

import XCTest
import SwiftUI
@testable import Leyne

final class MrtStationsTests: XCTestCase {
    func testSimpleSingleLine() {
        let s = resolveMrtStation("Clementi Stn")
        XCTAssertEqual(s?.name, "Clementi")
        XCTAssertEqual(s?.codes.map(\.code), ["EW23"])
    }

    func testPrefixAndExitSuffix() {
        XCTAssertEqual(resolveMrtStation("Opp Clementi Stn")?.name, "Clementi")
        XCTAssertEqual(resolveMrtStation("Bishan Stn Exit C")?.name, "Bishan")
    }

    func testAbbreviationExpansion() {
        // Screenshot example: "Farrer Rd Stn" → Farrer Road (CC20).
        let farrer = resolveMrtStation("Farrer Rd Stn Exit A")
        XCTAssertEqual(farrer?.name, "Farrer Road")
        XCTAssertEqual(farrer?.codes.first?.code, "CC20")
        XCTAssertEqual(resolveMrtStation("Bt Batok Stn")?.name, "Bukit Batok")
    }

    func testInterchangeReturnsAllCodes() {
        let je = resolveMrtStation("Jurong East Stn")
        XCTAssertEqual(je?.name, "Jurong East")
        XCTAssertEqual(je?.codes.map(\.code), ["EW24", "NS1"])
    }

    func testNonStationAndUnknownReturnNil() {
        XCTAssertNil(resolveMrtStation("Opp Blk 2"))     // not a station
        XCTAssertNil(resolveMrtStation("Clementi Int"))  // no "Stn" token
        XCTAssertNil(resolveMrtStation("Nonexistent Stn")) // unknown
    }
}
