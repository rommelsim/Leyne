// WhereSia — formatting + crowd vocabulary.
//
// Bridges the existing domain models (Load, CrowdLevel) to WhereSia's fixed
// vocabulary and the 3-step occupancy gauge. Crowd is ALWAYS spoken as a word
// alongside the gauge (VoiceOver never relies on the gauge alone).

import SwiftUI

// MARK: - Bus load (per-bus occupancy)

extension Load {
    /// Gauge fill fraction = how much ROOM IS LEFT, not how full the bus is
    /// (owner 2026-07-26). A full gauge means "plenty of space"; a nearly
    /// empty one means "almost none". Inverted from the original occupancy
    /// reading, where the most packed bus drew the longest bar and so looked
    /// like the best option at a glance.
    ///
    /// Renamed off `wsFraction` deliberately: the number's MEANING flipped, so
    /// the old name would silently keep reading as "how full" at call sites.
    /// The MRT `CrowdLevel.wsFraction` is a different quantity — platform
    /// density, which has no notion of seats — and is unchanged.
    ///
    /// ALWAYS render this alongside the word, and NEVER substitute 0 for an
    /// unknown load: under this reading an empty gauge asserts "no space".
    var wsSpaceFraction: CGFloat {
        switch self {
        case .sea: return 1.0
        case .sda: return 0.67
        case .lsd: return 0.34
        }
    }
    /// How full the bus is, said in full. A bare "Seats" / "Standing" left
    /// people asking what the word was even about (owner 2026-07-26) — the
    /// label has to carry its own meaning, since nothing next to it explains
    /// that this line is about the crowd on board.
    var wsWord: String {
        switch self {
        case .sea: return "Seats available"
        case .sda: return "Standing only"
        case .lsd: return "Almost full"
        }
    }
    /// Lower-case sentence phrase for the Stop hero's crowd row (design:
    /// "●●○ seats available").
    var wsPhrase: String {
        switch self {
        case .sea: return "seats available"
        case .sda: return "standing room"
        case .lsd: return "limited space"
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

// MARK: - Facility copy (lift maintenance feed)

/// The LTA facilities feed shouts inconsistently ("CONCOURSE - PLATFORM A",
/// "Exit B Street level - Concourse"). Reshape only ALL-CAPS words to title
/// case (single letters like the "A" in "Platform A" stay upper) and swap
/// spaced hyphens for an en dash. Mixed-case input passes through untouched.
func wsFacilityText(_ raw: String) -> String {
    raw.replacingOccurrences(of: " - ", with: " – ")
        .split(separator: " ")
        .map { word -> String in
            let s = String(word)
            let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            guard letters.count > 1,
                  !letters.contains(where: { CharacterSet.lowercaseLetters.contains($0) })
            else { return s }
            return s.prefix(1) + s.dropFirst().lowercased()
        }
        .joined(separator: " ")
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

    /// "Updated 9:41" meta used in section headers + status lines. Owner
    /// feedback 2026-07-02: "UPD" read as jargon — spell it out.
    static func upd(_ date: Date?, use24h: Bool) -> String {
        guard let date else { return "Updated —" }
        return "Updated " + clock(date, use24h: use24h)
    }

    /// LTA "HHmm" (e.g. "0530", past-midnight "2512") → "05:30" / "5:30 AM".
    /// Honours the 12/24-hour preference like every other clock in the app —
    /// a first/last card stuck on 24h while the boards read "5:30 AM" reads
    /// as two different apps.
    static func firstLast(_ raw: String?, use24h: Bool) -> String {
        guard let raw, raw.count == 4, let n = Int(raw) else { return "—" }
        let h = (n / 100) % 24
        let m = n % 100
        if use24h { return String(format: "%02d:%02d", h, m) }
        let suffix = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, suffix)
    }
}
