// Real iOS Live Activity — lock screen + Dynamic Island.
// Self-contained (the widget extension can't import the app module).

import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

// Palette — matches the app's Theme (lib/theme.dart). Kept inline since
// the widget extension can't import the app module. Each token is a
// dynamic UIColor so the Live Activity follows the system color scheme.
private func dyn(dark: UIColor, light: UIColor) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}
// V2 "Soft" palette — mirrors Lyne/Theme.swift (Theme.dark / .light).
// dim alpha nudged to 0.60 to match the app and stay legible on-glass.
private let ink = dyn(
    dark:  UIColor(red: 0x15/255, green: 0x20/255, blue: 0x1C/255, alpha: 1),
    light: UIColor(red: 0xF4/255, green: 0xEF/255, blue: 0xE7/255, alpha: 1))
private let paper = dyn(
    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 1),
    light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 1))
private let green = dyn(
    dark:  UIColor(red: 0x8E/255, green: 0xE6/255, blue: 0xC0/255, alpha: 1),
    light: UIColor(red: 0x2D/255, green: 0x7A/255, blue: 0x5A/255, alpha: 1))
private let dim = dyn(
    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 0.60),
    light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 0.60))

private func etaText(_ s: LeyneActivityAttributes.ContentState) -> String {
    s.arrived ? "Now" : (s.etaMinutes <= 0 ? "Arr" : "\(s.etaMinutes)")
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
// (Previously the Live Activity set no widgetURL, so a tap only foregrounded
// the app wherever it happened to be — it never opened the bus.)
private func busURL(_ a: LeyneActivityAttributes) -> URL? {
    guard !a.stopCode.isEmpty, !a.busNo.isEmpty else { return nil }
    let bus = a.busNo.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed) ?? a.busNo
    return URL(string: "lyne://bus/\(a.stopCode)/\(bus)")
}

// ─── Journey phase + progress ────────────────────────────────────────
// The mockup's hero is the bus's approach toward your stop, not a bare
// number. Both the phase word and the track position are *derived* from the
// state the app already pushes (GPS-driven `stopsAway`, `etaMinutes`,
// `arrived`) — nothing here is invented, so the visual stays as honest as the
// data behind it.
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
    /// Green = the confident "it's basically here" states; en-route stays neutral.
    var isGreen: Bool { self != .enroute }
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
// A capsule rail with the travelled portion filled green, a bus glyph at the
// bus's position, and your stop as the node at the right end. When the bus
// arrives the glyph lands on the node.
private struct JourneyTrack: View {
    let progress: Double
    let arrived: Bool
    var compact = false

    var body: some View {
        let busR: CGFloat = compact ? 8 : 11
        let h = busR * 2
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(0, w - busR)          // keep the bus glyph inside
            let x = min(usable, max(busR, usable * progress))
            ZStack(alignment: .leading) {
                Capsule().fill(dim.opacity(0.35)).frame(height: 3)
                Capsule().fill(green).frame(width: x, height: 3)

                // Destination node — your stop — at the rail's right end.
                ZStack {
                    Circle().fill(ink)
                    Circle().strokeBorder(green, lineWidth: 2)
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.system(size: busR))
                        .foregroundStyle(green)
                }
                .frame(width: h, height: h)
                .position(x: w - busR, y: h / 2)

                // The bus, travelling left→right toward the node.
                ZStack {
                    Circle().fill(green)
                    Image(systemName: "bus.fill")
                        .font(.system(size: busR * 0.9, weight: .bold))
                        .foregroundStyle(ink)
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
                .activityBackgroundTint(ink)
                .activitySystemActionForegroundColor(paper)
                .widgetURL(busURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.busNo)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(confPrefix(context.state) + etaText(context.state))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(context.state.arrived ? green : paper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !context.state.arrived && context.state.etaMinutes > 0 {
                            Text("min")
                                .font(.system(size: 10)).foregroundStyle(dim)
                        }
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // .widgetURL here makes the expanded info area tap → Bus view.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(phase(context.state).label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(phase(context.state).isGreen ? green : paper)
                            let detail = phaseDetail(context.state)
                            if !detail.isEmpty {
                                Text("· \(detail)")
                                    .font(.system(size: 12)).foregroundStyle(dim).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        HStack(spacing: 10) {
                            Text(context.attributes.stopName)
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(paper)
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
                // Bus glyph (mockup) rather than the number — identity lives in
                // the expanded badge; the compact rail is about "a bus is coming".
                Image(systemName: "bus.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(green)
                    .widgetAccentable()
                    .widgetURL(busURL(context.attributes))
            } compactTrailing: {
                Text(confPrefix(context.state) + etaText(context.state)
                     + (context.state.arrived || context.state.etaMinutes <= 0 ? "" : "m"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(context.state.arrived ? green : paper)
                    .widgetURL(busURL(context.attributes))
            } minimal: {
                Text(context.attributes.busNo)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
                    .widgetAccentable()
                    .widgetURL(busURL(context.attributes))
            }
            .keylineTint(green)
        }
    }
}

private struct LockScreenView: View {
    let attributes: LeyneActivityAttributes
    let state: LeyneActivityAttributes.ContentState

    var body: some View {
        let p = phase(state)
        VStack(alignment: .leading, spacing: 0) {
            // Header — service badge + destination.
            HStack(spacing: 9) {
                Text(attributes.busNo)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(minWidth: 34, minHeight: 24)
                    .background(green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Towards \(attributes.dest)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dim).lineLimit(1)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 10)

            // Phase word — the at-a-glance state. Tinted on the confident
            // "here / approaching" states, neutral while still en-route.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(p.label)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(p.isGreen ? green : paper)
                    .widgetAccentable(p.isGreen)
                if !state.monitored && !state.arrived {
                    // Whisper-quiet scheduled tell — see feedback_timely_over_honest.
                    Text("~").font(.system(size: 16, weight: .semibold)).foregroundStyle(dim)
                }
                Spacer(minLength: 0)
            }

            let detail = phaseDetail(state)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(p == .enroute ? dim : green)
                    .padding(.top, 2)
            }

            Spacer(minLength: 10)

            // Bottom — your stop + the approach track.
            HStack(spacing: 12) {
                Text(attributes.stopName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(paper).lineLimit(1)
                    .layoutPriority(1)
                JourneyTrack(progress: journeyProgress(state), arrived: state.arrived)
                    .frame(minWidth: 70)
            }
        }
        .padding(16)
    }
}

@main
struct LeyneWidgetBundle: WidgetBundle {
    var body: some Widget {
        LeyneStopWidget()          // Home Screen — pinned stop arrivals
        LeyneNearbyWidget()        // Home Screen — closest stops
        LeyneFavServiceWidget()    // Home Screen — favourited service
        LeyneLiveActivity()        // Lock Screen / Dynamic Island
    }
}
