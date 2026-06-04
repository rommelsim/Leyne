// SoftStopCard — Leyne 2.4.0 Home card: a stop's identity (pin tile · name ·
// "Stop {code} · road" · distance row) and a row of card-style next-bus chips.
//
// Chips preview the soonest buses (sorted by ETA). The lead chip is filled
// green with an "Arriving soon" tag when it's an imminent *live* arrival; the
// rest are bordered tiles with a proximity-coloured ETA. Colour carries only
// proximity — confidence still reads from the whisper "~" (see fmtETA /
// Confidence.swift). Caps at 4 chips + a "+N more" tile, all equal-width.

import SwiftUI

/// Compact next-bus chip: service number over a proximity-coloured ETA.
struct MiniBusChip: View {
    let t: Theme
    let svc: String
    let etaSec: Int
    let confidence: ArrivalConfidence
    /// The lead/imminent chip — filled green with an "Arriving soon" tag.
    var highlight: Bool = false

    var body: some View {
        let eta = fmtETA(etaSec)
        let arriving = eta.big == "Arr"
        let color = etaColor(etaSec: etaSec, confidence: confidence, t: t)
        let whisper = confidence == .stale || confidence == .unconfirmed

        VStack(alignment: .leading, spacing: 3) {
            Text(svc)
                .font(t.sans(15, weight: .bold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(arriving ? eta.small : "\(eta.big) \(eta.small)")
                    .font(t.mono(11, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if whisper {
                    Text("~")
                        .font(t.mono(8, weight: .regular))
                        .foregroundStyle(t.faint)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
            }
            if highlight {
                Text("Arriving soon")
                    .font(t.sans(9.5, weight: .semibold))
                    .foregroundStyle(t.soon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(highlight ? t.soonBg : t.surface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(highlight ? t.soon.opacity(0.55) : t.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel(eta: eta, arriving: arriving))
    }

    private func a11yLabel(eta: ETA, arriving: Bool) -> String {
        let when = arriving ? "arriving now" : "\(eta.big) \(eta.small)"
        let conf: String
        switch confidence {
        case .live:        conf = ""
        case .stale:       conf = ", estimated"
        case .unconfirmed: conf = ", scheduled"
        case .none:        conf = ""
        }
        return "Bus \(svc), \(when)\(conf)"
    }
}

/// A stop card: identity + distance row, then a row of card-style bus chips.
/// Tapping opens the stop.
struct SoftStopCard: View {
    let t: Theme
    let name: String
    let code: String
    let desc: String          // road name / "opp Blk 445"; may be empty
    let trailing: String?     // distance ("69 m") or walk ("3 min"); may be nil
    let services: [Service]
    let feed: Freshness
    let onTap: () -> Void
    /// Favourites: a gold star on the pin tile.
    var favourite: Bool = false
    /// Walk time appended to the distance row ("· 1 min walk").
    var walk: String? = nil
    /// When set, shows an in-card footer: "Updated N ago" + the soonest bus's
    /// occupancy. Used on the Favourites screen.
    var updatedLabel: String? = nil

    private static let maxChips = 4

    /// Soonest buses first, so the lead chip is the most imminent arrival —
    /// matching the mockup's ETA-ordered preview.
    private var sorted: [Service] {
        services.sorted { $0.etaSec < $1.etaSec }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                if !sorted.isEmpty {
                    chipRow
                } else {
                    quietRow
                }
                if let updatedLabel {
                    footer(updatedLabel)
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(t.surfaceHi)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.fg)
                }
                .frame(width: 38, height: 38)
                .overlay(alignment: .topTrailing) {
                    if favourite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "F5B500"))
                            .padding(2)
                            .background(t.surface, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(t.mono(11.5))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            if let trailing {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10, weight: .semibold))
                    Text(walk.map { "\(trailing) away · \($0) walk" } ?? "\(trailing) away")
                        .font(t.mono(11.5))
                }
                .foregroundStyle(t.dim)
                .padding(.leading, 2)
            }
        }
    }

    private var subtitle: String {
        desc.isEmpty ? "Stop \(code)" : "Stop \(code) · \(desc)"
    }

    /// In-card footer (Favourites): freshness on the left, the soonest bus's
    /// crowd on the right.
    private func footer(_ updatedLabel: String) -> some View {
        VStack(spacing: 10) {
            Rectangle().fill(t.line).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.dim)
                Text(updatedLabel)
                    .font(t.mono(11))
                    .foregroundStyle(t.dim)
                Spacer(minLength: 8)
                if let lead = sorted.first {
                    CrowdMeter(load: lead.load, t: t)
                }
            }
        }
    }

    private var chipRow: some View {
        let shown = Array(sorted.prefix(Self.maxChips))
        return HStack(alignment: .top, spacing: 7) {
            ForEach(Array(shown.enumerated()), id: \.element.no) { i, s in
                let conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed)
                MiniBusChip(t: t, svc: s.no, etaSec: s.etaSec, confidence: conf,
                            highlight: i == 0 && conf == .live
                                       && ETATier.of(etaSec: s.etaSec).isImminent)
            }
            if sorted.count > Self.maxChips {
                moreChip(count: sorted.count - Self.maxChips)
            }
        }
    }

    private func moreChip(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("+\(count)")
                .font(t.sans(15, weight: .bold))
                .foregroundStyle(t.dim)
            Text("more")
                .font(t.mono(11, weight: .medium))
                .foregroundStyle(t.faint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(count) more buses")
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
