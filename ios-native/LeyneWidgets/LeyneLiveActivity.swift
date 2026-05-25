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
private let ink = dyn(
    dark:  UIColor(red: 0x0E/255, green: 0x0E/255, blue: 0x0A/255, alpha: 1),
    light: UIColor(red: 0xF7/255, green: 0xF4/255, blue: 0xED/255, alpha: 1))
private let paper = dyn(
    dark:  UIColor(red: 0xEC/255, green: 0xE9/255, blue: 0xE0/255, alpha: 1),
    light: UIColor(red: 0x17/255, green: 0x16/255, blue: 0x12/255, alpha: 1))
private let green = dyn(
    dark:  UIColor(red: 0x5E/255, green: 0xE5/255, blue: 0x97/255, alpha: 1),
    light: UIColor(red: 0x2B/255, green: 0xAA/255, blue: 0x67/255, alpha: 1))
private let dim = dyn(
    dark:  UIColor(red: 0xEC/255, green: 0xE9/255, blue: 0xE0/255, alpha: 0.52),
    light: UIColor(red: 0x6D/255, green: 0x68/255, blue: 0x59/255, alpha: 1))

private func etaText(_ s: LeyneActivityAttributes.ContentState) -> String {
    s.arrived ? "Now" : (s.etaMinutes <= 0 ? "Arr" : "\(s.etaMinutes)")
}

struct LeyneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LeyneActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ink)
                .activitySystemActionForegroundColor(paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.busNo)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(green, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(etaText(context.state))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(context.state.arrived ? green : paper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !context.state.arrived && context.state.etaMinutes > 0 {
                            Text("min").font(.system(size: 10)).foregroundStyle(dim)
                        }
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
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
                }
            } compactLeading: {
                Text(context.attributes.busNo)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
            } compactTrailing: {
                Text(etaText(context.state) + (context.state.arrived || context.state.etaMinutes <= 0 ? "" : "m"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(context.state.arrived ? green : paper)
            } minimal: {
                Text(context.attributes.busNo)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
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
                .background(green, in: RoundedRectangle(cornerRadius: 12))

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
                Text(etaText(state))
                    .font(.system(size: state.arrived ? 22 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(state.arrived ? green : paper)
                if !state.arrived && state.etaMinutes > 0 {
                    Text("min").font(.system(size: 11, design: .monospaced)).foregroundStyle(dim)
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
