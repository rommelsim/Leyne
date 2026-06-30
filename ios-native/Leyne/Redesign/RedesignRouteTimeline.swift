// Route timeline (iOS) — the vertical rail on the Route screen: passed stops
// (collapsible), the live bus, the rider's stop, downstream stops (collapsible)
// and the terminus. Passed/downstream segments are dotted; the active region
// around the live bus uses a solid primary line.

import SwiftUI

/// Vertical line (solid or dotted) for the rail.
private struct RDVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        return p
    }
}

private struct RDSeg {
    let color: Color
    var dotted: Bool = false
}

struct RDRouteTimeline: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    let route: RouteInfo
    @State private var pulse = false

    var body: some View {
        let stops = route.stops
        let you = max(0, min(route.youIndex, max(0, stops.count - 1)))
        // Show the live-bus marker only when LTA placed it upstream of the
        // rider's stop (the "approaching" case); otherwise omit it honestly.
        let bus: Int? = route.busIndex.flatMap { ($0 >= 0 && $0 < you) ? $0 : nil }
        let firstActive = bus ?? you
        let lastIdx = stops.count - 1
        // Your stop gently pulses once the bus is the very next stop away.
        let oneStopAway = bus.map { you - $0 == 1 } ?? false

        return VStack(spacing: 0) {
            if stops.isEmpty {
                Text("Route stops unavailable")
                    .font(rdFont(13, .medium)).foregroundStyle(t.onVariant)
            } else {
                // 1 — passed stops (collapsible).
                if firstActive > 0 {
                    if !m.routeExpanded {
                        railRow(seg: RDSeg(color: t.outlineVariant, dotted: true),
                                node: AnyView(dot(color: t.surface, border: t.outlineVariant, size: 9)),
                                tap: m.toggleRoute) {
                            HStack(spacing: 4) {
                                RDSym("chevron.down", size: 13, color: t.outline)
                                Text("Passed (\(firstActive))")
                                    .font(rdFont(11.5, .semibold)).foregroundStyle(t.onVariant)
                            }
                        }
                    } else {
                        toggleRow("Hide passed stops", action: m.toggleRoute)
                        ForEach(0..<firstActive, id: \.self) { i in
                            railRow(seg: RDSeg(color: t.outlineVariant),
                                    node: AnyView(dot(color: t.outlineVariant, size: 9)),
                                    tap: { m.openStop(code: stops[i].code) }) {
                                stopLabel(stops[i].name, color: t.onVariant)
                            }
                        }
                    }
                }

                // 2 — live bus.
                if let bus {
                    let approaching = (bus + 1 <= lastIdx) ? stops[bus + 1].name : stops[bus].name
                    railRow(seg: RDSeg(color: t.primary), node: AnyView(busNode), nodeTop: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Bus is here now").font(rdFont(13.5, .heavy)).foregroundStyle(t.primary)
                            Text("Approaching \(approaching)").font(rdFont(11, .medium)).foregroundStyle(t.onVariant)
                        }
                        .padding(.top, 4)
                    }
                }

                // 3 — upcoming stops between the bus and your stop.
                if firstActive < you {
                    ForEach(firstActive..<you, id: \.self) { i in
                        railRow(seg: RDSeg(color: t.primary),
                                node: AnyView(dot(color: t.primary, size: 11)),
                                tap: { m.openStop(code: stops[i].code) }) {
                            HStack {
                                stopLabel(stops[i].name, color: t.onSurface)
                                Spacer()
                                if isInterchange(stops[i].name) {
                                    RDSym("chevron.right", size: 15, color: t.outline)
                                }
                            }
                        }
                    }
                }

                // 4 — your stop.
                railRow(seg: lastIdx > you ? RDSeg(color: t.outlineVariant, dotted: true) : nil,
                        node: AnyView(ring(pulsing: oneStopAway)), nodeTop: 2) {
                    // Subtle highlight, not a filled blue card — the ring node
                    // already marks your stop. A whisper-light primary tint +
                    // bolder name is enough.
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 7) {
                                Text(stops[you].name).font(rdFont(15.5, .heavy))
                                    .foregroundStyle(t.onSurface).lineLimit(1)
                                RDMrtBadgeRow(stopName: stops[you].name, size: 8)
                            }
                            Text("YOUR STOP").font(rdFont(9.5, .bold))
                                .foregroundStyle(t.primary).kerning(0.5)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(t.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // 5 — downstream stops (collapsible) + 6 — terminus.
                let downStart = you + 1
                if downStart <= lastIdx {
                    let downCount = lastIdx - downStart
                    if downCount > 0 {
                        if !m.routeDownExpanded {
                            railRow(seg: RDSeg(color: t.outlineVariant, dotted: true),
                                    node: AnyView(dot(color: t.surface, border: t.outlineVariant, size: 9)),
                                    tap: m.toggleRouteDown) {
                                HStack(spacing: 5) {
                                    Text("\(downCount) more stop\(downCount == 1 ? "" : "s")")
                                        .font(rdFont(12.5, .semibold)).foregroundStyle(t.primary)
                                    RDSym("chevron.down", size: 17, color: t.primary)
                                }
                            }
                        } else {
                            ForEach(downStart..<lastIdx, id: \.self) { i in
                                railRow(seg: RDSeg(color: t.outlineVariant),
                                        node: AnyView(dot(color: t.surface, border: t.outlineVariant, size: 9)),
                                        tap: { m.openStop(code: stops[i].code) }) {
                                    HStack {
                                        stopLabel(stops[i].name, color: t.onVariant)
                                        Spacer()
                                        if isInterchange(stops[i].name) {
                                            RDSym("chevron.right", size: 15, color: t.outline)
                                        }
                                    }
                                }
                            }
                            toggleRow("Hide stops", action: m.toggleRouteDown)
                        }
                    }
                    railRow(seg: nil, node: AnyView(RDSym("mappin.circle.fill", size: 18, color: t.onVariant)),
                            nodeTop: 1, tap: { m.openStop(code: stops[lastIdx].code) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(stops[lastIdx].name).font(rdFont(14, .semibold))
                                    .foregroundStyle(t.onSurface).lineLimit(1)
                                Text("Terminus").font(rdFont(11, .medium)).foregroundStyle(t.outline)
                            }
                            Spacer()
                            RDSym("chevron.right", size: 16, color: t.outline)
                        }
                    }
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) { pulse = true } }
    }

    /// True when the stop sits at an MRT/LRT interchange — the only normal stops
    /// that earn a chevron (the rest stay clean).
    private func isInterchange(_ name: String) -> Bool {
        !rdMrtBadges(forStopNamed: name).isEmpty
    }

    /// Stop name + an MRT line-colour badge when it's an interchange (item 3).
    private func stopLabel(_ name: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Text(name).font(rdFont(14, .medium)).foregroundStyle(color).lineLimit(1)
            RDMrtBadgeRow(stopName: name, size: 8)
        }
    }

    // MARK: rail row

    private func railRow<C: View>(
        seg: RDSeg?,
        node: AnyView,
        nodeTop: CGFloat = 4,
        tap: (() -> Void)? = nil,
        @ViewBuilder content: () -> C
    ) -> some View {
        let row = HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .top) {
                if let seg {
                    RDVLine()
                        .stroke(seg.color, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                              dash: seg.dotted ? [2, 4] : []))
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                }
                node.padding(.top, nodeTop)
            }
            .frame(width: 18)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)
        }
        return Group {
            if let tap {
                Button(action: tap) { row.contentShape(Rectangle()) }.buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private func toggleRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RDSym("chevron.up", size: 17, color: t.primary).frame(width: 18)
                Text(label).font(rdFont(11.5, .semibold)).foregroundStyle(t.primary)
                Spacer()
            }
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: nodes

    private func dot(color: Color, border: Color? = nil, size: CGFloat) -> some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(border ?? t.surface, lineWidth: border != nil ? 2 : 1.5))
    }

    private func ring(pulsing: Bool) -> some View {
        Circle().fill(t.surface).frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(t.primary, lineWidth: 4))
            .overlay(
                Circle().stroke(t.primary, lineWidth: 2)
                    .scaleEffect(pulsing && pulse ? 2.1 : 1)
                    .opacity(pulsing ? (pulse ? 0 : 0.7) : 0)
            )
    }

    private var busNode: some View {
        ZStack {
            Circle().fill(t.primary.opacity(pulse ? 0 : 0.35))
                .frame(width: pulse ? 38 : 28, height: pulse ? 38 : 28)
            Circle().fill(t.primary).frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(t.surface, lineWidth: 3))
                .overlay(RDSym("bus.fill", size: 14, color: .white))
        }
        .frame(width: 34, height: 34)
    }
}
