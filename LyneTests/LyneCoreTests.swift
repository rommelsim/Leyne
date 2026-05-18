// Functional/unit tests — parsing, ETA rules, distance, search, pins.

import XCTest
import CoreLocation
@testable import Lyne

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
        let p = Pin(code: "53061", nickname: "Morning", hidden: ["88", "156"])
        let data = try JSONEncoder().encode([p])
        let back = try JSONDecoder().decode([Pin].self, from: data)
        XCTAssertEqual(back, [p])
        // Missing "hidden" key (e.g. legacy data) must still decode, not throw.
        let legacy = #"[{"code":"99999","nickname":"X"}]"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode([Pin].self, from: legacy)
        XCTAssertEqual(migrated.first?.code, "99999")
        XCTAssertEqual(migrated.first?.hidden, [])
    }
}

// ─── AppModel pin logic (regression for the unpin/re-pin bug) ──
@MainActor
final class LynePinTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "lyne.pins")
        UserDefaults.standard.removeObject(forKey: "lyne.recents")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "lyne.pins")
        UserDefaults.standard.removeObject(forKey: "lyne.recents")
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
        let data = UserDefaults.standard.data(forKey: "lyne.pins")
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

    // "Start Live Activity does not generate" — prove the action produces the
    // state RootView renders the takeover from, and closes Detail so it shows.
    func testStartLiveActivityGeneratesState() {
        let m = AppModel()
        XCTAssertNil(m.liveActivity)
        m.openCard = CardModel(id: "53009", label: "x", stopName: "Bishan Int",
                               stopCode: "53009", walkMin: 0, services: [])
        let s = Service(no: "88", dest: "Bukit Panjang Int", etaSec: 180,
                        followingSec: 600, load: .sea, wab: true, deck: .DD)
        m.startLiveActivity(s, stopName: "Bishan Int", stopCode: "53009")
        XCTAssertNotNil(m.liveActivity)
        XCTAssertEqual(m.liveActivity?.busNo, "88")
        XCTAssertEqual(m.liveActivity?.dest, "Bukit Panjang Int")
        XCTAssertEqual(m.liveActivity?.etaAtStart, 180)   // real ETA, not raced
        XCTAssertNil(m.openCard)                          // detail closed
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
