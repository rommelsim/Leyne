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

// MARK: - Nearest stops to an arbitrary point (postal-code search)

@MainActor
extension DataStore {
    /// Nearest bus stops to any coordinate — the Home nearby ranking, but for
    /// a searched point (postal code), without touching the `nearby` state.
    func wsStopsNear(_ coord: CLLocationCoordinate2D, limit: Int = 8) -> [(stop: LTABusStop, distanceM: Int)] {
        stopByCode.values
            .map { ($0, Int(haversine(coord.latitude, coord.longitude,
                                      $0.Latitude, $0.Longitude).rounded())) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }
}

// MARK: - "Did you mean …?" (typo correction over the transit vocabulary)

@MainActor
enum WSSpell {
    /// Distinct words (≥ 4 letters) from stop names, road names and MRT
    /// station names — the only vocabulary users realistically type. Built
    /// once after the stop directory loads.
    private static var vocab: [String] = []

    private static func vocabulary(from store: DataStore) -> [String] {
        if !vocab.isEmpty { return vocab }
        var set = Set<String>()
        func add(_ text: String) {
            for w in text.lowercased().split(whereSeparator: { !$0.isLetter }) where w.count >= 4 {
                set.insert(String(w))
            }
        }
        for s in store.stopByCode.values { add(s.Description); add(s.RoadName) }
        for st in MrtGeo.all { add(st.name) }
        vocab = Array(set)
        return vocab
    }

    /// A corrected version of `query` (token-by-token, edit distance ≤ 2), or
    /// nil when no better spelling exists. "clemeti rd" → "Clementi rd".
    static func suggest(for query: String, store: DataStore) -> String? {
        let words = vocabulary(from: store)
        guard !words.isEmpty else { return nil }
        var changed = false
        let corrected = query.split(separator: " ").map { tok -> String in
            let t = tok.lowercased()
            guard t.count >= 4, t.allSatisfy(\.isLetter), !words.contains(t) else { return String(tok) }
            let maxDist = t.count >= 6 ? 2 : 1
            var best: (word: String, dist: Int)? = nil
            for w in words where abs(w.count - t.count) <= maxDist {
                let d = editDistance(t, w, cap: maxDist)
                if d <= maxDist, d < (best?.dist ?? .max) { best = (w, d) }
            }
            guard let best else { return String(tok) }
            changed = true
            return best.word.capitalized
        }.joined(separator: " ")
        return changed ? corrected : nil
    }

    /// Levenshtein distance with an early-out once a whole row exceeds `cap`.
    private static func editDistance(_ a: String, _ b: String, cap: Int) -> Int {
        let aa = Array(a.unicodeScalars), bb = Array(b.unicodeScalars)
        var prev = Array(0...bb.count)
        for i in 1...aa.count {
            var cur = [Int](repeating: 0, count: bb.count + 1)
            cur[0] = i
            var rowMin = i
            for j in 1...bb.count {
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > cap { return cap + 1 }
            prev = cur
        }
        return prev[bb.count]
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
