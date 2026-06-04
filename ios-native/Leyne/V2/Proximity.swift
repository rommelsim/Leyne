// Proximity & occupancy — the 2.4.0 overhaul's semantic-colour layer.
//
// Two orthogonal signals get colour here, and ONLY these two:
//   • ETA proximity — how soon a bus arrives (green → amber → neutral)
//   • Occupancy     — how full it is (seats green · standing amber · limited grey)
//
// Confidence (live / stale / scheduled) is deliberately NOT colour — it stays
// shape + opacity + the whisper "~" (see Confidence.swift), so the honesty
// thesis and colour-blind legibility survive. A scheduled/ghost arrival is
// therefore shown neutral regardless of how soon it is: we don't paint an
// unverified time green.

import SwiftUI

// MARK: - ETA proximity

/// How soon an arrival is, bucketed for colour + "Arriving soon" copy.
/// Thresholds mirror the mockups: ≤~2.5 min reads as imminent, green holds
/// to ~9 min, amber to ~16 min, then neutral.
enum ETATier {
    case imminent   // arriving / very soon → green + "Arriving soon"
    case soon       // green
    case medium     // amber
    case far        // neutral (grey)

    static func of(etaSec: Int) -> ETATier {
        switch etaSec {
        case ..<150:  return .imminent
        case ..<540:  return .soon
        case ..<960:  return .medium
        default:      return .far
        }
    }

    var isImminent: Bool { self == .imminent }
}

/// Resolves the colour for an arrival's ETA, gating on confidence: a bus we
/// can't verify live (scheduled / ghost) is always neutral — we never paint
/// an unconfirmed time green or amber. Stale (was-live, now aging) keeps its
/// proximity hue; the "~" whisper already signals the aging.
func etaColor(tier: ETATier, confidence: ArrivalConfidence, t: Theme) -> Color {
    switch confidence {
    case .unconfirmed, .none:
        return t.dim
    case .live, .stale:
        switch tier {
        case .imminent, .soon: return t.soon
        case .medium:          return t.mid
        case .far:             return t.dim
        }
    }
}

/// Convenience: colour straight from seconds + confidence.
func etaColor(etaSec: Int, confidence: ArrivalConfidence, t: Theme) -> Color {
    etaColor(tier: .of(etaSec: etaSec), confidence: confidence, t: t)
}

/// Fill + number colour for a proximity-coloured service badge: soon → green,
/// medium → amber (both with contrasting text that works in either mode),
/// far / scheduled / ghost → neutral surface with ink text (we never paint an
/// unverified service badge a confident green/amber).
func serviceBadgeColors(etaSec: Int, confidence: ArrivalConfidence, t: Theme) -> (fill: Color, fg: Color) {
    switch confidence {
    case .unconfirmed, .none:
        return (t.surfaceHi, t.fg)
    case .live, .stale:
        switch ETATier.of(etaSec: etaSec) {
        case .imminent, .soon: return (t.soon, t.contrastFg)
        case .medium:          return (t.mid, t.contrastFg)
        case .far:             return (t.surfaceHi, t.fg)
        }
    }
}

// MARK: - Clock

/// Wall-clock time string honouring the in-app 24-hour preference
/// (`AppModel.use24h`). Mirrors HomeView.formattedTime so route times read the
/// same as the rest of the app. Used for per-stop ETAs on the Bus view.
func fmtClock(_ date: Date, use24h: Bool) -> String {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: date)
    let minute = cal.component(.minute, from: date)
    let mm = String(format: "%02d", minute)
    if use24h {
        return "\(String(format: "%02d", hour)):\(mm)"
    }
    let h12 = ((hour + 11) % 12) + 1
    return "\(h12):\(mm) \(hour < 12 ? "AM" : "PM")"
}

// MARK: - Occupancy

/// Shared crowding colour: seats → green, standing → amber, limited/unknown
/// → neutral grey. Used by both `OccupancyLabel` (icon + words) and
/// `CrowdMeter` (bars) so the two read the same.
func occupancyColor(_ load: Load?, t: Theme) -> Color {
    switch load {
    case .sea:        return t.soon
    case .sda:        return t.mid
    case .lsd, .none: return t.dim
    }
}

// MARK: - Occupancy label

/// Crowding shown the friendly way — an icon + plain words, coloured by how
/// much room is left: seats (green) · standing (amber) · limited (grey).
/// Sits under the destination on Stop/Bus rows. (The compact `CrowdMeter`
/// bars stay for the Bus view's tighter header.)
struct OccupancyLabel: View {
    let load: Load
    let t: Theme
    var size: CGFloat = 12

    private var icon: String {
        switch load {
        case .sea: return "chair.lounge"
        case .sda, .lsd: return "person.2.fill"
        }
    }

    private var text: String {
        switch load {
        case .sea: return "Seats available"
        case .sda: return "Standing available"
        case .lsd: return "Limited standing"
        }
    }

    private var tint: Color { occupancyColor(load, t: t) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
            Text(text)
                .font(t.sans(size, weight: .medium))
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
