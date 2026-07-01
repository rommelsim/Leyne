// WhereSia — data helpers.
//
// Small bridges over the existing DataStore/AppModel so the screens read
// cleanly. No new networking — everything routes through the live data layer.

import SwiftUI
import CoreLocation

// MARK: - Station code → line

/// The MRTLine a station/segment code belongs to (for crowd/forecast fetches).
/// Returns nil for LRT and codes we don't fetch crowd for.
func wsLine(forStationCode code: String) -> MRTLine? {
    switch code.prefix(2).uppercased() {
    case "NS":        return .NS
    case "EW", "CG":  return .EW
    case "NE":        return .NE
    case "CC", "CE":  return .CC
    case "DT":        return .DT
    case "TE":        return .TE
    default:          return nil
    }
}

// MARK: - Live ETA

/// Live seconds-to-arrival for a service, recomputed from the LTA timestamp
/// against now (so the countdown ticks smoothly), falling back to the fetched
/// etaSec when no absolute date is present.
func wsLiveETASec(_ s: Service, now: Date = Date()) -> Int {
    if let d = s.arrivalDate { return max(0, Int(d.timeIntervalSince(now))) }
    return max(0, s.etaSec)
}

/// The soonest service at a stop (by live ETA), or nil.
func wsSoonest(_ services: [Service], now: Date = Date()) -> Service? {
    services.min { wsLiveETASec($0, now: now) < wsLiveETASec($1, now: now) }
}

// MARK: - Station crowd lookup

@MainActor
extension DataStore {
    /// Ensure live crowd is fetched for every line a set of stations touches
    /// (best-effort; the store dedupes + gates the network itself).
    func wsWarmCrowd(for stations: [MrtGeoStation]) {
        var lines = Set<MRTLine>()
        for st in stations { for c in st.codes { if let l = wsLine(forStationCode: c) { lines.insert(l) } } }
        for l in lines { refreshCrowd(line: l) }
    }

    /// The best available live crowd reading for a station (first line that has
    /// a reading for one of the station's codes).
    func wsCrowd(for station: MrtGeoStation) -> CrowdLevel? {
        for code in station.codes {
            guard let line = wsLine(forStationCode: code),
                  let rows = crowdByLine[line] else { continue }
            if let hit = rows.first(where: { $0.code == code }) { return hit.level }
        }
        return nil
    }
}

// MARK: - Interchange resolution (is this bus stop at a rail station?)

/// If a bus stop's description sits at a rail station, its resolved name +
/// line codes (coloured via the WhereSia palette). nil when it isn't a station.
func wsInterchange(forStopName name: String) -> (name: String, codes: [String])? {
    guard let station = resolveMrtStation(name) else { return nil }
    return (station.name, station.codes.map { $0.code })
}

// MARK: - Operator display

extension BusOperator {
    var wsName: String {
        switch self {
        case .sbst:    return "SBS Transit"
        case .smrt:    return "SMRT"
        case .tts:     return "Tower Transit"
        case .gas:     return "Go-Ahead"
        case .unknown: return "Bus"
        }
    }
}

// MARK: - Deck → glyph

extension Deck {
    var wsGlyph: WSGlyph {
        switch self {
        case .DD: return .busDouble
        case .BD: return .busBendy
        case .SD: return .busSingle
        }
    }
}
