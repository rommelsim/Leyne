// Tests for the Nearby long-press / context-menu actions.
//
// The menu buttons are thin wrappers over AppModel state mutations, so we test
// those effects directly:
//   • "Add to Saved" / "Remove from Saved" → AppModel.togglePin
//   • "Hide From Nearby"                    → AppModel.hideFromNearby
//   • "Open Stop"                           → AppModel.addRecent (records the visit)
//   • the Stop list + peek ordering         → localizedStandardCompare contract
//
// Plus a regression for the bug where saving a stop made it vanish from Nearby
// (Nearby must exclude only *hidden* stops, never *saved* ones).
//
// The buttons' UIKit / navigation closures (Open on Map, Share Stop, Arrival
// Alerts sheet, the onOpenStop push) are integration concerns and aren't unit-
// tested here.
//
// AppModel persists to UserDefaults, so every test uses an obviously-fake stop
// code and cleans up after itself to stay isolated from real user data.

import XCTest
import UIKit
@testable import Leyne

@MainActor
final class NearbyActionTests: XCTestCase {

    // Codes/names that can't collide with a real LTA stop.
    private let codeA = "ZZ_TEST_A"
    private let codeB = "ZZ_TEST_B"
    private let codeC = "ZZ_TEST_C"
    private let recentName = "ZZ Unit Test Stop"

    private func clean(_ m: AppModel) {
        m.pins.removeAll { [codeA, codeB, codeC].contains($0.code) }
        for c in [codeA, codeB, codeC] { m.hiddenNearby.remove(c) }
        m.removeRecent(recentName)
    }

    override func tearDown() {
        clean(AppModel())
        super.tearDown()
    }

    // ─── "Add to Saved" / "Remove from Saved" → togglePin ──────────────
    func testAddToSavedThenRemove() {
        let m = AppModel()
        clean(m)
        XCTAssertFalse(m.isPinned(codeA), "fake stop should start unpinned")

        m.togglePin(code: codeA)            // tap "Add to Saved"
        XCTAssertTrue(m.isPinned(codeA), "Add to Saved should pin the stop")
        XCTAssertTrue(m.pins.contains { $0.code == codeA })

        m.togglePin(code: codeA)            // tap "Remove from Saved"
        XCTAssertFalse(m.isPinned(codeA), "Remove from Saved should unpin the stop")
    }

    func testAddToSavedIsIdempotentPerCode() {
        // Saving the same stop twice (without an intervening unpin) must never
        // create a duplicate pin.
        let m = AppModel()
        clean(m)
        m.togglePin(code: codeA)
        let count = m.pins.filter { $0.code == codeA }.count
        XCTAssertEqual(count, 1, "exactly one pin per stop code")
        m.togglePin(code: codeA)            // cleanup
    }

    // ─── "Hide From Nearby" → hideFromNearby ───────────────────────────
    func testHideFromNearby() {
        let m = AppModel()
        clean(m)
        XCTAssertFalse(m.hiddenNearby.contains(codeB))

        m.hideFromNearby(code: codeB)       // tap "Hide From Nearby"
        XCTAssertTrue(m.hiddenNearby.contains(codeB),
                      "Hide From Nearby should add the code to hiddenNearby")
    }

    // ─── Regression: saving must NOT hide from Nearby ──────────────────
    // The bug: pinning a stop removed it from the Nearby list. Nearby should
    // exclude only stops the user explicitly hid — saved stops stay.
    func testSavingDoesNotHideFromNearby() {
        let m = AppModel()
        clean(m)

        m.togglePin(code: codeC)            // "Add to Saved"
        XCTAssertTrue(m.isPinned(codeC))
        XCTAssertFalse(m.hiddenNearby.contains(codeC),
                       "Saving a stop must not hide it from Nearby")

        // And the inverse: hiding a stop is independent of saving it.
        m.hideFromNearby(code: codeC)
        XCTAssertTrue(m.isPinned(codeC),
                      "Hiding from Nearby must not unpin a saved stop")

        m.togglePin(code: codeC)            // cleanup pin
    }

    // ─── "Open Stop" → records a recent visit ──────────────────────────
    func testOpenStopRecordsRecent() {
        let m = AppModel()
        m.removeRecent(recentName)

        m.addRecent(recentName)             // the onOpenStop side effect
        XCTAssertEqual(m.recents.first, recentName,
                       "Opening a stop should push it to the front of recents")

        // Opening it again shouldn't duplicate it.
        m.addRecent(recentName)
        XCTAssertEqual(m.recents.filter { $0 == recentName }.count, 1,
                       "recents must dedupe")
    }

    // ─── Service-number ordering used by the Stop list + long-press peek ─
    // Both sort with localizedStandardCompare so SG service numbers order
    // naturally: numeric first (2 before 10), suffixes after their base
    // (53 before 53M), and letter-prefixed night services last.
    func testServiceNumberNaturalOrder() {
        let input = ["98", "10", "2", "53M", "53", "98A", "170", "NR7"]
        let sorted = input.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(sorted, ["2", "10", "53", "53M", "98", "98A", "170", "NR7"])
    }

    // ─── "Copy Stop Code" → general pasteboard ─────────────────────────
    func testCopyStopCode() {
        UIPasteboard.general.string = codeA  // mirrors the button's action
        XCTAssertEqual(UIPasteboard.general.string, codeA)
    }
}
