// Real iOS Live Activity — lock screen + Dynamic Island.
// Self-contained (the widget extension can't import the app module).

import ActivityKit
import WidgetKit
import SwiftUI

private let ink   = Color(red: 0x14/255, green: 0x11/255, blue: 0x0f/255)
private let paper = Color(red: 0xF2/255, green: 0xEF/255, blue: 0xE8/255)
private let green = Color(red: 0x5B/255, green: 0xC0/255, blue: 0x7A/255)
private let dim   = Color(red: 0x9a/255, green: 0x94/255, blue: 0x8a/255)

private func etaText(_ s: LyneActivityAttributes.ContentState) -> String {
    s.arrived ? "Now" : (s.etaMinutes <= 0 ? "Arr" : "\(s.etaMinutes)")
}

struct LyneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyneActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ink)
                .activitySystemActionForegroundColor(paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.busNo)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(green, in: RoundedRectangle(cornerRadius: 8))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(etaText(context.state))
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .foregroundStyle(context.state.arrived ? green : paper)
                        if !context.state.arrived && context.state.etaMinutes > 0 {
                            Text("min").font(.system(size: 11)).foregroundStyle(dim)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(context.attributes.dest)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(paper)
                            .lineLimit(1)
                        HStack {
                            Text(context.attributes.stopName.uppercased())
                                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(dim)
                            if context.state.stopsAway >= 0 && !context.state.arrived {
                                Text("· \(context.state.stopsAway) STOP\(context.state.stopsAway == 1 ? "" : "S") AWAY")
                                    .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(dim)
                            }
                            Spacer()
                            Text(context.state.status.uppercased())
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(context.state.arrived ? green : dim)
                        }
                    }
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
    let attributes: LyneActivityAttributes
    let state: LyneActivityAttributes.ContentState

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
struct LyneWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyneStopWidget()        // Home Screen
        LyneLiveActivity()      // Lock Screen / Dynamic Island
    }
}
