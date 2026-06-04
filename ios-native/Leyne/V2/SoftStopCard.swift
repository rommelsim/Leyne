// SoftStopCard — the Leyne 3.0 Home card: a stop, its identity, and a
// compact rundown of the next few buses as mini-chips. Used for both the
// Pinned and Nearby sections of Home so the two read as one language.
//
// Each mini-chip carries the confidence treatment (live solid · stale
// dimmed · ghost "~" + dashed), so even the glance-level preview is honest
// about which arrivals it trusts. Caps at 4 chips + "+N", matching the
// prototype's StopCard (it doesn't wrap — keeps the card a fixed rhythm).

import SwiftUI

/// Compact next-bus chip: service badge + confidence-treated ETA.
struct MiniBusChip: View {
    let t: Theme
    let svc: String
    let etaSec: Int
    let confidence: ArrivalConfidence

    var body: some View {
        let eta = fmtETA(etaSec)
        let arriving = eta.big == "Arr"
        let imminent = confidence == .live && eta.live
        // Whisper-quiet: the chip always reads as a confident arrival; the
        // only estimate tell is a faint trailing "~". No dimming, no dashed
        // outline, no "~" prefix — timeliness is the promise.
        let whisper = confidence == .stale || confidence == .unconfirmed

        HStack(spacing: 5) {
            // Inner service micro-pill.
            Text(svc)
                .font(t.mono(12, weight: .bold))
                .foregroundStyle(t.fg)
                .padding(.horizontal, 5)
                .frame(minWidth: 22, minHeight: 18)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(t.line, lineWidth: 0.5))

            HStack(spacing: 1) {
                Text(label(eta: eta, arriving: arriving))
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(imminent ? t.accent : t.dim)
                    .lineLimit(1)
                if whisper {
                    Text("~")
                        .font(t.mono(9, weight: .regular))
                        .foregroundStyle(t.faint)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 9)
        .frame(height: 27)
        .background(t.surfaceHi, in: Capsule())
        .overlay(Capsule().stroke(t.line, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(eta: eta, arriving: arriving))
    }

    private func label(eta: ETA, arriving: Bool) -> String {
        if arriving { return "now" }
        return "\(eta.big) \(eta.small)"
    }

    private func a11y(eta: ETA, arriving: Bool) -> String {
        let word: String
        switch confidence {
        case .live: word = ""
        case .stale: word = ", estimated"
        case .unconfirmed: word = ", scheduled"
        case .none: word = ""
        }
        let when = arriving ? "arriving now" : "\(eta.big) \(eta.small)"
        return "Bus \(svc), \(when)\(word)"
    }
}

/// A stop card: identity (pin tile · name · code · road) + distance, then a
/// row of mini-bus chips. Tapping opens the stop.
struct SoftStopCard: View {
    let t: Theme
    let name: String
    let code: String
    let desc: String          // road name / "opp Blk 445"; may be empty
    let trailing: String?     // distance ("80 m") or walk ("3 min"); may be nil
    let services: [Service]
    let feed: Freshness
    let onTap: () -> Void

    private static let maxChips = 4

    /// Chips are ordered by bus number (natural numeric, so 1 < 2 < 5 < 78 <
    /// 103 and "21A" sorts beside 21), then the first 4 are shown. So a stop
    /// serving {2,103,5,78,1} previews {1,2,5,78} with a "+1". `localized­
    /// StandardCompare` handles the numeric ordering + lettered variants.
    private var sorted: [Service] {
        services.sorted { $0.no.localizedStandardCompare($1.no) == .orderedAscending }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 11) {
                headerRow
                if !sorted.isEmpty {
                    chipRow
                } else {
                    quietRow
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(name)")
    }

    private var headerRow: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(t.surfaceHi)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.fg)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(t.sans(16, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(desc.isEmpty ? code : "\(code) · \(desc)")
                    .font(t.mono(11.5))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.faint)
        }
    }

    private var chipRow: some View {
        // Wrap (never compress) so a chip's service number + ETA always read
        // in full — matching the prototype's flex-wrap. Each chip takes its
        // intrinsic width via .fixedSize. `stickyLast` glues the "+N" badge to
        // the last chip so the overflow count can never wrap onto a line by
        // itself (which read as dead space); it pulls the last chip down with
        // it instead, giving a clean trailing "[chip] +N".
        let hasOverflow = sorted.count > Self.maxChips
        return FlowLayout(spacing: 6, lineSpacing: 6, stickyLast: hasOverflow) {
            ForEach(Array(sorted.prefix(Self.maxChips)), id: \.no) { s in
                MiniBusChip(t: t, svc: s.no, etaSec: s.etaSec,
                            confidence: ArrivalConfidence.of(monitored: s.monitored, feed: feed))
                    .fixedSize()
            }
            if hasOverflow {
                Text("+\(sorted.count - Self.maxChips)")
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(t.faint)
                    .fixedSize()
                    .frame(height: 27)
            }
        }
    }

    private var quietRow: some View {
        HStack(spacing: 7) {
            ConfidenceDot(confidence: .stale, t: t, size: 6)
            Text("No live arrivals right now")
                .font(t.mono(11))
                .foregroundStyle(t.faint)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - FlowLayout

/// Minimal wrapping layout (iOS 16+ `Layout`): lays children left-to-right,
/// wrapping to a new line when the next child would overflow the proposed
/// width. Used for the wrapping mini-bus chips so nothing truncates.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// When true, the final subview is glued to the one before it: the pair
    /// wraps together so the last subview can never start a line alone. Used
    /// for the "+N" overflow badge so it always trails a chip, never floats on
    /// an otherwise-empty line.
    var stickyLast: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let (_, size) = resolve(sizes: sizes, maxW: proposal.width ?? .infinity)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let (origins, _) = resolve(sizes: sizes, maxW: bounds.width)
        for (i, sv) in subviews.enumerated() {
            let p = CGPoint(x: bounds.minX + origins[i].x, y: bounds.minY + origins[i].y)
            sv.place(at: p, anchor: .topLeading, proposal: ProposedViewSize(sizes[i]))
        }
    }

    /// Single line-breaking pass shared by sizing and placement so the
    /// reserved height always matches where subviews actually land. Returns
    /// each subview's origin (relative to the layout's top-leading) and the
    /// total content size.
    private func resolve(sizes: [CGSize], maxW: CGFloat) -> ([CGPoint], CGSize) {
        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        let n = sizes.count
        var i = 0
        while i < n {
            // The last chip + sticky badge form one unbreakable group: wrap
            // them together when the group won't fit on the current line.
            if stickyLast, n >= 2, i == n - 2 {
                let chip = sizes[n - 2], badge = sizes[n - 1]
                let groupW = chip.width + spacing + badge.width
                if x > 0, x + groupW > maxW { x = 0; y += lineH + lineSpacing; lineH = 0 }
                origins[n - 2] = CGPoint(x: x, y: y)
                x += chip.width + spacing
                lineH = max(lineH, chip.height)
                origins[n - 1] = CGPoint(x: x, y: y)
                x += badge.width + spacing
                lineH = max(lineH, badge.height)
                widest = max(widest, x - spacing)
                break
            }
            let s = sizes[i]
            if x > 0, x + s.width > maxW { x = 0; y += lineH + lineSpacing; lineH = 0 }
            origins[i] = CGPoint(x: x, y: y)
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
            i += 1
        }
        return (origins, CGSize(width: min(maxW, widest), height: y + lineH))
    }
}
