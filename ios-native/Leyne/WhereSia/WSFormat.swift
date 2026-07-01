// WhereSia — formatting + crowd vocabulary.
//
// Bridges the existing domain models (Load, CrowdLevel) to WhereSia's fixed
// vocabulary and the 3-step occupancy gauge. Crowd is ALWAYS spoken as a word
// alongside the gauge (VoiceOver never relies on the gauge alone).

import SwiftUI

// MARK: - Bus load (per-bus occupancy)

extension Load {
    /// Gauge fill fraction — the ceiling of LTA's 3-level Load. 34 / 67 / 100 %.
    var wsFraction: CGFloat {
        switch self {
        case .sea: return 0.34
        case .sda: return 0.67
        case .lsd: return 1.0
        }
    }
    /// Full word for legends / VoiceOver: Seats · Standing · Limited.
    var wsWord: String {
        switch self {
        case .sea: return "Seats"
        case .sda: return "Standing"
        case .lsd: return "Limited"
        }
    }
    /// Compact word for the arrival pills (fits three across).
    var wsShort: String {
        switch self {
        case .sea: return "Seats"
        case .sda: return "Stand"
        case .lsd: return "Full"
        }
    }
}

// MARK: - Station crowd level

extension CrowdLevel {
    /// Gauge fill fraction — 34 / 67 / 100 %. Unknown reads as empty.
    var wsFraction: CGFloat {
        switch self {
        case .low:      return 0.34
        case .moderate: return 0.67
        case .high:     return 1.0
        case .unknown:  return 0
        }
    }
    /// Station word: Low · Moderate · High.
    var wsWord: String {
        switch self {
        case .low:      return "Low"
        case .moderate: return "Moderate"
        case .high:     return "High"
        case .unknown:  return "—"
        }
    }
    /// Plain-language sub-line for the "crowd now" hero card.
    var wsHint: String {
        switch self {
        case .low:      return "PLENTY OF ROOM"
        case .moderate: return "SOME QUEUES AT GANTRIES"
        case .high:     return "BUSY — EXPECT A WAIT"
        case .unknown:  return "NO LIVE READING"
        }
    }
}

// MARK: - Time of day

enum WSFmt {
    /// Clock label for the "UPD 9:41" / status lines. Honours the 24-h pref.
    static func clock(_ date: Date, use24h: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_SG")
        f.dateFormat = use24h ? "HH:mm" : "h:mm"
        return f.string(from: date)
    }

    /// "UPD 9:41" eyebrow used in section headers + meta lines.
    static func upd(_ date: Date?, use24h: Bool) -> String {
        guard let date else { return "UPD —" }
        return "UPD " + clock(date, use24h: use24h)
    }

    /// LTA "HHmm" (e.g. "0530", past-midnight "2512") → "05:30" / "01:12".
    static func firstLast(_ raw: String?) -> String {
        guard let raw, raw.count == 4, let n = Int(raw) else { return "—" }
        let h = (n / 100) % 24
        let m = n % 100
        return String(format: "%02d:%02d", h, m)
    }
}
