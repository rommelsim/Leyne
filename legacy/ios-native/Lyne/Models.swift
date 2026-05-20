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
    /// Absolute arrival instants from LTA — the UI tick recomputes etaSec/
    /// followingSec from these against `now` for a smooth live countdown.
    var arrivalDate: Date? = nil
    var followingDate: Date? = nil
    var thirdDate: Date? = nil
    var id: String { no }
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
