// Real iOS Live Activity — lock screen + Dynamic Island.
// "Soft blue 4b": the lock screen is a light, near-white blurred board (SF,
// same as the app) with the darker #2E8FE0 blue as the live accent — it marks
// the LIVE reading and the arrival moment. Those colours apply in
// `.fullColor` rendering only; see LockScreenView's `renderingMode` note for
// what happens in the system's accented/vibrant modes. The Dynamic Island always renders on the system's own
// black chrome regardless of app styling, so its content uses a SEPARATE
// dark-context pair: white/light-grey copy (wIslandFg/wIslandDim) and the
// lighter #5CB8F2 accent (wIslandBlue) instead of the lock screen's tokens.
// Palette, fonts and shared atoms (WServiceBadge) come from
// WidgetShared.swift (same extension target; the app module is unreachable).
//
// LeyneActivityAttributes.ContentState (Leyne/LeyneActivityAttributes.swift)
// is an unchanged contract — no crowd field is pushed into it, so the
// Dynamic Island footer shows "N stops away" (from `stopsAway`, already
// pushed) and does NOT show crowd dots, even though the shared design spec
// asks for them there. Inventing a crowd read with no backing data would
// break the "never guess" rule the rest of this pass follows; see the
// widget-ETA note in LeyneNearbyWidget.swift for the same call made
// elsewhere. Flagged in the handoff report.

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
    /// greyscale/accent-neutral, so only "Bus is here" tints; approaching /
    /// en-route stay neutral (colour discipline: blue = live/arriving,
    /// nothing else).
    var isArrival: Bool { self == .here }
}

private func phase(_ s: LeyneActivityAttributes.ContentState) -> LivePhase {
    if s.arrived { return .here }
    if s.stopsAway >= 0 { return s.stopsAway <= 1 ? .approaching : .enroute }
    // No stops-away signal — fall back to the ETA.
    return s.etaMinutes <= 1 ? .approaching : .enroute
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
// A 4pt rail with the travelled portion filled in the accent colour, and a
// glowing 12pt dot riding the head of the fill — the journey's current
// position, nothing more literal than that (no bus glyph, no destination
// node): matches the shared design spec exactly. `accent`/`rail` are
// parameterised because this view is shared between the light lock-screen
// (default: #2E8FE0 accent, dark hairline rail) and the always-dark Dynamic
// Island bottom region (passed #5CB8F2 accent, translucent-white rail).
/// The Dynamic Island's compact/minimal chip: a 22pt filled square (not the
/// pill-shaped `WServiceBadge` used elsewhere) — per the shared design
/// spec's "22pt square style" call-out for the collapsed island. Uses the
/// lighter #5CB8F2 island accent since this always sits on black chrome.
private struct WIslandChip: View {
    let no: String
    var body: some View {
        Text(no)
            .font(wMono(10.5, .heavy))
            .foregroundStyle(wIslandBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 22, height: 22)
            .background(wIslandBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(wIslandBlue.opacity(0.5), lineWidth: 1))
            .widgetAccentable()
    }
}

private struct JourneyTrack: View {
    let progress: Double
    let arrived: Bool
    var compact = false
    var accent: Color = wAccentBlue
    var rail: Color = Color.black.opacity(0.08)

    var body: some View {
        let dotSize: CGFloat = compact ? 9 : 12
        let trackH: CGFloat = 4
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(0, w - dotSize)
            let x = min(usable, max(dotSize / 2, usable * progress))
            ZStack(alignment: .leading) {
                Capsule().fill(rail).frame(height: trackH)
                Capsule().fill(accent).frame(width: x, height: trackH)

                // No `.widgetAccentable()` on the dot: in the system's
                // accented/tinted rendering that puts the dot in a different
                // colour group from the rail it rides, and the two flatten
                // into each other (owner 2026-07-25, "cannot see"). One group,
                // one tint, always visible.
                Circle().fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: x, y: trackH / 2)
            }
            .frame(height: max(dotSize, trackH))
        }
        .frame(height: compact ? 9 : 12)
        .animation(.easeInOut(duration: 0.4), value: progress)
    }
}

struct LeyneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LeyneActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state,
                           isStale: context.isStale)
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
                DynamicIslandExpandedRegion(.center) {
                    // Island copy is always on black chrome — uses the
                    // dark-context wIslandFg/wIslandDim pair, not wFg/wDim
                    // (which are now dark ink, tuned for the light widget +
                    // lock screen surfaces).
                    VStack(alignment: .leading, spacing: 1) {
                        Text("to \(context.attributes.dest)")
                            .font(wSans(12.5, .bold))
                            .foregroundStyle(wIslandFg)
                            .lineLimit(1)
                        Text(context.attributes.stopName)
                            .font(wSans(10.5, .medium))
                            .foregroundStyle(wIslandDim)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.arrived {
                            Text("Now")
                                .font(wMono(22, .heavy))
                                .foregroundStyle(wIslandBlue)
                                .shadow(color: wIslandBlue.opacity(0.5), radius: 4)
                                .lineLimit(1)
                        } else if shouldShowTimer(context.state) {
                            Text(timerInterval: .now...context.state.eta, countsDown: true)
                                .font(wMono(22, .heavy))
                                .foregroundStyle(wIslandBlue)
                                .shadow(color: wIslandBlue.opacity(0.5), radius: 4)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(confPrefix(context.state) + etaText(context.state))
                                    .font(wMono(22, .heavy))
                                    .foregroundStyle(wIslandBlue)
                                    .shadow(color: wIslandBlue.opacity(0.5), radius: 4)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if context.state.etaMinutes > 0 {
                                    Text("min")
                                        .font(wMono(10)).foregroundStyle(wIslandDim)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // .widgetURL here makes the expanded info area tap → Bus view.
                    VStack(alignment: .leading, spacing: 6) {
                        JourneyTrack(progress: journeyProgress(context.state),
                                     arrived: context.state.arrived,
                                     accent: wIslandBlue, rail: Color.white.opacity(0.16))
                            .frame(height: 12)
                        HStack {
                            // "N stops away" when the app pushes a real GPS
                            // stops-away count; otherwise the phase word
                            // ("Approaching" / "Next stop") — never a
                            // fabricated distance. No crowd dots here: the
                            // ContentState contract carries no crowd field
                            // (see file header).
                            Text(footerLeftLabel(context.state))
                                .font(wSans(10.5, .medium))
                                .foregroundStyle(context.state.arrived ? wIslandBlue : wIslandDim)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("Your stop")
                                .font(wSans(10, .medium))
                                .foregroundStyle(wIslandDim)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 2)
                    .widgetURL(busURL(context.attributes))
                }
            } compactLeading: {
                // 22pt square blue chip with the bus NUMBER, not a generic
                // glyph — the identity is the whole point. Paired with the
                // ETA in compactTrailing, the collapsed island answers
                // "which bus, how long" at a glance.
                WIslandChip(no: context.attributes.busNo)
                    .widgetURL(busURL(context.attributes))
            } compactTrailing: {
                // STATIC minute value only — never a `Text(timerInterval:)` here.
                // A self-sizing timer reserves width for its widest value, which
                // balloons the compact island across the whole notch and covers
                // the status-bar clock + battery. The live m:ss countdown lives
                // on the lock screen + expanded views, where there's room.
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(context.state.arrived
                         ? "Now"
                         : confPrefix(context.state) + etaText(context.state))
                        .font(wMono(13, .heavy))
                        .foregroundStyle(wIslandBlue)
                    if !context.state.arrived && context.state.etaMinutes > 0 {
                        Text("min").font(wMono(9)).foregroundStyle(wIslandDim)
                    }
                }
                .widgetURL(busURL(context.attributes))
            } minimal: {
                // The minimal view (multiple Live Activities) is the tiniest
                // notch presentation — just the blue service-number chip, per
                // the shared design spec. The app only ever runs ONE bus Live
                // Activity at a time, so the number alone is unambiguous.
                WIslandChip(no: context.attributes.busNo)
                    .widgetURL(busURL(context.attributes))
            }
            .keylineTint(wIslandBlue)
        }
    }
}

/// Expanded/footer left label — real GPS stops-away when the app pushed one,
/// else the phase word. Never invents a distance.
private func footerLeftLabel(_ s: LeyneActivityAttributes.ContentState) -> String {
    if s.arrived { return "Bus is here" }
    if s.stopsAway == 0 { return "Arriving now" }
    if s.stopsAway > 0 { return "\(s.stopsAway) stop\(s.stopsAway == 1 ? "" : "s") away" }
    return phase(s).label
}

private struct LockScreenView: View {
    let attributes: LeyneActivityAttributes
    let state: LeyneActivityAttributes.ContentState
    /// Past the content's staleDate (the app is suspended and can't push).
    /// The tell stays whisper-quiet per feedback_timely_over_honest: the
    /// LIVE dot just loses its blue fill + glow — no banner, no wording
    /// change.
    var isStale: Bool = false

    /// The system renders Lock Screen / StandBy Live Activities in one of
    /// three modes. In `.accented` and `.vibrant` it IGNORES our colours and
    /// re-derives everything from the view's luminance — so the hand-tuned
    /// light-surface palette (dark ink on near-white) collapses into a flat,
    /// unreadable wash, which is exactly what the owner photographed on
    /// 2026-07-25 ("cannot see"). Outside `.fullColor` we hand the system the
    /// semantic styles it knows how to render instead of fighting it.
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var fullColor: Bool { renderingMode == .fullColor }

    /// Primary ink / accent — the countdown and the LIVE dot.
    private var accentInk: Color { fullColor ? wAccentBlue : .primary }
    /// Body copy.
    private var bodyInk: Color { fullColor ? wDim : .secondary }
    /// Captions — the quietest tier.
    private var captionInk: Color { fullColor ? wFaint : .secondary }

    var body: some View {
        // Header: monogram tile + "Bus <no> · <stop>", LIVE mark trailing.
        // Body: the big countdown with the journey phase beside it. Then the
        // progress track FULL WIDTH, with its two end labels directly
        // underneath it.
        //
        // The track used to share a row with the countdown, which squeezed it
        // into whatever width the numerals left over and stranded "Next stop"
        // / "Your stop" a whole row below the rail they annotate — the labels
        // pointed at nothing (owner 2026-07-25, "string not centered and
        // placed properly"). Track and labels are now one block: the rail
        // spans the card, and each label sits under the end it names.
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fullColor
                              ? AnyShapeStyle(LinearGradient(colors: [wAccentBlue, wIslandBlue],
                                                             startPoint: .topLeading,
                                                             endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.primary))
                    Text("D")
                        .font(wSans(14, .heavy))
                        .foregroundStyle(fullColor ? Color.white : Color.black)
                }
                .frame(width: 26, height: 26)

                Text("Bus \(attributes.busNo) · \(attributes.stopName)")
                    .font(wSans(12.5, .semibold))
                    .foregroundStyle(bodyInk)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Circle().fill(isStale ? captionInk : accentInk)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(wSans(10.5, .semibold))
                        .foregroundStyle(captionInk)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Group {
                        if state.arrived {
                            Text("Now")
                        } else if shouldShowTimer(state) {
                            // Live bus: OS-ticked m:ss countdown, no push
                            // needed — already reads as a duration, so no
                            // separate "min" unit is appended.
                            Text(timerInterval: .now...state.eta, countsDown: true)
                        } else {
                            // Schedule-only: static minute, whisper-quiet "~".
                            Text(confPrefix(state) + etaText(state))
                        }
                    }
                    .font(wMono(32, .heavy))
                    .foregroundStyle(accentInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                    // A self-sizing timer reserves width for its widest value;
                    // fixing it stops the destination text beside it from
                    // jumping left and right as the countdown ticks.
                    .fixedSize(horizontal: shouldShowTimer(state), vertical: false)

                    // The static branch is a bare minute count — always
                    // pair it with its unit (owner has flagged missing
                    // "min" strings repeatedly).
                    if !state.arrived && !shouldShowTimer(state) && state.etaMinutes > 0 {
                        Text("min")
                            .font(wSans(13, .medium))
                            .foregroundStyle(bodyInk)
                    }
                }

                Spacer(minLength: 8)

                Text("to \(attributes.dest)")
                    .font(wSans(12.5, .semibold))
                    .foregroundStyle(bodyInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 5) {
                JourneyTrack(progress: journeyProgress(state), arrived: state.arrived,
                             accent: accentInk,
                             rail: fullColor ? Color.black.opacity(0.08)
                                             : Color.secondary.opacity(0.3))
                    .frame(height: 12)

                HStack {
                    Text(footerLeftLabel(state))
                        .font(wSans(10, .medium))
                        .foregroundStyle(state.arrived ? accentInk : captionInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Your stop")
                        .font(wSans(10, .medium))
                        .foregroundStyle(captionInk)
                }
            }
        }
        .padding(16)
    }
}

@main
struct LeyneWidgetBundle: WidgetBundle {
    var body: some Widget {
        // The widget lineup is exactly ONE widget in ONE size (owner
        // directive, 2026-07-24): the Nearest Stop board, .systemMedium only.
        // The Saved Stop and Favourite Service widget kinds were removed
        // outright — existing placed widgets of those kinds go blank on
        // users' home screens, which is accepted as part of this redesign.
        LeyneNearbyWidget()        // Home Screen — nearest stop, live board (Medium)
        LeyneLiveActivity()        // Lock Screen / Dynamic Island
    }
}
