// Real iOS Live Activity — lock screen + Dynamic Island.
// Styled as a quote of the WhereSia departure board: board surfaces, Inter +
// IBM Plex Mono, route tile for the bus number, and the blue live accent as
// the ONLY colour — it marks the LIVE reading and the arrival moment.
// Palette, fonts and shared atoms (WServiceBadge, WLiveBadge) come from
// WidgetShared.swift (same extension target; the app module is unreachable).

import ActivityKit
import WidgetKit
import SwiftUI

private func etaText(_ s: LeyneActivityAttributes.ContentState) -> String {
    s.arrived ? "Now" : (s.etaMinutes <= 0 ? "Arr" : "\(s.etaMinutes)")
}

/// True when the state should render a live, OS-ticked m:ss countdown.
/// Requires a real monitored bus whose target Date is still in the future.
private func shouldShowTimer(_ s: LeyneActivityAttributes.ContentState) -> Bool {
    !s.arrived && s.monitored && s.eta > .now
}

/// Whisper-quiet estimate tell: a single faint "~" before a scheduled-only
/// ETA. The numeral is otherwise shown confidently (no dimming, no "sched"
/// unit) — timeliness is the selling point, so the Live Activity never
/// advertises a data gap. See memory `feedback_timely_over_honest`.
private func confPrefix(_ s: LeyneActivityAttributes.ContentState) -> String {
    (!s.monitored && !s.arrived && s.etaMinutes > 0) ? "~" : ""
}

// Deep link into the app's Bus view for this tracked service. The app
// (RootView.onOpenURL) maps lyne://bus/<stopCode>/<busNo> onto the same
// AppModel.open(...) path a notification tap uses, so tapping the lock-screen
// Live Activity or the Dynamic Island lands on Bus <busNo> at <stopCode>.
private func busURL(_ a: LeyneActivityAttributes) -> URL? {
    guard !a.stopCode.isEmpty, !a.busNo.isEmpty else { return nil }
    let bus = a.busNo.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed) ?? a.busNo
    return URL(string: "lyne://bus/\(a.stopCode)/\(bus)")
}

// ─── Journey phase + progress ────────────────────────────────────────
// The hero is the bus's approach toward your stop, not a bare number. Both
// the phase word and the track position are *derived* from the state the app
// already pushes (GPS-driven `stopsAway`, `etaMinutes`, `arrived`) — nothing
// here is invented, so the visual stays as honest as the data behind it.
private enum LivePhase {
    case here          // bus at your stop (arrived)
    case approaching   // one stop out / imminent
    case enroute       // still some stops away

    var label: String {
        switch self {
        case .here:        return "Bus is here"
        case .approaching: return "Approaching"
        case .enroute:     return "Next stop"
        }
    }
    /// The blue accent marks the arrival moment ONLY — the resting palette is
    /// greyscale, so only "Bus is here" tints; approaching / en-route stay
    /// neutral (colour discipline: blue = live/arriving, nothing else).
    var isArrival: Bool { self == .here }
}

private func phase(_ s: LeyneActivityAttributes.ContentState) -> LivePhase {
    if s.arrived { return .here }
    if s.stopsAway >= 0 { return s.stopsAway <= 1 ? .approaching : .enroute }
    // No stops-away signal — fall back to the ETA.
    return s.etaMinutes <= 1 ? .approaching : .enroute
}

/// The detail line under the phase word ("1 stop away", "Arrival in 3 min").
private func phaseDetail(_ s: LeyneActivityAttributes.ContentState) -> String {
    if s.arrived { return "" }
    if s.stopsAway >= 0 && s.stopsAway <= 1 {
        return s.stopsAway == 1 ? "1 stop away" : "Arriving now"
    }
    if s.stopsAway > 1 { return "\(s.stopsAway) stops away" }
    return s.etaMinutes <= 0 ? "Arriving now"
        : "Arrival in \(s.etaMinutes) min"
}

/// Bus position on the final-approach track, 0 (far) … 1 (at your stop).
/// Uses real stops-away over a short window; falls back to the ETA when the
/// route can't be resolved. Floored a touch above 0 so the bus glyph never
/// hugs the far edge and reads as "stuck".
private func journeyProgress(_ s: LeyneActivityAttributes.ContentState) -> Double {
    if s.arrived { return 1 }
    if s.stopsAway >= 0 {
        let window = 6.0
        return max(0.06, 1 - min(Double(s.stopsAway), window) / window)
    }
    let m = Double(max(0, s.etaMinutes))
    return max(0.06, 1 - min(m, 15) / 15)
}

// ─── Route progress track ────────────────────────────────────────────
// A capsule rail with the travelled portion + the bus glyph in the LIVE
// blue (this is live GPS tracking — blue is exactly what the accent is
// for), and your stop as a neutral node at the right end that turns blue
// when the bus lands on it.
private struct JourneyTrack: View {
    let progress: Double
    let arrived: Bool
    var compact = false

    var body: some View {
        let busR: CGFloat = compact ? 8 : 11
        let h = busR * 2
        let nodeTint = arrived ? wAccentSoft : wFg
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(0, w - busR)          // keep the bus glyph inside
            let x = min(usable, max(busR, usable * progress))
            ZStack(alignment: .leading) {
                Capsule().fill(wDim.opacity(0.35)).frame(height: 3)
                Capsule().fill(wAccentSoft).frame(width: x, height: 3)

                // Destination node — your stop — at the rail's right end.
                ZStack {
                    Circle().fill(wBg)
                    Circle().strokeBorder(nodeTint, lineWidth: 2)
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.system(size: busR))
                        .foregroundStyle(nodeTint)
                }
                .frame(width: h, height: h)
                .position(x: w - busR, y: h / 2)

                // The bus, travelling left→right toward the node.
                ZStack {
                    Circle().fill(wAccentSoft)
                    Image(systemName: "bus.fill")
                        .font(.system(size: busR * 0.9, weight: .bold))
                        .foregroundStyle(wBg)
                }
                .frame(width: h, height: h)
                .position(x: x, y: h / 2)
                .widgetAccentable()
            }
            .frame(height: h)
        }
        .frame(height: h)
        .animation(.easeInOut(duration: 0.4), value: progress)
    }
}

struct LeyneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LeyneActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(wBg)
                .activitySystemActionForegroundColor(wFg)
                .widgetURL(busURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WServiceBadge(no: context.attributes.busNo)
                        // Inset from the island's rounded edge so the tile
                        // doesn't hug / clip the corner.
                        .padding(.leading, 12)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.arrived {
                            Text("Now")
                                .font(wMono(22, .semibold))
                                .foregroundStyle(wAccentSoft)
                                .lineLimit(1)
                        } else if shouldShowTimer(context.state) {
                            Text(timerInterval: .now...context.state.eta, countsDown: true)
                                .font(wMono(22, .semibold))
                                .foregroundStyle(wFg)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(confPrefix(context.state) + etaText(context.state))
                                    .font(wMono(22, .semibold))
                                    .foregroundStyle(wFg)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if context.state.etaMinutes > 0 {
                                    Text("min")
                                        .font(wMono(10)).foregroundStyle(wDim)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // .widgetURL here makes the expanded info area tap → Bus view.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(phase(context.state).label)
                                .font(wSans(14, .bold))
                                .foregroundStyle(phase(context.state).isArrival ? wAccentSoft : wFg)
                            let detail = phaseDetail(context.state)
                            if !detail.isEmpty {
                                Text("· \(detail)")
                                    .font(wSans(12, .medium)).foregroundStyle(wDim).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        HStack(spacing: 10) {
                            Text(context.attributes.stopName)
                                .font(wSans(11, .semibold)).foregroundStyle(wFg)
                                .lineLimit(1).layoutPriority(1)
                            JourneyTrack(progress: journeyProgress(context.state),
                                         arrived: context.state.arrived)
                                .frame(minWidth: 60)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 2)
                    .widgetURL(busURL(context.attributes))
                }
            } compactLeading: {
                // Bus NUMBER, not a generic glyph — the identity is the whole
                // point. Paired with the ETA in compactTrailing, the collapsed
                // island answers "which bus, how long" at a glance.
                Text(context.attributes.busNo)
                    .font(wMono(14, .bold))
                    .foregroundStyle(context.state.arrived ? wAccentSoft : wFg)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .widgetAccentable()
                    .widgetURL(busURL(context.attributes))
            } compactTrailing: {
                // STATIC minute value only — never a `Text(timerInterval:)` here.
                // A self-sizing timer reserves width for its widest value, which
                // balloons the compact island across the whole notch and covers
                // the status-bar clock + battery. The live m:ss countdown lives
                // on the lock screen + expanded views, where there's room.
                Text(context.state.arrived
                     ? "Now"
                     : confPrefix(context.state) + etaText(context.state)
                        + (context.state.etaMinutes <= 0 ? "" : "m"))
                    .font(wMono(13, .semibold))
                    .foregroundStyle(context.state.arrived ? wAccentSoft : wFg)
                    .widgetURL(busURL(context.attributes))
            } minimal: {
                // The minimal view (multiple Live Activities) is the tiniest notch
                // presentation — show the ETA, the one actionable number. The app
                // only ever runs ONE bus Live Activity at a time, so the bus
                // number isn't needed to disambiguate here (it's in the
                // compact/expanded views). Static minute, never a wide timer.
                Text(context.state.arrived ? "Now" : etaText(context.state))
                    .font(wMono(11, .bold))
                    .foregroundStyle(context.state.arrived ? wAccentSoft : wFg)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .widgetAccentable()
                    .widgetURL(busURL(context.attributes))
            }
            .keylineTint(context.state.arrived ? wAccentSoft : wFg)
        }
    }
}

private struct LockScreenView: View {
    let attributes: LeyneActivityAttributes
    let state: LeyneActivityAttributes.ContentState

    var body: some View {
        let p = phase(state)
        // Quotes the in-app Track Bus live card: route tile + TOWARD on the
        // left, the COUNTDOWN as the hero on the right with its "MIN TO YOUR
        // STOP" caption, a board rule, then phase + LIVE + your stop against
        // the blue approach track. (The first pass kept the old monochrome
        // hierarchy — phase word as hero, timer tucked in a corner — and read
        // as the old Leyne design; owner-flagged.)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                WServiceBadge(no: attributes.busNo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TOWARD").font(wMono(8.5)).kerning(0.8).foregroundStyle(wDim)
                    Text(attributes.dest)
                        .font(wSans(13.5, .bold))
                        .foregroundStyle(wFg).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Group {
                        if state.arrived {
                            Text("Now")
                                .font(wMono(27, .bold))
                                .foregroundStyle(wAccentSoft)
                        } else if shouldShowTimer(state) {
                            // Live bus: OS-ticked countdown, no push needed.
                            Text(timerInterval: .now...state.eta, countsDown: true)
                                .font(wMono(27, .bold))
                                .foregroundStyle(wFg)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        } else {
                            // Schedule-only: static minute, whisper-quiet "~".
                            Text(confPrefix(state) + etaText(state))
                                .font(wMono(27, .bold))
                                .foregroundStyle(wFg)
                                .lineLimit(1)
                        }
                    }
                    Text(state.arrived ? "AT YOUR STOP"
                         : shouldShowTimer(state) ? "TO YOUR STOP" : "MIN TO YOUR STOP")
                        .font(wMono(8)).kerning(0.7).foregroundStyle(wDim)
                }
            }

            Rectangle().fill(wLine).frame(height: 1)

            // Phase + LIVE on the left, your stop riding the blue track right.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(p.label)
                            .font(wSans(15, .heavy))
                            .foregroundStyle(p.isArrival ? wAccentSoft : wFg)
                            .widgetAccentable(p.isArrival)
                            .lineLimit(1)
                        if state.monitored && !state.arrived { WLiveBadge() }
                    }
                    // Detail + your stop in one quiet line ("2 stops away ·
                    // Farrer Rd Stn Exit A").
                    Text(detailLine)
                        .font(wSans(11, .medium))
                        .foregroundStyle(wDim)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                JourneyTrack(progress: journeyProgress(state), arrived: state.arrived)
                    .frame(minWidth: 80)
            }
        }
        .padding(16)
    }

    private var detailLine: String {
        let detail = phaseDetail(state)
        return detail.isEmpty ? attributes.stopName : "\(detail) · \(attributes.stopName)"
    }
}

@main
struct LeyneWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home Screen widgets are live again — the app already publishes their
        // data to the App Group every refresh (mirrorNearbyToWidget /
        // mirrorFavServicesToWidget / pinned-stop publish in AppModel+DataStore).
        LeyneStopWidget()          // Home Screen — saved stop departure board
                                   // (was compiled but missing from the bundle,
                                   // so it never appeared in the gallery)
        LeyneNearbyWidget()        // Home Screen — nearest stop, live mini board
        LeyneFavServiceWidget()    // Home Screen — favourited service
        LeyneLiveActivity()        // Lock Screen / Dynamic Island
    }
}
