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

    /// "~" prefixes ghost ETAs so a scheduled-only number never reads as a
    /// confident live one. Stale keeps the bare number (it *was* live).
    var etaPrefix: String { self == .unconfirmed ? "~" : "" }

    /// Opacity applied to the ETA numeral. Stale softens to signal aging;
    /// ghost fades further (and carries the "~" + dashed dot to stay
    /// unmistakable even though both are dimmed).
    func numeralOpacity(stale: Double = 0.5) -> Double {
        switch self {
        case .live:        return 1
        case .stale:       return stale
        case .unconfirmed: return 0.42
        case .none:        return 1
        }
    }

    /// Numeral colour. The reserved accent appears only for a *live*
    /// imminent arrival; everything else is monochrome ink so confidence
    /// reads from opacity/shape, not colour.
    func numeralColor(imminent: Bool, t: Theme) -> Color {
        if self == .none { return t.faint }
        return (imminent && self == .live) ? t.accent : t.fg
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
            Circle().fill(t.fg).frame(width: size, height: size)
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
/// The arrival number with the full confidence treatment applied. Used in
/// the Stop list rows and anywhere a compact ETA appears. For the Bus-view
/// hero numeral the treatment is applied inline (different layout), reusing
/// the `ArrivalConfidence` helpers above.
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
                .foregroundStyle(confidence.numeralColor(imminent: imminent, t: t))
                .opacity(confidence.numeralOpacity())
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(confidence.etaPrefix)\(eta.big)")
                    .font(t.mono(size, weight: weight))
                    .foregroundStyle(confidence.numeralColor(imminent: imminent, t: t))
                Text(eta.small)
                    .font(t.mono(size * 0.72, weight: .medium))
                    .foregroundStyle(imminent ? t.accent : t.dim)
            }
            .opacity(confidence.numeralOpacity())
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
            Circle().fill(t.accent).frame(width: 6, height: 6)
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
/// Three ascending bars filled by load (Seats=1, Standing=2, Crowded=3),
/// with an unknown state rendered as dashed outlines. Replaces the
/// colour-dot + word so crowding reads as a small pictogram — and "unknown"
/// is shown honestly rather than hidden. Bars are monochrome ink; this is a
/// data signal, not a place to spend the accent.
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
    private var label: String { load?.label ?? "Crowd —" }
    private let heights: [CGFloat] = [8, 11, 14]

    var body: some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                    bar(filled: load != nil && i < fill, height: h)
                }
            }
            .frame(height: 14)
            if showLabel {
                Text(label)
                    .font(t.mono(10, weight: .medium))
                    .foregroundStyle(load == nil ? t.faint : t.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(load == nil ? "Crowd unknown" : "Crowd: \(label)")
    }

    @ViewBuilder
    private func bar(filled: Bool, height: CGFloat) -> some View {
        if load == nil {
            RoundedRectangle(cornerRadius: 1.5)
                .strokeBorder(t.faint, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 4, height: height)
        } else if filled {
            RoundedRectangle(cornerRadius: 1.5).fill(t.fg)
                .frame(width: 4, height: height)
        } else {
            RoundedRectangle(cornerRadius: 1.5).stroke(t.line, lineWidth: 1)
                .frame(width: 4, height: height)
        }
    }
}
