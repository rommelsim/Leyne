// Proximity & occupancy.
//
// ETA / soon-ness is deliberately NOT colour-coded: arrival times read as
// uniform ink, and only confidence dims them (scheduled / ghost arrivals show
// faint — the honesty whisper, see Confidence.swift). The one remaining colour
// signal here is occupancy — how full a bus is (seats green · standing amber ·
// limited grey).
//
// `ETATier` survives only to drive the "Arriving soon" text cue for an
// imminent *live* arrival; it no longer maps to a colour.

import SwiftUI

// MARK: - ETA proximity

/// How soon an arrival is, bucketed for the "Arriving soon" copy on the lead
/// chip. Thresholds mirror the mockups: ≤~2.5 min reads as imminent.
enum ETATier {
    case imminent   // arriving / very soon → "Arriving soon"
    case soon
    case medium
    case far

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
