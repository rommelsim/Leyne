// Domain models — mirror the shapes used across data.js / search.jsx.

import SwiftUI

enum Load: String {
    case sea, sda, lsd
    var label: String {
        switch self {
        case .sea: return "Seats"
        case .sda: return "Standing"
        case .lsd: return "Crowded"
        }
    }
    func color(_ t: Theme) -> Color {
        switch self {
        case .sea: return t.live
        case .sda: return t.warn
        case .lsd: return t.crit
        }
    }
}

enum Deck: String {
    case DD, SD, BD
    var word: String {
        switch self {
        case .DD: return "Double-deck"
        case .SD: return "Single-deck"
        case .BD: return "Bendy"
        }
    }
}

struct Service: Identifiable, Equatable {
    var no: String
    var dest: String
    var etaSec: Int
    var followingSec: Int
    var load: Load
    var wab: Bool
    var deck: Deck
    /// True when the arrival came from a live GPS feed (LTA `Monitored == 1`),
    /// false for a schedule-derived estimate. Drives the live/scheduled badge.
    var monitored: Bool = true
    /// LTA operator code: SBST / SMRT / TTS / GAS. Drives the per-row
    /// operator stripe — Singapore commuters distinguish operators by
    /// frequency patterns and fare-card behaviour, so this is a useful
    /// at-a-glance signal that no competing SG bus app surfaces today.
    var op: BusOperator = .unknown
    /// Absolute arrival instants from LTA — the UI tick recomputes etaSec/
    /// followingSec from these against `now` for a smooth live countdown.
    var arrivalDate: Date? = nil
    var followingDate: Date? = nil
    var thirdDate: Date? = nil
    /// Live GPS position of the next bus (from LTA `NextBus.Latitude/Longitude`),
    /// present only for monitored arrivals. Drives the Stop view's Distance
    /// sort — nearest bus first; nil (ghost / no telemetry) sorts last.
    var busLat: Double? = nil
    var busLon: Double? = nil
    /// Crowd level of the 2nd / 3rd buses (LTA `NextBus2/3.Load`). Strict —
    /// nil when LTA gives no occupancy code, so the Bus view's next-buses
    /// columns show "unknown" honestly instead of defaulting to "seats".
    var followingLoad: Load? = nil
    var thirdLoad: Load? = nil
    var id: String { no }
}

/// Singapore public bus operators as exposed by LTA DataMall's `Operator`
/// field. The colour each renders is intentionally subdued so a row of
/// stripes reads as a peripheral signal, not a parade.
enum BusOperator: String, Equatable {
    case sbst   // SBS Transit
    case smrt   // SMRT Buses
    case tts    // Tower Transit Singapore
    case gas    // Go-Ahead Singapore
    case unknown

    init(lta: String?) {
        switch lta?.uppercased() {
        case "SBST": self = .sbst
        case "SMRT": self = .smrt
        case "TTS":  self = .tts
        case "GAS":  self = .gas
        default:     self = .unknown
        }
    }

    /// Brand colour, but desaturated to coexist with the cream palette. The
    /// stripe is only 3pt wide, so these are perceptual hints rather than
    /// faithful brand reproductions.
    func stripe(_ t: Theme) -> Color {
        switch self {
        case .sbst:    return Color(hex: "B0322B")  // SBS deep red
        case .smrt:    return Color(hex: "8B8B8B")  // SMRT silver-grey
        case .tts:     return Color(hex: "E0A82E")  // Tower Transit yellow
        case .gas:     return Color(hex: "E0683A")  // Go-Ahead orange-red
        case .unknown: return t.line                // hairline (effectively invisible)
        }
    }
}

/// A pinned card (built-in pin or a stop added from Nearby).
struct CardModel: Identifiable, Equatable {
    var id: String
    var label: String
    var stopName: String
    var stopCode: String
    var walkMin: Int
    var services: [Service]
    /// When a card is opened by tapping a specific bus row.
    var initialSelectedNo: String? = nil
}

struct NearbyStop: Identifiable, Equatable {
    var id: String
    var stopName: String
    var stopCode: String
    var distanceM: Int
    var walkMin: Int
    var services: [Service]
}

struct DetectedKind: Equatable {
    var kind: String
    var label: String
}

// ─── ETA formatting (cards.jsx fmtETA) ────────────────────────────
struct ETA {
    var big: String
    var small: String
    var live: Bool
}

func fmtETA(_ sec: Int) -> ETA {
    if sec <= 0 { return ETA(big: "Arr", small: "now", live: true) }
    let m = sec / 60
    if m == 0 { return ETA(big: "Arr", small: "now", live: true) }
    return ETA(big: String(m), small: "min", live: m <= 1)
}

func fmtDistance(_ m: Int) -> String {
    m < 1000 ? "\(m)m" : String(format: "%.1fkm", Double(m) / 1000)
}

// ─── Data freshness ───────────────────────────────────────────────
/// Three-state confidence signal for live arrivals. Drives the dot in the
/// Home LIVE chip and (eventually) any per-stop staleness indicator. The
/// `LIVE · 10:15` chip is identity; *this* tells the user whether to trust
/// what they're reading right now.
enum Freshness: Equatable {
    case live           // last successful refresh < 30s ago
    case stale          // 30s – 5 min ago
    case offline        // > 5 min ago, or never fetched, or error state

    static func from(_ lastRefresh: Date?, now: Date = Date()) -> Freshness {
        guard let last = lastRefresh else { return .offline }
        let dt = now.timeIntervalSince(last)
        if dt < 30 { return .live }
        if dt < 300 { return .stale }
        return .offline
    }

    func color(_ t: Theme) -> Color {
        switch self {
        case .live:    return t.live
        case .stale:   return t.warn
        case .offline: return t.crit
        }
    }

    /// Short label suitable for a status chip. Kept terse so the chip
    /// doesn't grow when freshness changes.
    var label: String {
        switch self {
        case .live:    return "LIVE"
        case .stale:   return "STALE"
        case .offline: return "OFFLINE"
        }
    }
}
