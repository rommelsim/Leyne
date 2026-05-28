// RouteTimeline — vertical step list of stops along a tracked bus's
// route. Each row has a connector + dot + label, with per-row state:
//   past   — bus has passed; dot muted, connector faint
//   here   — bus's current location; filled dot with halo, "BUS HERE NOW"
//   board  — user's boarding stop; filled dot with halo, "BOARD" chip
//   next   — upcoming; hollow dot, ETA clock time on right, tap to alight
//   alight — user-selected alight target (upcoming); filled accent + 🔔 chip
//
// Tap behaviour: tapping an upcoming row toggles the alight selection
// (one stop max). The parent owns `alightId` so it can persist across
// re-renders and schedule a real alight notification.

import SwiftUI

enum RouteStopState {
    case past, here, board, next, alight
}

struct RouteStop: Identifiable, Equatable {
    let id: String        // stop code
    let name: String
    let state: RouteStopState
    /// Minutes from now until bus arrives at this stop (for `.next`/`.alight`).
    let etaMin: Int?
}

struct RouteTimeline: View {
    let t: Theme
    let svc: String
    let stops: [RouteStop]
    @Binding var alightId: String?
    /// Reference instant used to format clock-time ETAs. Pass current
    /// `Date()` — kept as a parameter so previews can pin the clock.
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("ROUTE · BUS \(svc)")
                    .font(t.mono(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(t.dim)
                Spacer()
                if stops.contains(where: { $0.state == .here }) {
                    let aheadCount = stops.firstIndex(where: { $0.state == .here })
                        .map { stops.count - $0 - 1 } ?? 0
                    Text("\(aheadCount) STOP\(aheadCount == 1 ? "" : "S") AWAY")
                        .font(t.mono(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(t.dim)
                }
            }
            .padding(.bottom, 8)

            if alightId == nil && stops.contains(where: { $0.state == .next }) {
                Text("Tap a stop to be alerted when arriving.")
                    .font(t.sans(12))
                    .foregroundStyle(t.dim)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                    routeRow(stop: stop,
                             isFirst: idx == 0,
                             isLast: idx == stops.count - 1)
                }
            }
        }
        .padding(16)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func routeRow(stop: RouteStop, isFirst: Bool, isLast: Bool) -> some View {
        let isUpcoming = stop.state == .next || stop.state == .alight
        let resolved: RouteStopState = (alightId == stop.id && isUpcoming)
            ? .alight
            : (stop.state == .alight ? .next : stop.state)

        Button {
            if isUpcoming {
                if alightId == stop.id { alightId = nil }
                else { alightId = stop.id }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(connectorColor(for: resolved))
                            .frame(width: 2)
                            .opacity(isFirst ? 0 : 1)
                        Rectangle()
                            .fill(connectorColor(for: resolved))
                            .frame(width: 2)
                            .opacity(isLast ? 0 : 1)
                    }
                    dotView(state: resolved)
                }
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(stop.name)
                            .font(t.sans(14, weight: resolved == .past ? .regular : .medium))
                            .foregroundStyle(resolved == .past ? t.faint : t.fg)
                        Spacer(minLength: 0)
                        if resolved == .next, let m = stop.etaMin {
                            Text(clockETA(m))
                                .font(t.mono(12, weight: .medium))
                                .foregroundStyle(t.dim)
                        }
                    }
                    switch resolved {
                    case .here:
                        chip("BUS HERE NOW", filled: false)
                    case .board:
                        chip("BOARD", filled: true)
                    case .alight:
                        chip("🔔 ALIGHT", filled: true)
                    default:
                        EmptyView()
                    }
                }
                .padding(.bottom, isLast ? 0 : 14)
                .padding(.top, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUpcoming)
    }

    @ViewBuilder
    private func dotView(state: RouteStopState) -> some View {
        switch state {
        case .past:
            Circle().fill(t.faint).frame(width: 8, height: 8)
        case .here, .board, .alight:
            ZStack {
                Circle().fill(t.accent.opacity(0.25)).frame(width: 18, height: 18)
                Circle().fill(t.accent).frame(width: 10, height: 10)
            }
        case .next:
            Circle()
                .stroke(t.dim, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .background(Circle().fill(t.surface))
        }
    }

    private func connectorColor(for state: RouteStopState) -> Color {
        switch state {
        case .past: return t.line
        case .here, .board, .alight: return t.accent.opacity(0.5)
        case .next: return t.line
        }
    }

    @ViewBuilder
    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(t.mono(9, weight: .semibold))
            .tracking(1)
            .foregroundStyle(filled ? t.onAccent : t.accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                filled ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.liveBg),
                in: Capsule()
            )
            .overlay(Capsule().stroke(filled ? Color.clear : t.accent.opacity(0.4), lineWidth: 1))
    }

    private func clockETA(_ mins: Int) -> String {
        let target = now.addingTimeInterval(TimeInterval(mins * 60))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: target)
    }
}
