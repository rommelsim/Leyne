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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(context.attributes.dest)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(paper)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(context.attributes.stopName.uppercased())
                                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(dim)
                                .lineLimit(1)
                            if context.state.stopsAway >= 0 && !context.state.arrived {
                                Text("· \(context.state.stopsAway) STOP\(context.state.stopsAway == 1 ? "" : "S") AWAY")
                                    .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(dim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(context.state.status.uppercased())
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(context.state.arrived ? green : dim)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 2)
                    .widgetURL(busURL(context.attributes))
                }
            } compactLeading: {
                Text(context.attributes.busNo)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
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
        HStack(spacing: 14) {
            Text(attributes.busNo)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("→ \(attributes.dest.uppercased())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(dim).lineLimit(1)
                Text(state.status)
                    .font(.system(size: state.arrived ? 20 : 16, weight: .semibold))
                    .foregroundStyle(paper)
                HStack(spacing: 6) {
                    Text(attributes.stopName)
                        .font(.system(size: 11)).foregroundStyle(dim).lineLimit(1)
                    if state.stopsAway >= 0 && !state.arrived {
                        Text("· \(state.stopsAway) stop\(state.stopsAway == 1 ? "" : "s") away")
                            .font(.system(size: 11)).foregroundStyle(dim)
                    }
                }
            }
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(confPrefix(state) + etaText(state))
                    .font(.system(size: state.arrived ? 22 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(state.arrived ? green : paper)
                    .contentTransition(.numericText(countsDown: true))
                if !state.arrived && state.etaMinutes > 0 {
                    Text("min")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(dim)
                }
            }
        }
        .padding(16)
    }
}

@main
struct LeyneWidgetBundle: WidgetBundle {
    var body: some Widget {
        LeyneStopWidget()        // Home Screen
        LeyneLiveActivity()      // Lock Screen / Dynamic Island
    }
}
