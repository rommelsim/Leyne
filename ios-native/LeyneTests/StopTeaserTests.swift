// Unit tests for stopTeaser(...) — the collapsed stop-card summary line
// ("5 buses · next in 3 min") that replaces the inline bus list on the Home
// and Favourites cards. Pure logic; no view state.

import XCTest
@testable import Leyne

final class StopTeaserTests: XCTestCase {

    // ─── No arrivals → no teaser ──────────────────────────
    func testEmptyReturnsNil() {
        XCTAssertNil(stopTeaser(count: 0, soonestEtaSec: 120))
        XCTAssertNil(stopTeaser(count: 0, soonestEtaSec: 0))
    }

    // ─── Singular vs plural noun ──────────────────────────
    func testCountNoun() {
        XCTAssertEqual(stopTeaser(count: 1, soonestEtaSec: 180)?.countText, "1 bus")
        XCTAssertEqual(stopTeaser(count: 2, soonestEtaSec: 180)?.countText, "2 buses")
        XCTAssertEqual(stopTeaser(count: 12, soonestEtaSec: 180)?.countText, "12 buses")
    }

    // ─── Timing text mirrors fmtETA (round DOWN) ──────────
    func testWhenMinutes() {
        // 3:49 → "3 min"
        XCTAssertEqual(stopTeaser(count: 3, soonestEtaSec: 229)?.whenText, "next in 3 min")
        // 1:59 → "1 min"
        XCTAssertEqual(stopTeaser(count: 1, soonestEtaSec: 119)?.whenText, "next in 1 min")
    }

    // ─── Sub-minute / arriving collapses to "next now" ────
    func testWhenArriving() {
        XCTAssertEqual(stopTeaser(count: 4, soonestEtaSec: 59)?.whenText, "next now")
        XCTAssertEqual(stopTeaser(count: 4, soonestEtaSec: 0)?.whenText, "next now")
        XCTAssertEqual(stopTeaser(count: 4, soonestEtaSec: -30)?.whenText, "next now")
    }
}
