// RouteTimeline — vertical step list of stops along a tracked bus's
// route. Each row has a connector + dot + label, with per-row state:
//   past   — bus has passed; dot muted, connector faint
//   here   — bus's current location; filled dot with halo, "BUS HERE NOW"
//   board  — user's boarding stop; filled dot with halo, "BOARD" chip
//   next   — upcoming; hollow dot, tap to alight (no per-stop ETA: LTA
//            gives us no per-stop times and a guessed clock would mislead)
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
}

struct RouteTimeline: View {
    let t: Theme
    let svc: String
    let stops: [RouteStop]
    @Binding var alightId: String?

    // Beyond this many stops the leading run is collapsed behind a "show
    // earlier stops" node so a long route stays scannable. Kept in sync with
    // the Android RouteTimeline (`maxVisible`).
    private static let maxVisible = 8

    // Whether the collapsed leading stops are revealed. Long routes start
    // collapsed so the boarding/upcoming area is what you see first.
    @State private var expanded = false

    /// Focal stop: the boarding stop, else the live bus, else the start.
    private var focalIdx: Int {
        if let i = stops.firstIndex(where: { $0.state == .board }) { return i }
        if let i = stops.firstIndex(where: { $0.state == .here }) { return i }
        return 0
    }

    /// First stop kept visible when collapsed — 2 stops of lead-in before the
    /// focal stop. Everything before it folds into the collapse node.
    private var keepFrom: Int { min(max(0, focalIdx - 2), stops.count) }

    private var canCollapse: Bool {
        stops.count > Self.maxVisible && keepFrom >= 2
    }

    private var startIdx: Int { (canCollapse && !expanded) ? keepFrom : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("ROUTE · BUS \(svc)")
                    .font(t.mono(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(t.dim)
                Spacer()
                // No "N STOPS AWAY" badge: it requires the bus's live route
                // position (RouteInfo.busIndex), which is always nil today —
                // DataStore.route hard-codes busIndex/busCoord to nil. A count
                // derived without it would be fabricated. Restore this badge
                // (count of stops between `.here` and the boarding stop) once
                // real live bus coordinates land.
            }
            .padding(.bottom, 8)

            if stops.contains(where: { $0.state == .next }) {
                Text("Tap a stop to be alerted when arriving.")
                    .font(t.sans(12))
                    .foregroundStyle(t.dim)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                // The collapse node sits at the visual top when active; the
                // first rendered stop then keeps its top connector so the line
                // stays unbroken.
                if canCollapse {
                    collapseNode(hiddenCount: keepFrom)
                }
                ForEach(Array(stops.enumerated()).filter { $0.offset >= startIdx },
                        id: \.element.id) { idx, stop in
                    routeRow(stop: stop,
                             isFirst: !canCollapse && idx == startIdx,
                             isLast: idx == stops.count - 1)
                }
            }
        }
        .padding(16)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Expandable node standing in for the collapsed leading stops. Tapping it
    /// toggles the full list. Drawn like a route row (connector + glyph) so it
    /// reads as part of the line, not a detached button.
    @ViewBuilder
    private func collapseNode(hiddenCount: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    VStack(spacing: 0) {
                        // Node is the visual top — no connector above it.
                        Rectangle().fill(Color.clear).frame(width: 2)
                        Rectangle().fill(t.line).frame(width: 2)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.dim)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(t.surface))
                }
                .frame(width: 24)

                Text(expanded
                     ? "Hide earlier stops"
                     : "Show \(hiddenCount) earlier stop\(hiddenCount == 1 ? "" : "s")")
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.dim)
                    .padding(.bottom, 14)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    }
                    // Stop code as a dim mono subline (e.g. "42071"). `id` is
                    // the LTA stop code; only show it when it differs from the
                    // displayed name so we never echo a code that *is* the name.
                    if stop.id != stop.name {
                        Text(stop.id)
                            .font(t.mono(10))
                            .foregroundStyle(t.faint)
                    }
                    switch resolved {
                    case .here:
                        chip("BUS HERE NOW", filled: false)
                    case .board:
                        chip("THIS STOP", filled: true)
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
}
