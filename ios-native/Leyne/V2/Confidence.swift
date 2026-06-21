// Confidence — Leyne 3.0's headline idea, ported into the Soft (green)
// system. Leyne doesn't compete on accuracy (every SG app reads the same
// LTA feed); it competes on *honesty about uncertainty*. So every arrival
// carries a confidence level, and that level is expressed ONLY through
// opacity, dot shape and freshness microcopy — never a new hue. The one
// reserved accent (mint here, magenta in the design mock) still means just
// "imminent / arriving", exactly as the locked spec demands.
//
//   live         GPS-monitored and the feed is fresh           solid ink
//   stale        GPS-monitored but the feed has aged            ink @ 50%
//   unconfirmed  timetabled but no live GPS (the "ghost bus")   "~" + faded
//   none         nothing coming                                 em-dash
//
// Derivation uses only data we actually have: LTA's `Monitored` flag
// (Service.monitored) and how long ago we last refreshed the stop
// (DataStore.lastRefresh → Freshness). Nothing is invented.

import SwiftUI

enum ArrivalConfidence: Equatable {
    case live
    case stale
    case unconfirmed
    case none

    /// Map an arrival to a confidence level. `feed` is the stop-level
    /// freshness (how recently we pulled arrivals); `monitored` is LTA's
    /// per-arrival GPS flag. A non-monitored arrival is always a ghost bus
    /// regardless of feed age — it's timetable data, not live.
    static func of(monitored: Bool, feed: Freshness) -> ArrivalConfidence {
        guard monitored else { return .unconfirmed }
        switch feed {
        case .live:             return .live
        case .stale, .offline:  return .stale
        }
    }

    /// Always returns empty string — ETA numerals never show a "~" prefix.
    /// Confidence is conveyed by the dot shape and freshness microcopy only.
    var etaPrefix: String { "" }

    /// Opacity applied to the ETA numeral. Always 1.0 — full-ink numerals
    /// signal timeliness; uncertainty is expressed by dot shape and microcopy.
    func numeralOpacity(stale: Double = 1.0) -> Double { 1.0 }

    /// Numeral colour. The reserved accent appears only for a *live*
    /// imminent arrival; everything else is solid ink (t.fg).
    func numeralColor(imminent: Bool, t: Theme) -> Color {
        (imminent && self == .live) ? t.accent : t.fg
    }

    /// Short status word for the provenance pill / chip.
    var statusWord: String {
        switch self {
        case .live:        return "Live"
        case .stale:       return "Estimated"
        case .unconfirmed: return "Scheduled"
        case .none:        return "—"
        }
    }

    /// One honest line of freshness microcopy. `ageSec` is how long ago the
    /// feed last refreshed (nil → omit the relative time).
    func microcopy(ageSec: Int?) -> String {
        switch self {
        case .live:        return ageSec.map { "live · \($0)s ago" } ?? "live"
        case .stale:       return ageSec.map { "updated \($0)s ago" } ?? "estimate aging"
        case .unconfirmed: return "scheduled · no live signal"
        case .none:        return "last bus gone"
        }
    }
}

// ─── Freshness dot ────────────────────────────────────────────────────
/// Tiny confidence dot. Hue-free: the *shape* carries the meaning so it
/// works for colour-blind users and doesn't spend the reserved accent.
///   live → filled ink · stale → hollow ring · unconfirmed → dashed ring
struct ConfidenceDot: View {
    let confidence: ArrivalConfidence
    let t: Theme
    var size: CGFloat = 7

    var body: some View {
        switch confidence {
        case .live:
            Circle().fill(t.soon).frame(width: size, height: size)
        case .stale, .none:
            Circle().stroke(t.faint, lineWidth: 1.5).frame(width: size, height: size)
        case .unconfirmed:
            Circle()
                .strokeBorder(t.faint,
                              style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: size, height: size)
        }
    }
}

// ─── Confidence-aware ETA numeral (inline use) ─────────────────────────
/// The arrival number, rendered as a solid, full-opacity, full-ink figure
/// regardless of confidence level. The selling point is timely, confident
/// information — uncertainty is communicated only by the dot shape and
/// freshness microcopy, never by dimming or a "~" prefix. Used in the Stop
/// list rows and anywhere a compact ETA appears. The screen-reader label
/// at the call site stays fully honest. See memory `feedback_timely_over_honest`.
struct ConfidenceETA: View {
    let eta: ETA                 // from fmtETA(seconds)
    let confidence: ArrivalConfidence
    let t: Theme
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold

    private var imminent: Bool { confidence == .live && eta.live }

    var body: some View {
        if confidence == .none {
            Text("—")
                .font(t.mono(size, weight: weight))
                .foregroundStyle(t.faint)
        } else if eta.big == "Arr" {
            // Arriving now — render the small word as the figure.
            Text(eta.small)
                .font(t.mono(size, weight: weight))
                .foregroundStyle(imminent ? t.accent : t.fg)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(eta.big)
                    .font(t.mono(size, weight: weight))
                    .foregroundStyle(imminent ? t.accent : t.fg)
                Text(eta.small)
                    .font(t.mono(size * 0.72, weight: .medium))
                    .foregroundStyle(imminent ? t.accent : t.dim)
            }
        }
    }
}

// ─── Status pill (Bus view) ────────────────────────────────────────────
/// LIVE / ESTIMATED / SCHEDULED pill. LIVE is the one place the accent
/// surfaces as a status dot (on an inverse pill), mirroring the design's
/// green-dot-in-navy-pill; the softer states use a hollow/dashed dot on a
/// raised surface so the gradient of certainty reads at a glance.
struct ConfidenceStatusPill: View {
    let confidence: ArrivalConfidence
    let t: Theme

    var body: some View {
        HStack(spacing: 5) {
            dot
            Text(label)
                .font(t.mono(10, weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(confidence == .live ? t.contrastFg : t.dim)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            confidence == .live ? AnyShapeStyle(t.contrast)
                                 : AnyShapeStyle(t.surfaceHi),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(confidence == .live ? Color.clear : t.line, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch confidence {
        case .live:        return "LIVE"
        case .stale:       return "ESTIMATED"
        case .unconfirmed: return "SCHEDULED"
        case .none:        return "—"
        }
    }

    @ViewBuilder private var dot: some View {
        switch confidence {
        case .live:
            Circle().fill(t.soon).frame(width: 6, height: 6)
        case .stale, .none:
            Circle().stroke(t.dim, lineWidth: 1.5).frame(width: 6, height: 6)
        case .unconfirmed:
            Circle().strokeBorder(t.dim, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 6, height: 6)
        }
    }

    private var accessibilityText: String {
        switch confidence {
        case .live:        return "Live arrival, tracked by GPS"
        case .stale:       return "Estimated — live signal aging"
        case .unconfirmed: return "Scheduled estimate, no live GPS signal"
        case .none:        return "No service"
        }
    }
}

// ─── Crowd meter glyph ─────────────────────────────────────────────────
/// Occupancy shown as a row of three person glyphs filled by load
/// (Seats=1, Standing=2, Crowded=3) and tinted green / amber / grey — the
/// "how full is the bus" metaphor riders already know from the LTA app.
/// (Deliberately NOT ascending bars: those read as a cellular-signal meter,
/// which is the wrong sense — more crowding is worse, not "stronger".)
/// Unknown shows three faint outlines, honestly rather than hidden.
struct CrowdMeter: View {
    let load: Load?          // nil → unknown
    let t: Theme
    var showLabel: Bool = true

    private var fill: Int {
        switch load {
        case .sea: return 1
        case .sda: return 2
        case .lsd: return 3
        case .none: return 0
        }
    }
    /// Fuller phrasing than `Load.label` so the bus-view hero reads
    /// "Seats available" rather than just "Seats".
    private var label: String {
        switch load {
        case .sea:        return "Seats available"
        case .sda:        return "Standing available"
        case .lsd:        return "Limited standing"
        case .none:       return "Crowd unknown"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: (load != nil && i < fill) ? "person.fill" : "person")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(personColor(i))
                }
            }
            if showLabel {
                Text(label)
                    .font(t.mono(10, weight: .medium))
                    .foregroundStyle(load == nil ? t.faint : occupancyColor(load, t: t))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(load == nil ? "Crowd unknown" : label)
    }

    /// Filled people take the occupancy hue; empties are hairline; an unknown
    /// load greys the whole row.
    private func personColor(_ i: Int) -> Color {
        guard load != nil else { return t.faint }
        return i < fill ? occupancyColor(load, t: t) : t.line
    }
}
