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
    /// Per-stop time label, e.g. "8:18 AM" / "ETA 8:20 AM". nil = unknown
    /// (passed stops: we never recorded when the bus went by, so we show
    /// none rather than invent one).
    var time: String? = nil
}

/// True when a bus stop sits at an MRT/LRT station. There's no bus-stop→station
/// dataset from LTA, but SG stop descriptions tag these with the "Stn" token
/// (e.g. "Bishan Stn", "Opp Serangoon Stn", "Bef Bugis Stn Exit C"), so the
/// name is the signal. Word-boundaried so ordinary names ("Stadium", "Newton")
/// don't false-positive; an explicit "MRT"/"LRT" also qualifies. Conservative
/// by design — it surfaces a station only when we're confident, never invents
/// one ("if have", not "always").
func stopServesMRT(_ name: String) -> Bool {
    let lower = name.lowercased()
    if lower.contains("mrt") || lower.contains("lrt") { return true }
    return lower.range(of: #"\bstn\b"#, options: .regularExpression) != nil
}

struct RouteTimeline: View {
    let t: Theme
    let svc: String
    let stops: [RouteStop]
    @Binding var alightId: String?
    /// When false the list is a read-only viewer: no "tap to be alerted" hint,
    /// no per-row tap or chevron. (Alight selection is disabled for now.)
    var selectable: Bool = true
    /// When true, drop the inner card chrome (padding + surface) so the list
    /// sits flush with its parent's margin — e.g. inside the glass route card.
    var embedded: Bool = false

    // Beyond this many stops the leading run is collapsed behind a "show
    // earlier stops" node so a long route stays scannable. Kept in sync with
    // the Android RouteTimeline (`maxVisible`).
    private static let maxVisible = 8

    // Whether the collapsed leading stops are revealed. Long routes start
    // collapsed so the boarding/upcoming area is what you see first.
    @State private var expanded = false

    /// Whether the whole route list is shown. The "FULL ROUTE" header toggles
    /// it so the (often long) bus→terminus list can be folded away.
    @State private var routeShown = true

    /// Whether the stops past your stop (→ terminus) are revealed. Long routes
    /// start with the tail folded so the card opens on bus → your stop.
    @State private var tailExpanded = false

    /// Focal stop: keep both the live bus and the boarding stop on screen, so
    /// collapse never folds the bus away. Use the earlier of the two; fall back
    /// to whichever exists, else the start.
    private var focalIdx: Int {
        let here = stops.firstIndex { $0.state == .here }
        let board = stops.firstIndex { $0.state == .board }
        if let h = here, let b = board { return min(h, b) }
        return here ?? board ?? 0
    }

    /// First stop kept visible when collapsed — 2 stops of lead-in before the
    /// focal stop. Everything before it folds into the collapse node.
    private var keepFrom: Int { min(max(0, focalIdx - 2), stops.count) }

    private var canCollapse: Bool {
        stops.count > Self.maxVisible && keepFrom >= 2
    }

    private var startIdx: Int { (canCollapse && !expanded) ? keepFrom : 0 }

    /// The furthest "important" stop to keep visible by default — your boarding
    /// stop, or the alight target if it's further along (else the bus). Stops
    /// beyond it fold into a trailing node so a long route doesn't scroll forever.
    private var tailAnchorIdx: Int {
        let board = stops.firstIndex { $0.state == .board }
        let here = stops.firstIndex { $0.state == .here }
        let alight = alightId.flatMap { id in stops.firstIndex { $0.id == id } }
        return max(board ?? here ?? -1, alight ?? -1)
    }
    /// Keep two stops of lead-out past the anchor, then collapse to the terminus.
    private var tailKeepTo: Int {
        guard tailAnchorIdx >= 0 else { return stops.count - 1 }
        return min(stops.count - 1, tailAnchorIdx + 2)
    }
    private var canCollapseTail: Bool {
        tailAnchorIdx >= 0 && (stops.count - 1 - tailKeepTo) >= 2
    }
    private var effectiveEndIdx: Int {
        (canCollapseTail && !tailExpanded) ? tailKeepTo : stops.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header — collapse / expand the whole route list.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { routeShown.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("FULL ROUTE")
                        .font(t.mono(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(t.dim)
                    Text("· \(stops.count)")
                        .font(t.mono(10, weight: .semibold))
                        .foregroundStyle(t.faint)
                    Spacer()
                    Image(systemName: routeShown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, routeShown ? 8 : 0)
            .accessibilityLabel(routeShown ? "Hide full route" : "Show full route, \(stops.count) stops")

            if routeShown {
                if selectable && stops.contains(where: { $0.state == .next }) {
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
                    ForEach(Array(stops.enumerated())
                                .filter { $0.offset >= startIdx && $0.offset <= effectiveEndIdx },
                            id: \.element.id) { idx, stop in
                        routeRow(stop: stop,
                                 isFirst: !canCollapse && idx == startIdx,
                                 isLast: idx == stops.count - 1)
                    }
                    // The long tail past your stop folds away, so the card opens on
                    // the part you care about (bus → your stop), not a long scroll.
                    if canCollapseTail {
                        tailCollapseNode(hiddenCount: stops.count - 1 - tailKeepTo,
                                         terminus: stops.last?.name ?? "the end")
                    }
                }
            }
        }
        .padding(embedded ? 0 : 16)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.surface)
            }
        }
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

    /// Trailing counterpart to `collapseNode` — folds the stops between your
    /// stop and the terminus. The connector enters from the top; nothing below.
    @ViewBuilder
    private func tailCollapseNode(hiddenCount: Int, terminus: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { tailExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    // Connector only while collapsed; when expanded the terminus
                    // above is the line's end, so this is a plain "hide" control.
                    if !tailExpanded {
                        VStack(spacing: 0) {
                            Rectangle().fill(t.line).frame(width: 2)
                            Rectangle().fill(Color.clear).frame(width: 2)
                        }
                    }
                    Image(systemName: tailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.dim)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(t.surface))
                }
                .frame(width: 24)

                Text(tailExpanded
                     ? "Hide later stops"
                     : "Show \(hiddenCount) more stop\(hiddenCount == 1 ? "" : "s") to \(terminus)")
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.dim)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
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
                        // Top half: green if the bus has reached this stop.
                        Rectangle()
                            .fill(connectorColor(for: resolved))
                            .frame(width: 2)
                            .opacity(isFirst ? 0 : 1)
                        // Bottom half: the bus hasn't travelled past its own
                        // stop yet, so the green trail ends *at* the bus — this
                        // half greys out, giving one continuous green run from
                        // the origin to the bus and grey all the way after.
                        Rectangle()
                            .fill(BusProgress.lowerConnectorIsGreen(resolved) ? t.soon : t.line)
                            .frame(width: 2)
                            .opacity(isLast ? 0 : 1)
                    }
                    dotView(state: resolved)
                }
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stop.name)
                            .font(t.sans(14, weight: resolved == .past ? .regular : .medium))
                            .foregroundStyle(resolved == .past ? t.faint : t.fg)
                        if stopServesMRT(stop.name) { mrtBadge }
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

                Spacer(minLength: 8)
                if let time = stop.time {
                    Text(time)
                        .font(t.mono(12, weight: resolved == .next ? .regular : .semibold))
                        .foregroundStyle(timeColor(resolved))
                        .lineLimit(1)
                        .padding(.top, 1)
                }
                if selectable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.faint)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUpcoming || !selectable)
    }

    @ViewBuilder
    private func dotView(state: RouteStopState) -> some View {
        switch state {
        case .past:
            // Traversed — a completed green check.
            ZStack {
                Circle().fill(t.soon).frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(t.contrastFg)
            }
        case .here:
            // The bus, right now — green with a bus glyph.
            ZStack {
                Circle().fill(t.soon.opacity(0.25)).frame(width: 22, height: 22)
                Circle().fill(t.soon).frame(width: 18, height: 18)
                Image(systemName: "bus.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.contrastFg)
            }
        case .board:
            // Your stop — a green ring.
            ZStack {
                Circle().fill(t.soon.opacity(0.18)).frame(width: 18, height: 18)
                Circle().strokeBorder(t.soon, lineWidth: 2.5).frame(width: 13, height: 13)
                    .background(Circle().fill(t.surface))
            }
        case .alight:
            ZStack {
                Circle().fill(t.soon.opacity(0.25)).frame(width: 18, height: 18)
                Circle().fill(t.soon).frame(width: 10, height: 10)
            }
        case .next:
            Circle()
                .stroke(t.dim, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .background(Circle().fill(t.surface))
        }
    }

    private func connectorColor(for state: RouteStopState) -> Color {
        // Green marks track the bus has covered. Only stops the bus has reached
        // (passed, or its current stop) are green; your boarding/alight stop is
        // ahead of the bus, so its connector stays grey — no isolated green
        // segment detached from the bus's trail.
        BusProgress.connectorIsGreen(state) ? t.soon : t.line
    }

    private func timeColor(_ state: RouteStopState) -> Color {
        switch state {
        case .past:  return t.faint
        case .here:  return t.soon
        default:     return t.dim
        }
    }

    /// Subtle MRT-station marker — a tram glyph + "MRT" chip. Monochrome
    /// (t.dim on t.surfaceHi) so it reads as a neutral wayfinding attribute,
    /// not a live signal (green stays reserved for proximity/arrival).
    private var mrtBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "tram.fill")
                .font(.system(size: 8.5, weight: .bold))
            Text("MRT")
                .font(t.mono(8, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(t.dim)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(t.surfaceHi, in: Capsule())
        .accessibilityLabel("MRT station")
    }

    @ViewBuilder
    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(t.mono(9, weight: .semibold))
            .tracking(1)
            .foregroundStyle(filled ? t.contrastFg : t.soon)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                filled ? AnyShapeStyle(t.soon) : AnyShapeStyle(t.soonBg),
                in: Capsule()
            )
            .overlay(Capsule().stroke(filled ? Color.clear : t.soon.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Route progress (compact horizontal summary)

/// A few stops around the bus → your stop, laid out horizontally with the
/// line green up to the bus and grey after. Driven by the same estimated bus
/// position as the map pin (so it's honest about being an estimate, not a
/// fabricated GPS-on-route fix). Sits above the FULL ROUTE list.
struct RouteProgressBar: View {
    let t: Theme
    let nodes: [RouteStop]
    let remaining: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ROUTE PROGRESS")
                    .font(t.mono(10, weight: .semibold)).tracking(1)
                    .foregroundStyle(t.dim)
                Spacer()
                if let r = remaining {
                    Text(r == 0 ? "Arriving" : "\(r) stop\(r == 1 ? "" : "s") remaining")
                        .font(t.sans(12, weight: .semibold))
                        .foregroundStyle(t.soon)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { i, n in
                    VStack(spacing: 6) {
                        ZStack {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(i == 0 ? Color.clear : segColor(nodes[i - 1].state))
                                    .frame(height: 2)
                                Rectangle()
                                    .fill(i == nodes.count - 1 ? Color.clear : segColor(n.state))
                                    .frame(height: 2)
                            }
                            dot(n.state)
                        }
                        .frame(height: 24)
                        Text(n.name)
                            .font(t.sans(10, weight: n.state == .next ? .regular : .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(n.state == .next ? t.dim : t.fg)
                        chip(for: n.state)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func segColor(_ s: RouteStopState) -> Color {
        (s == .past || s == .here) ? t.soon : t.line
    }

    @ViewBuilder private func dot(_ s: RouteStopState) -> some View {
        switch s {
        case .past:
            ZStack {
                Circle().fill(t.soon).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.contrastFg)
            }
        case .here:
            ZStack {
                Circle().fill(t.soon).frame(width: 24, height: 24)
                Image(systemName: "bus.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(t.contrastFg)
            }
        case .board, .alight:
            Circle().strokeBorder(t.soon, lineWidth: 2.5).frame(width: 20, height: 20)
                .background(Circle().fill(t.surface))
        case .next:
            Circle().strokeBorder(t.dim, lineWidth: 2).frame(width: 18, height: 18)
                .background(Circle().fill(t.surface))
        }
    }

    @ViewBuilder private func chip(for s: RouteStopState) -> some View {
        switch s {
        case .here:  tag("Bus is here")
        case .board: tag("Your stop")
        default:     EmptyView()
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(t.sans(9.5, weight: .semibold))
            .foregroundStyle(t.soon)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(t.soonBg, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
