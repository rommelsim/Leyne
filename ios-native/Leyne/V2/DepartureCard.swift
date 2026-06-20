// DepartureCard — Glance Phase 1 hero component.
//
// Matches the prototype's `.dep` card: ink bus-number chip · destination +
// crowd glyph + "then X · Y min" sub-row · big rounded tabular live countdown.
//
// Live countdown states (mirrors prototype `paintDep`):
//   live       monitored + feed fresh  — ink text + pulsing wave mark
//   arriving   etaSec ≤ 60 / "Arr"    — `go` green + pulse
//   scheduled  monitored == false      — ink3 (muted) + "~" prefix
//
// The countdown is driven by `m.tick` (AppModel's per-second @Published Int)
// which is already live for every pinned and nearby stop. No new Timer is
// introduced here.
//
// Tap → SoftRoute.bus(stopCode:svc:) via `onTap`, which the host view
// (SoftHomeView) routes through the existing NavigationStack.

import SwiftUI

// MARK: - Countdown state

/// Which visual state the countdown numeral is in. Drives colour + animation.
private enum CountdownState {
    case live        // GPS-monitored, feed is fresh
    case arriving    // ≤ 60 s (including "Arr")
    case scheduled   // not monitored — timetable only

    static func of(eta: ETA, confidence: ArrivalConfidence) -> CountdownState {
        if confidence == .unconfirmed { return .scheduled }
        if eta.live || eta.big == "Arr" { return .arriving }
        return .live
    }
}

// MARK: - DepartureCard

struct DepartureCard: View {
    // MARK: Inputs

    let t: Theme
    let service: Service      // the next-bus record
    let stopCode: String       // needed for the tap navigation callback
    let feed: Freshness        // stop-level freshness from DataStore
    let tick: Int              // m.tick — forces a per-second ETA recompute
    /// Up to two following-bus ETAs to show in "then X · Y min".
    let followingEtas: [Int]   // seconds from now for next-next arrivals
    let onTap: () -> Void      // routes to SoftRoute.bus(...)

    // MARK: Derived

    private var eta: ETA { fmtETA(service.etaSec) }
    private var confidence: ArrivalConfidence {
        ArrivalConfidence.of(monitored: service.monitored, feed: feed)
    }
    private var countdown: CountdownState { CountdownState.of(eta: eta, confidence: confidence) }

    // MARK: Body

    var body: some View {
        let _ = tick   // subscribe to the 1 s pulse so SwiftUI re-evaluates
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                busBadge
                midSection
                countdownSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glanceCard(fill: t.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens bus \(service.no) detail")
    }

    // MARK: Sub-views

    /// Ink-filled rounded-square bus number chip.
    /// Sized at 48×48 (badge--md) with a 14-pt radius matching `--r-badge`.
    private var busBadge: some View {
        Text(service.no)
            .font(t.rounded(19, .bold))
            .foregroundStyle(t.bg)          // paper colour on ink fill
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 48, height: 48)
            .background(t.fg,
                        in: RoundedRectangle(cornerRadius: Theme.badgeRadius,
                                             style: .continuous))
            .accessibilityHidden(true)      // combined into parent label
    }

    /// Destination + sub-row (crowd glyph + "then …").
    private var midSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Destination
            Text(service.dest.isEmpty ? "Unknown destination" : service.dest)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .truncationMode(.tail)

            // Sub-row: crowd glyph · "then X · Y min"
            HStack(spacing: 8) {
                CrowdMeter(load: service.load, t: t, showLabel: false)
                thenLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)   // combined into parent label
    }

    /// "then 9 · 15 min" label from following buses, using ink3 per the spec's
    /// `.dep__then` style. Hides when there are no following ETAs.
    @ViewBuilder
    private var thenLabel: some View {
        if !followingEtas.isEmpty {
            let parts = followingEtas.prefix(2).map { sec -> String in
                let m = sec / 60
                return m <= 0 ? "Arr" : "\(m)"
            }
            let joined = parts.joined(separator: " · ")
            Text("then \(joined) min")
                .font(t.sans(12, weight: .medium))
                .foregroundStyle(t.ink3)
                .lineLimit(1)
        }
    }

    /// The big right-hand countdown — the "hero" of the departure card.
    private var countdownSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Wave mark for live arrivals, sized to 13×13 matching the prototype.
            if countdown == .live {
                liveWave
                    .frame(width: 13, height: 13)
                    .foregroundStyle(t.go)
            }

            // The number
            countdownNumeral

            // Unit label ("min" / "now")
            Text(eta.big == "Arr" ? "now" : "min")
                .font(t.rounded(11, .semibold))
                .foregroundStyle(t.ink3)
                .monospacedDigit()
        }
        .frame(minWidth: 56, alignment: .trailing)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var countdownNumeral: some View {
        let numeral = eta.big == "Arr" ? "0" : eta.big
        let color: Color = {
            switch countdown {
            case .arriving:  return t.go
            case .scheduled: return t.ink3
            case .live:      return t.fg
            }
        }()

        if countdown == .arriving {
            // "is-go" state: green + subtle 2-second opacity breathe via TimelineView.
            // TimelineView drives its own repaint without a retained timer, which is
            // safe here since DepartureCard only lives while the Home view is on screen.
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let opacity = 0.6 + 0.4 * (0.5 + 0.5 * sin(phase * .pi * 2 / 2.0))
                Text(numeral)
                    .font(t.eta(40, .heavy))
                    .foregroundStyle(color)
                    .opacity(opacity)
                    .contentTransition(.numericText(countsDown: true))
            }
        } else if countdown == .scheduled {
            // Scheduled — small "~" whisper prefix + muted numeral.
            // Both Text views carry their own font so the tilde can be smaller.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("~")
                    .font(t.eta(22, .semibold))
                    .foregroundStyle(t.ink3.opacity(0.7))
                    .accessibilityHidden(true)
                Text(numeral)
                    .font(t.eta(40, .heavy))
                    .foregroundStyle(color)
            }
        } else {
            // Live, non-arriving — ink numeral with numeric roll on minute change.
            Text(numeral)
                .font(t.eta(40, .heavy))
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
        }
    }

    /// SF Symbols wave mark for a live arrival. The symbol's own rendering
    /// already implies broadcast/signal; we add a phase-matched opacity breathe
    /// using `TimelineView` so the animation runs without a stateful timer.
    private var liveWave: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            // 1.8 s period sinewave → opacity oscillates 0.35 … 1.0
            let opacity = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase * .pi * 2 / 1.8))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .opacity(opacity)
        }
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        let busLine = "Bus \(service.no)"
        let dest = service.dest.isEmpty ? "" : " to \(service.dest)"
        let etaStr: String = {
            if eta.big == "Arr" { return "arriving now" }
            return "in \(eta.big) minutes"
        }()
        let conf = confidence == .unconfirmed ? ", scheduled estimate" : ""
        return "\(busLine)\(dest), \(etaStr)\(conf)"
    }
}

// MARK: - Skeleton (loading placeholder)

/// A shimmer-free loading placeholder that matches the DepartureCard layout.
/// Shown while the first arrivals fetch is in-flight for a stop.
struct DepartureCardSkeleton: View {
    let t: Theme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Badge placeholder
            RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
                .fill(t.surfaceHi)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
                // Destination line
                Capsule().fill(t.surfaceHi).frame(width: 120, height: 13)
                // Sub-row
                Capsule().fill(t.surfaceHi).frame(width: 80, height: 11)
            }
            Spacer()
            // ETA placeholder
            Capsule().fill(t.surfaceHi).frame(width: 44, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glanceCard(fill: t.surface)
        // Shimmer sweep via phase animation on the fill opacity.
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
