// WhereSia — Track bus (screen 7).
//
// Bar title: "Bus N". A live card (route, destination, "reaching your stop in
// N min", crowd) over a vertical route timeline. Long routes collapse with
// tappable "N earlier/more stops" chips that expand/collapse the full route;
// every other stop row pushes that stop's own arrivals. The moving bus is a
// pulsing node between stops; MRT-interchange stops are flagged; the user's
// stop is highlighted. CTA: "Alert me 1 stop before".
//
// Position is APPROXIMATE — LTA gives coords + ETAs for the next buses only, so
// per-stop minute times are not invented (only the your-stop ETA is real).

import SwiftUI

struct WSTrackBusView: View {
    let stopCode: String
    let serviceNo: String
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: RouteInfo?
    @State private var busIndex: Int?
    @State private var refreshTick = false
    @State private var showEarlier = false
    @State private var showLater = false

    private var service: Service? { store.servicesFor(stopCode).first { $0.no == serviceNo } }
    private var isAlerted: Bool {
        m.alert(kind: .arrival, busNo: serviceNo, stopCode: stopCode) != nil
    }

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            liveCard
                .wsEntrance()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let r = route, !r.stops.isEmpty {
                        WSSectionHeader(label: "Route", meta: "\(r.stops.count) stops")
                            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
                    }
                    timeline
                }
            }

            cta
                .wsEntrance(delay: 0.08)
        }
        .background(ws.bg)
        // The bar names the bus itself — "TRACK BUS" told the user nothing.
        .wsHeaderBar(eyebrow: "Track bus", title: "Bus \(serviceNo)",
                     collapsed: true, onBack: onBack) {
            WSHairButton(glyph: .info) {
                push(.serviceInfo(no: serviceNo, fromStop: stopCode))
            }
        }
        .onAppear {
            store.ensureArrivals(stop: stopCode, force: true)
        }
        // Keep the tracked stop live while open (freshness-gated inside), and
        // refetch immediately on return from background — the tick loop was
        // paused, so the card would otherwise show minutes-old data until a
        // pull-to-refresh (owner-reported).
        .onChange(of: m.tick) { _, _ in store.ensureArrivals(stop: stopCode) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.ensureArrivals(stop: stopCode, force: true) }
        }
        .task {
            // .task (not a fire-and-forget Task in onAppear) so the route
            // fetch cancels automatically if the user pops before it resolves.
            await loadRoute()
        }
        .refreshable {
            await store.refreshArrivals(stop: stopCode)
            await loadRoute()
            refreshTick.toggle()
        }
        .sensoryFeedback(.success, trigger: refreshTick)
    }

    // MARK: live card
    //
    // Information hierarchy, first glance → last: (1) WHEN the bus reaches
    // your stop — the hero numerals, the whole reason this screen is open;
    // (2) which bus, toward where; (3) is it live + how full. Rendered on
    // real glass chrome (owner redesign, 2026-07-02).

    private var liveCard: some View {
        let eta = service.map { fmtETA(wsLiveETASec($0)) }
        let arriving = eta?.big == "Arr"
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    RouteTile(text: serviceNo, size: .large)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TOWARD").font(ws.sans(9.5, weight: .heavy)).tracking(1.2).foregroundStyle(ws.dim)
                        Text(service?.dest ?? destName)
                            .font(ws.sans(15.5, weight: .heavy)).foregroundStyle(ws.text)
                            .lineLimit(2)
                    }
                }
                HStack(spacing: 7) {
                    if let load = service?.load {
                        WSLiveBadge()
                        Text("·").font(ws.mono(10)).foregroundStyle(ws.faint)
                        CrowdGauge(fraction: load.wsFraction, width: 26)
                        Text(load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                    } else {
                        Text("Waiting for the next bus…")
                            .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim)
                    }
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 3) {
                if let eta {
                    Text(eta.big)
                        .font(ws.mono(arriving ? 30 : 40, weight: .bold))
                        .foregroundStyle(ws.text)
                        .contentTransition(.numericText(countsDown: true))
                    Text(arriving ? "AT YOUR STOP" : "MIN TO YOUR STOP")
                        .font(ws.mono(9)).tracking(0.7).foregroundStyle(ws.dim)
                } else {
                    Text("—").font(ws.mono(34, weight: .bold)).foregroundStyle(ws.faint)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: eta?.big)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 14 matches the app's card radius family (WSCard 14, search 14,
        // interchange 13). The previous 20 curved the bottom-left corner so
        // far in that "ROUTE" below read as misaligned against the card's
        // edge (owner-reported optical bug) — the margins were identical.
        .wsGlassChrome(cornerRadius: 14, tint: ws.panel)
        .shadow(color: .black.opacity(ws.isDark ? 0.3 : 0.08), radius: 12, x: 0, y: 5)
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var destName: String {
        route?.stops.last?.name ?? "—"
    }

    // MARK: timeline

    @ViewBuilder private var timeline: some View {
        if let r = route, !r.stops.isEmpty {
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            let baseStart = busIndex.map { min($0, you) } ?? max(0, you - 6)
            let baseEnd = min(r.stops.count - 1, you + 1)
            let start = showEarlier ? 0 : baseStart
            let end = showLater ? r.stops.count - 1 : baseEnd
            VStack(alignment: .leading, spacing: 0) {
                if baseStart > 0 {
                    collapseChip(expanded: showEarlier,
                                 show: "Show \(baseStart) earlier stop\(baseStart == 1 ? "" : "s") · from \(r.stops.first?.name ?? "")",
                                 hide: "Hide earlier stops") {
                        showEarlier.toggle()
                    }
                }
                ForEach(start...end, id: \.self) { i in
                    stepRow(r, index: i, you: you)
                    if busIndex == i && i < end {
                        vehicleRow(r)
                    }
                }
                let more = (r.stops.count - 1) - baseEnd
                if more > 0 {
                    collapseChip(expanded: showLater,
                                 show: "Show \(more) more stop\(more == 1 ? "" : "s") to \(r.stops.last?.name ?? "")",
                                 hide: "Hide later stops") {
                        showLater.toggle()
                    }
                }
            }
            .padding(.horizontal, 22)
        } else {
            Text("Loading route…")
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                .padding(.horizontal, 22).padding(.top, 20)
        }
    }

    private func stepRow(_ r: RouteInfo, index i: Int, you: Int) -> some View {
        let stop = r.stops[i]
        let passed = busIndex.map { i < $0 } ?? false
        let isYou = i == you
        let ic = wsInterchange(forStopName: stop.name)
        return HStack(alignment: .top, spacing: 15) {
            // rail
            VStack(spacing: 0) {
                Circle()
                    .fill(isYou ? ws.accent : (passed ? ws.faint : ws.bg))
                    .frame(width: isYou ? 15 : 13, height: isYou ? 15 : 13)
                    .overlay(Circle().stroke(isYou ? ws.accent : (passed ? ws.text : ws.faint), lineWidth: isYou ? 3 : 2.5))
                    // Ping the user's stop — the one node that matters most.
                    .background { if isYou { WSPing(cornerRadius: 999) } }
                    .padding(.top, 4)
                Rectangle().fill(passed ? ws.text : ws.rule).frame(width: 3)
            }
            .frame(width: 24)

            if isYou {
                youBody(stop, ic: ic)
            } else {
                // Any other stop on the route opens that stop's own arrivals.
                Button { push(.busStop(code: stop.code)) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(ws.sans(14.5, weight: .bold))
                                .foregroundStyle(passed ? ws.dim : ws.text)
                                .multilineTextAlignment(.leading)
                            Text(stop.code)
                                .font(ws.mono(10.5)).tracking(0.3)
                                .foregroundStyle(ws.dim)
                            if let ic { interchangeFlag("MRT", ic.codes) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func youBody(_ stop: RouteStopLive, ic: (name: String, codes: [String])?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ic != nil ? "YOUR STOP · MRT INTERCHANGE" : "YOUR STOP")
                .font(ws.sans(9.5, weight: .heavy)).tracking(1.2).foregroundStyle(ws.dim)
            Text(stop.name).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
            if let eta = service.map({ fmtETA(wsLiveETASec($0)) }) {
                Text(eta.big == "Arr" ? "Arriving now" : "~\(eta.big) min")
                    .font(ws.mono(11.5)).foregroundStyle(ws.dim)
            }
            if let ic { interchangeFlag("CHANGE FOR", ic.codes) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
        .overlay(alignment: .leading) { Rectangle().fill(ws.accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.bottom, 14)
    }

    private func interchangeFlag(_ label: String, _ codes: [String]) -> some View {
        HStack(spacing: 7) {
            WSIcon(glyph: .train, size: 15, color: ws.dim)
            Text(label).font(ws.mono(9)).tracking(0.5).foregroundStyle(ws.dim)
            ForEach(codes.prefix(3), id: \.self) { LineBullet(code: $0) }
        }
        .padding(.top, 2)
    }

    private func vehicleRow(_ r: RouteInfo) -> some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(spacing: 0) {
                Text(serviceNo)
                    .font(ws.mono(12, weight: .bold)).foregroundStyle(ws.text)
                    .frame(width: 34, height: 30)
                    .background(ws.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ws.accent, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    // Radar ping behind the tile — draws the eye to the bus's
                    // live position. Added after the clip so the ring emanates.
                    .background(WSPing(cornerRadius: 8))
                Rectangle().fill(ws.rule).frame(width: 3)
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bus en route").font(ws.sans(12, weight: .bold)).foregroundStyle(ws.text)
                Text("between stops · \(service?.load.wsWord.lowercased() ?? "on the way")")
                    .font(ws.mono(11)).foregroundStyle(ws.dim)
            }
            .padding(.top, 5).padding(.bottom, 13)
        }
    }

    /// Tappable expand/collapse for the hidden ends of a long route.
    private func collapseChip(expanded: Bool, show: String, hide: String,
                              action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion { action() }
            else { withAnimation(.snappy(duration: 0.25)) { action() } }
        } label: {
            HStack(alignment: .top, spacing: 15) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 2)
                        .overlay(
                            Rectangle().fill(ws.faint)
                                .frame(width: 2)
                                .mask(VStack(spacing: 6) { ForEach(0..<6, id: \.self) { _ in
                                    Rectangle().frame(height: 3) } })
                        )
                }
                .frame(width: 24)
                HStack(spacing: 8) {
                    WSIcon(glyph: .chevronDown, size: 14, color: ws.dim)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Text(expanded ? hide : show)
                        .font(ws.mono(11)).foregroundStyle(ws.dim)
                        .underline()
                }
                .padding(.vertical, 6)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    // MARK: CTA

    private var cta: some View {
        Button {
            let name = store.stopName(stopCode)
            m.toggleArrivalAlert(busNo: serviceNo, stopCode: stopCode,
                                 stopName: name, dest: service?.dest ?? "")
        } label: {
            HStack(spacing: 9) {
                WSIcon(glyph: isAlerted ? .bellRing : .alerts, size: 19, color: ws.bg)
                Text(isAlerted ? "Alert set · tap to cancel" : "Alert me 1 stop before")
                    .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.bg)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(ws.text)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.vertical, 12)
        // Arming reads as a small win (.success); cancelling is a quieter
        // acknowledgement (.impact) — matches the app's "quiet by default"
        // haptic restraint (Feedback.swift).
        .sensoryFeedback(trigger: isAlerted) { _, new in new ? .success : .impact(weight: .light) }
    }

    // MARK: data

    private func loadRoute() async {
        guard let r = await store.route(service: serviceNo, stopCode: stopCode) else { return }
        if reduceMotion { route = r }
        else { withAnimation(.easeOut(duration: 0.35)) { route = r } }
        // Approximate the bus's position from its live coord → nearest upstream stop.
        if let coord = await store.liveBus(service: serviceNo, stopCode: stopCode) {
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            var best: (idx: Int, d: Double)? = nil
            for i in 0...you {
                let s = r.stops[i]
                let d = haversine(coord.latitude, coord.longitude, s.lat, s.lon)
                if best == nil || d < best!.d { best = (i, d) }
            }
            busIndex = best?.idx
        } else {
            busIndex = nil
        }
    }
}
