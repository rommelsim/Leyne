// Mock data for the SG Transit redesign (iOS) — a faithful port of the design
// composition's constants. The redesign is a self-contained design surface, so
// it ships the same sample content the prototype used.

import SwiftUI

enum RDLoad { case seats, standing, packed }

struct RDArrival: Identifiable {
    let route: String
    let dest: String
    let load: RDLoad
    let min: String
    let then: String?
    // Identity is the service + destination (NOT the ETA) so a row persists as
    // its minutes tick down — letting the ETA `contentTransition` cross-fade
    // instead of the whole row being replaced.
    var id: String { route + dest }
}

struct RDStop: Identifiable {
    let name: String
    let code: String
    let dist: String
    let distShort: String
    let badge: String
    let arrivals: [RDArrival]
    var id: String { code }
}

struct RDStationDir: Identifiable {
    let to: String
    let via: String
    let plat: String
    let min: String
    let then: String
    var id: String { plat + to }
}

struct RDStation: Identifiable {
    let key: String
    let name: String
    let code: String
    let lineColor: Color
    let lineFg: Color
    let lineName: String
    let walk: String
    let freq: String
    let crowd: String
    let crowdLoad: RDLoad
    let firstTrain: String
    let lastTrain: String
    let exits: String
    let facilities: String
    let dirs: [RDStationDir]
    var id: String { key }
}

enum RDLineStatus { case normal, busy, major }

struct RDMrtLine: Identifiable {
    let code: String
    let name: String
    let badgeBg: Color
    let badgeFg: Color
    let statusText: String
    let location: String
    var major: Bool = false
    var detail: String? = nil
    var status: RDLineStatus = .normal
    var id: String { code }
}

private let orange = rdHex("FA9E0D")
private let onOrange = rdHex("3A2500")

let kRDStops: [RDStop] = [
    RDStop(
        name: "Opp Blk 123", code: "43091",
        dist: "You're at this stop · Farrer Road", distShort: "You are here", badge: "YOU'RE HERE",
        arrivals: [
            RDArrival(route: "165", dest: "HarbourFront Int", load: .seats, min: "2", then: "then 11"),
            RDArrival(route: "174", dest: "Clementi Int", load: .standing, min: "7", then: "then 16"),
            RDArrival(route: "186", dest: "Boon Lay Int", load: .packed, min: "12", then: nil),
            RDArrival(route: "5", dest: "Eunos Int", load: .seats, min: "4", then: "then 13"),
            RDArrival(route: "48", dest: "Marina Centre", load: .standing, min: "6", then: "then 18"),
            RDArrival(route: "93", dest: "Toa Payoh Int", load: .seats, min: "9", then: "then 21"),
            RDArrival(route: "961", dest: "Sin Ming Ave", load: .packed, min: "13", then: nil),
            RDArrival(route: "970", dest: "Jurong East Int", load: .standing, min: "16", then: nil),
        ]),
    RDStop(
        name: "Blk 240", code: "43099",
        dist: "1 min walk · 140 m", distShort: "140 m", badge: "1 MIN WALK",
        arrivals: [
            RDArrival(route: "51", dest: "Bishan Int", load: .seats, min: "5", then: "then 14"),
            RDArrival(route: "93", dest: "Toa Payoh", load: .standing, min: "8", then: nil),
            RDArrival(route: "410", dest: "Lor 1 Toa Payoh", load: .seats, min: "15", then: nil),
        ]),
    RDStop(
        name: "Farrer Rd Exit A", code: "43071",
        dist: "2 min walk · 160 m", distShort: "160 m", badge: "2 MIN WALK",
        arrivals: [
            RDArrival(route: "48", dest: "Marina Centre", load: .standing, min: "4", then: "then 12"),
            RDArrival(route: "93", dest: "Toa Payoh", load: .packed, min: "9", then: nil),
            RDArrival(route: "857", dest: "Yishun Int", load: .seats, min: "17", then: nil),
        ]),
]

let kRDStations: [String: RDStation] = [
    "holland": RDStation(
        key: "holland", name: "Holland Village", code: "CC21",
        lineColor: orange, lineFg: onOrange, lineName: "Circle Line",
        walk: "4 min walk · 320 m", freq: "every 4–6 min", crowd: "Moderate", crowdLoad: .standing,
        firstTrain: "5:31 AM", lastTrain: "12:18 AM", exits: "4 exits · A to D",
        facilities: "Lift, escalator & toilets",
        dirs: [
            RDStationDir(to: "HarbourFront", via: "via one-north · Buona Vista", plat: "A", min: "3", then: "then 9 min"),
            RDStationDir(to: "Dhoby Ghaut", via: "via Botanic Gardens · Bishan", plat: "B", min: "5", then: "then 12 min"),
        ]),
    "botanic": RDStation(
        key: "botanic", name: "Botanic Gardens", code: "CC19",
        lineColor: orange, lineFg: onOrange, lineName: "Circle Line · Downtown Line",
        walk: "7 min walk · 560 m", freq: "every 5–7 min", crowd: "Light", crowdLoad: .seats,
        firstTrain: "5:28 AM", lastTrain: "12:09 AM", exits: "3 exits · A to C",
        facilities: "Lift & escalator",
        dirs: [
            RDStationDir(to: "HarbourFront", via: "via Farrer Road · Holland V", plat: "A", min: "6", then: "then 13 min"),
            RDStationDir(to: "Marina Bay", via: "via Bishan · Promenade", plat: "B", min: "4", then: "then 11 min"),
        ]),
]

struct RDNearbyStation {
    let key: String
    let sub: String
    let topMin: String
}

let kRDNearbyStations: [RDNearbyStation] = [
    RDNearbyStation(key: "holland", sub: "4 min walk · Circle Line", topMin: "3"),
    RDNearbyStation(key: "botanic", sub: "7 min walk · CC · DT", topMin: "6"),
]

let kRDMrtLines: [RDMrtLine] = [
    RDMrtLine(code: "EWL", name: "East West Line", badgeBg: rdHex("009645"), badgeFg: .white,
              statusText: "MAJOR DELAY", location: "", major: true,
              detail: "Fault between Bugis and Tanah Merah. Add 15 min. Free bus bridging.", status: .major),
    RDMrtLine(code: "NSL", name: "North South Line", badgeBg: rdHex("D42E12"), badgeFg: .white,
              statusText: "Normal", location: "Bishan · 12 min", status: .normal),
    RDMrtLine(code: "CCL", name: "Circle Line", badgeBg: orange, badgeFg: onOrange,
              statusText: "Busy", location: "Farrer Road · 5 min", status: .busy),
    RDMrtLine(code: "NEL", name: "North East Line", badgeBg: rdHex("9900AA"), badgeFg: .white,
              statusText: "Normal", location: "Serangoon · 22 min", status: .normal),
]
