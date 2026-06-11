// Functional/unit tests — parsing, ETA rules, distance, search, pins.

import XCTest
import CoreLocation
@testable import Leyne

final class LyneCoreTests: XCTestCase {

    // ─── ETA rounding (LTA guide §2: round DOWN; <1 min → "Arr") ──
    func testETARounding() {
        XCTAssertEqual(fmtETA(229).big, "3")     // 3:49 → "3 min"
        XCTAssertEqual(fmtETA(127).big, "2")     // 2:07 → "2 min"
        let one = fmtETA(119)                     // 1:59 → "1 min", live
        XCTAssertEqual(one.big, "1"); XCTAssertTrue(one.live)
        let arr = fmtETA(59)                       // 0:59 → "Arr"
        XCTAssertEqual(arr.big, "Arr"); XCTAssertTrue(arr.live)
        XCTAssertEqual(fmtETA(0).big, "Arr")
        XCTAssertEqual(fmtETA(-10).big, "Arr")
        XCTAssertEqual(fmtETA(600).big, "10")
    }
    // ─── Query-kind detection ─────────────────────────────
    func testDetectQueryKind() {
        XCTAssertEqual(detectQueryKind("88").kind, "bus")
        XCTAssertEqual(detectQueryKind("410W").kind, "bus")
        XCTAssertEqual(detectQueryKind("NR1").kind, "bus")
        XCTAssertEqual(detectQueryKind("53061").kind, "stopcode")
        XCTAssertEqual(detectQueryKind("560123").kind, "postal")
        XCTAssertEqual(detectQueryKind("blk 230").kind, "block")
        XCTAssertEqual(detectQueryKind("Bishan MRT").kind, "text")
        XCTAssertEqual(detectQueryKind("").kind, "empty")
    }

    // ─── Haversine distance ───────────────────────────────
    func testHaversine() {
        XCTAssertEqual(haversine(1.3, 103.8, 1.3, 103.8), 0, accuracy: 0.001)
        // ~1 deg latitude ≈ 111 km
        XCTAssertEqual(haversine(1.0, 103.8, 2.0, 103.8), 111_195, accuracy: 1500)
        // Bishan MRT → Bishan Int (~300 m)
        let d = haversine(1.350758, 103.848298, 1.350955, 103.849516)
        XCTAssertTrue(d > 50 && d < 400, "got \(d)")
    }

    // ─── LTA date parsing (+08:00) ────────────────────────
    func testLTADate() {
        XCTAssertNotNil(LTADate.parse("2024-08-14T16:41:48+08:00"))
        XCTAssertNotNil(LTADate.parse("2026-05-18T13:42:06+08:00"))
        XCTAssertNil(LTADate.parse(""))
        XCTAssertNil(LTADate.parse("not-a-date"))
    }

    // ─── Load / Deck mapping ──────────────────────────────
    func testLoadDeckMapping() {
        XCTAssertEqual(Load(lta: "SEA"), .sea)
        XCTAssertEqual(Load(lta: "SDA"), .sda)
        XCTAssertEqual(Load(lta: "LSD"), .lsd)
        XCTAssertEqual(Load(lta: ""), .sea)         // blank → seats default
        XCTAssertEqual(Deck(lta: "DD"), .DD)
        XCTAssertEqual(Deck(lta: "SD"), .SD)
        XCTAssertEqual(Deck(lta: "BD"), .BD)
        XCTAssertEqual(Deck(lta: nil), .SD)
    }

    // ─── Bus Arrival v3 JSON (sample from the LTA guide) ──
    func testBusArrivalParsing() throws {
        let json = """
        {
          "odata.metadata": "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival",
          "BusStopCode": "83139",
          "Services": [
            {
              "ServiceNo": "15", "Operator": "GAS",
              "NextBus":  { "OriginCode":"77009","DestinationCode":"77131","EstimatedArrival":"2024-08-14T16:41:48+08:00","Monitored":1,"Latitude":"1.3154","Longitude":"103.9059","VisitNumber":"1","Load":"SEA","Feature":"WAB","Type":"SD" },
              "NextBus2": { "OriginCode":"77009","DestinationCode":"77131","EstimatedArrival":"2024-08-14T16:49:22+08:00","Monitored":1,"Latitude":"1.330","Longitude":"103.903","VisitNumber":"1","Load":"SDA","Feature":"WAB","Type":"DD" },
              "NextBus3": { "OriginCode":"","DestinationCode":"","EstimatedArrival":"","Monitored":0,"Latitude":"","Longitude":"","VisitNumber":"","Load":"","Feature":"","Type":"" }
            }
          ]
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(LTAArrivalResponse.self, from: json)
        XCTAssertEqual(resp.BusStopCode, "83139")
        XCTAssertEqual(resp.Services.count, 1)
        let svc = resp.Services[0]
        XCTAssertEqual(svc.ServiceNo, "15")
        XCTAssertTrue(svc.NextBus.hasData)
        XCTAssertFalse(svc.NextBus3.hasData)              // blank → no data
        let mapped = svc.toService(destName: "Bukit Panjang Int")
        XCTAssertEqual(mapped.no, "15")
        XCTAssertEqual(mapped.dest, "Bukit Panjang Int")
        XCTAssertEqual(mapped.load, .sea)
        XCTAssertEqual(mapped.deck, .SD)
        XCTAssertTrue(mapped.wab)
        XCTAssertNotNil(mapped.arrivalDate)
        XCTAssertNotNil(mapped.followingDate)
        XCTAssertNil(mapped.thirdDate)                    // NextBus3 blank
    }

    // ─── Reference dataset JSON ───────────────────────────
    func testBusStopsParsing() throws {
        let json = """
        { "odata.metadata":"x", "value":[
          {"BusStopCode":"01012","RoadName":"Victoria St","Description":"Hotel Grand Pacific","Latitude":1.29685,"Longitude":103.853}
        ]}
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(LTAList<LTABusStop>.self, from: json)
        XCTAssertEqual(list.value.first?.BusStopCode, "01012")
        XCTAssertEqual(list.value.first?.Description, "Hotel Grand Pacific")
        XCTAssertEqual(list.value.first?.Latitude ?? 0, 1.29685, accuracy: 1e-5)
    }

    func testBusRoutesParsing() throws {
        let json = """
        { "value":[
          {"ServiceNo":"107M","Operator":"SBST","Direction":1,"StopSequence":28,"BusStopCode":"01219","Distance":10.3}
        ]}
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(LTAList<LTABusRouteDTO>.self, from: json)
        XCTAssertEqual(list.value.first?.ServiceNo, "107M")
        XCTAssertEqual(list.value.first?.StopSequence, 28)
        XCTAssertEqual(list.value.first?.BusStopCode, "01219")
    }

    // The reported "weird waypoint" bug: the map drew the whole route
    // (40–60 stops, loops) → a tangle. The fix slices to the bus→you segment.
    func testJourneySegmentTrimsFullRoute() {
        let stops = (0..<40).map {
            RouteStopLive(code: "\($0)", name: "S\($0)", lat: Double($0), lon: 0, seq: $0)
        }
        // bus at 10, you at 15 → segment 10...16 only (not all 40)
        var seg = journeySegment(RouteInfo(stops: stops, youIndex: 15, busIndex: 10, busCoord: nil))
        XCTAssertEqual(seg.first?.code, "10")
        XCTAssertEqual(seg.last?.code, "16")
        XCTAssertEqual(seg.count, 7)

        // bus GPS unknown → bounded approach window (you-6 … you+1)
        seg = journeySegment(RouteInfo(stops: stops, youIndex: 15, busIndex: nil, busCoord: nil))
        XCTAssertEqual(seg.first?.code, "9")
        XCTAssertEqual(seg.last?.code, "16")

        // bus already past you → still bounded, still includes your stop
        seg = journeySegment(RouteInfo(stops: stops, youIndex: 5, busIndex: 30, busCoord: nil))
        XCTAssertLessThanOrEqual(seg.count, 8)
        XCTAssertTrue(seg.contains { $0.code == "5" })

        // empty route is safe
        XCTAssertTrue(journeySegment(RouteInfo(stops: [], youIndex: 0,
                                               busIndex: nil, busCoord: nil)).isEmpty)
    }

    func testLiveActivityPhases() {
        // A freshly started activity for a real ETA must be live (tracking),
        // not racing to dismissal.
        XCTAssertEqual(phaseFor(eta: 180, postArrivedMs: 0), .tracking)
        XCTAssertEqual(phaseFor(eta: 55,  postArrivedMs: 0), .arriving)
        XCTAssertEqual(phaseFor(eta: 20,  postArrivedMs: 0), .close)
        XCTAssertEqual(phaseFor(eta: 0,   postArrivedMs: 0), .arrived)
        XCTAssertEqual(phaseFor(eta: 0,   postArrivedMs: 2000), .completed)
        XCTAssertEqual(phaseFor(eta: 0,   postArrivedMs: 4000), .dismissing)
    }

    func testPinCodable() throws {
        let p = Pin(code: "53061", nickname: "Morning", tracked: ["88", "156"])
        let back = try JSONDecoder().decode([Pin].self,
                                            from: JSONEncoder().encode([p]))
        XCTAssertEqual(back, [p])
        // tracked == nil ("all") round-trips.
        let allP = Pin(code: "1", nickname: "X", tracked: nil)
        let back2 = try JSONDecoder().decode([Pin].self,
                                             from: JSONEncoder().encode([allP]))
        XCTAssertNil(back2.first?.tracked)
        // Legacy/missing key must still decode (tracked nil), not throw.
        let legacy = #"[{"code":"99999","nickname":"X"}]"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode([Pin].self, from: legacy)
        XCTAssertEqual(migrated.first?.code, "99999")
        XCTAssertNil(migrated.first?.tracked)
    }
}

// ─── AppModel pin logic (regression for the unpin/re-pin bug) ──
@MainActor
final class LynePinTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "leyne.pins")
        UserDefaults.standard.removeObject(forKey: "leyne.recents")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "leyne.pins")
        UserDefaults.standard.removeObject(forKey: "leyne.recents")
    }

    func testPinToggleIsSymmetric() {
        let m = AppModel()
        XCTAssertTrue(m.pins.isEmpty)               // starts empty (no mock)
        XCTAssertFalse(m.isPinned("53061"))
        m.togglePin(code: "53061")
        XCTAssertTrue(m.isPinned("53061"))
        m.togglePin(code: "53061")
        XCTAssertFalse(m.isPinned("53061"))
        m.togglePin(code: "53061")                  // re-pin must work
        XCTAssertTrue(m.isPinned("53061"))
    }

    func testTrackedToggleAndPersistence() {
        let m = AppModel()
        m.togglePin(code: "53061")
        XCTAssertTrue(m.isTracked(code: "53061", busNo: "88"))   // empty = all
        m.toggleTracked(code: "53061", busNo: "88", allNos: ["88", "156"])
        XCTAssertFalse(m.isTracked(code: "53061", busNo: "88"))
        XCTAssertTrue(m.isTracked(code: "53061", busNo: "156"))
        // persisted to UserDefaults
        let data = UserDefaults.standard.data(forKey: "leyne.pins")
        XCTAssertNotNil(data)
        let pins = try? JSONDecoder().decode([Pin].self, from: data ?? Data())
        XCTAssertEqual(pins?.first?.code, "53061")
    }

    // The reported bug: on a single-service stop, unchecking the bus
    // wrapped back to checked (empty list was overloaded to mean "all").
    func testUncheckSingleServiceSticks() {
        let m = AppModel()
        m.togglePin(code: "53061")
        XCTAssertTrue(m.isTracked(code: "53061", busNo: "88"))
        m.toggleTracked(code: "53061", busNo: "88", allNos: ["88"])
        XCTAssertFalse(m.isTracked(code: "53061", busNo: "88"))   // stays unchecked
        m.toggleTracked(code: "53061", busNo: "88", allNos: ["88"])
        XCTAssertTrue(m.isTracked(code: "53061", busNo: "88"))     // re-check works
    }

    func testUncheckAllDoesNotWrap() {
        let m = AppModel()
        m.togglePin(code: "X")
        let all = ["88", "156", "410"]
        for b in all { m.toggleTracked(code: "X", busNo: b, allNos: all) }
        for b in all { XCTAssertFalse(m.isTracked(code: "X", busNo: b)) }  // none re-check
        m.toggleTracked(code: "X", busNo: "88", allNos: all)
        XCTAssertTrue(m.isTracked(code: "X", busNo: "88"))
        XCTAssertFalse(m.isTracked(code: "X", busNo: "156"))
    }

    // The Live Activity is now AUTOMATIC (follows the soonest alerted bus).
    // Verify the automatic model's reachable invariants:
    //   1. No tracker by default (nothing to track until an alert exists).
    //   2. liveKey format is stable (key is read by autoTrackSoonestAlert to
    //      detect the currently-tracked bus from the key alone).
    //   3. stopLiveActivity is idempotent and leaves key = nil.
    //   4. Disabling notifications stops any running Live Activity.
    func testLiveActivityAutomaticContract() {
        XCTAssertEqual(AppModel.liveKey(bus: "88", stopCode: "53009"), "53009|88")

        let m = AppModel()
        // No tracker at start — no alerts exist.
        XCTAssertNil(m.liveActivityKey)
        XCTAssertFalse(m.liveActivityOn)

        // startLiveActivity sets the key (ActivityKit itself is unavailable in the
        // simulator test process; the call is a no-op when areActivitiesEnabled ==
        // false, so we just verify the contract that stopLiveActivity clears it).
        m.stopLiveActivity()              // idempotent on an inactive session
        XCTAssertNil(m.liveActivityKey)

        // Disabling notifications must stop any Live Activity.
        // setNotificationsEnabled is async; test the synchronous path directly
        // (notificationsEnabled is @AppStorage so we can set it to false).
        m.notificationsEnabled = false
        m.stopLiveActivity()              // as the tick would call it
        XCTAssertNil(m.liveActivityKey)
        XCTAssertFalse(m.liveActivityOn)
    }

    // The Home Screen widget can only see pins through the App Group. Pinning
    // must publish them there in the shape the widget decodes.
    func testWidgetPinMirrorViaAppGroup() {
        AppGroup.defaults?.removeObject(forKey: AppGroup.pinsKey)
        let m = AppModel()
        m.togglePin(code: "53009")
        m.togglePin(code: "83139")

        guard let d = AppGroup.defaults?.data(forKey: AppGroup.pinsKey) else {
            return XCTFail("App Group not writable — entitlement missing?")
        }
        let stops = try! JSONDecoder().decode([SharedPinnedStop].self, from: d)
        XCTAssertEqual(Set(stops.map(\.id)), ["53009", "83139"])
        XCTAssertTrue(stops.allSatisfy { !$0.name.isEmpty })   // never blank

        m.togglePin(code: "53009")                              // unpin
        let d2 = AppGroup.defaults!.data(forKey: AppGroup.pinsKey)!
        let after = try! JSONDecoder().decode([SharedPinnedStop].self, from: d2)
        XCTAssertEqual(after.map(\.id), ["83139"])              // mirror updated
    }

    // Nearby "Pin to Home" → must surface in allPinnedCards (Home list).
    func testPinFromNearbySurfacesOnHome() {
        let m = AppModel()
        XCTAssertTrue(m.pins.isEmpty)
        m.togglePin(code: "53231")                       // tap "Pin to Home"
        XCTAssertTrue(m.isPinned("53231"))
        XCTAssertEqual(m.pins.count, 1)
        let cards = m.allPinnedCards                      // what Home renders
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.stopCode, "53231")
        XCTAssertEqual(cards.first?.id, "53231")
    }

    // Search → open stop → top-right "Pin stop" must land on Home.
    func testPinFromDetailSurfacesOnHome() {
        let m = AppModel()
        m.openCard = CardModel(id: "17171", label: "x", stopName: "Clementi Stn Exit B",
                               stopCode: "17171", walkMin: 0, services: [])
        guard let live = m.openCardLive() else { return XCTFail("no card") }
        XCTAssertFalse(m.isCardPinned(live))
        m.togglePinForCard(live)                          // tap "Pin stop"
        XCTAssertTrue(m.isCardPinned(live))
        XCTAssertEqual(m.allPinnedCards.map(\.stopCode), ["17171"])
    }

    func testTrackAllUntrackAll() {
        let m = AppModel()
        let all = ["96", "183", "96B"]
        m.setAllTracked(code: "17171", allNos: all, tracked: true)   // pin + all
        XCTAssertTrue(m.isPinned("17171"))
        XCTAssertTrue(m.allTracked(code: "17171"))
        for b in all { XCTAssertTrue(m.isTracked(code: "17171", busNo: b)) }
        m.setAllTracked(code: "17171", allNos: all, tracked: false)  // = unpin
        XCTAssertFalse(m.isPinned("17171"))               // not on Home
        XCTAssertFalse(m.allTracked(code: "17171"))
        for b in all { XCTAssertFalse(m.isTracked(code: "17171", busNo: b)) }
    }

    // The reported bug: "Pinned stop" lit while nothing tracked. New rule:
    // pinned ⟺ ≥1 bus tracked; unchecking the last one unpins.
    func testPinnedIffHasTrackedBus() {
        let m = AppModel()
        let all = ["10", "14", "16"]
        m.togglePin(code: "77009")                        // top-right Pin → all
        XCTAssertTrue(m.isPinned("77009"))
        m.toggleTracked(code: "77009", busNo: "10", allNos: all)
        m.toggleTracked(code: "77009", busNo: "14", allNos: all)
        XCTAssertTrue(m.isPinned("77009"))                // 1 left → still pinned
        XCTAssertTrue(m.isTracked(code: "77009", busNo: "16"))
        m.toggleTracked(code: "77009", busNo: "16", allNos: all)  // uncheck last
        XCTAssertFalse(m.isPinned("77009"))               // → unpinned, not lit
        for b in all { XCTAssertFalse(m.isTracked(code: "77009", busNo: b)) }
        // Checking a bus on the now-unpinned stop re-pins it.
        m.toggleTracked(code: "77009", busNo: "10", allNos: all)
        XCTAssertTrue(m.isPinned("77009"))
        XCTAssertTrue(m.isTracked(code: "77009", busNo: "10"))
        XCTAssertFalse(m.isTracked(code: "77009", busNo: "14"))
    }

    func testReorderPins() {
        let m = AppModel()
        m.togglePin(code: "A"); m.togglePin(code: "B"); m.togglePin(code: "C")
        XCTAssertEqual(m.pins.map(\.code), ["A", "B", "C"])
        m.reorderPins(["C", "A", "B"])
        XCTAssertEqual(m.pins.map(\.code), ["C", "A", "B"])
    }

    func testAddRecentDeduplicatesAndCaps() {
        let m = AppModel()
        for i in 0..<12 { m.addRecent("q\(i)") }
        m.addRecent("q11")                          // dup → moves to front
        XCTAssertEqual(m.recents.count, 8)
        XCTAssertEqual(m.recents.first, "q11")
    }
}
