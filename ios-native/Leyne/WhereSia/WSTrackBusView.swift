// WhereSia — Track bus (screen 7).
//
// Bar title: "Bus N". A tracking card in the Home/Stop card grammar (owner
// spec 2026-07-08): eyebrow row, green Now plate + edge tick while the bus is
// pulling in, seat-dot crowd phrase, the your-stop ETA big on the right with
// numericText-only updates. Below, the route card: a vertical timeline whose
// long ends collapse behind tappable "N earlier/more stops" chips; every other
// stop row pushes that stop's own arrivals. The moving bus is a pinging node
// between stops; MRT-interchange stops are flagged; the user's stop is
// highlighted. CTA: "Alert me 1 stop before".
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

    @State private var serviceRouteData: ServiceRoute?
    @State private var selectedDirIndex = 0
    @State private var busIndex: Int?
    @State private var refreshTick = false
    @State private var showEarlier = false
    @State private var showLater = false

    private var service: Service? { store.servicesFor(stopCode).first { $0.no == serviceNo } }
    private var isAlerted: Bool {
        m.alert(kind: .arrival, busNo: serviceNo, stopCode: stopCode) != nil
    }

    /// The direction currently shown in the Route section below — starts on
    /// whichever direction serves `stopCode` but can be flipped with the
    /// switcher when the service runs both ways (mirrors Android's
    /// SegmentedButton on this same screen, restyled via WSSegmented).
    private var currentDirection: RouteDirection? {
        guard let sr = serviceRouteData, selectedDirIndex < sr.directions.count else { return nil }
        return sr.directions[selectedDirIndex]
    }

    /// The direction that actually serves the tracked stop, regardless of
    /// which one is currently being browsed. Anything describing the REAL bus
    /// being tracked (hero card, live bus marker) is grounded here so
    /// switching to the other direction never misrepresents it.
    private var anchorDirection: RouteDirection? {
        serviceRouteData?.directions.first(where: \.anchorPresent) ?? serviceRouteData?.directions.first
    }

    /// Stop list for whichever direction is currently displayed in the
    /// timeline below.
    private var route: RouteInfo? {
        guard let dir = currentDirection else { return nil }
        return RouteInfo(stops: dir.stops, youIndex: dir.youIndex, busIndex: nil, busCoord: nil)
    }

    /// The live bus marker's stop index — meaningful only against the
    /// direction that actually serves this stop. Nil while the OTHER
    /// direction is being browsed, so a tracked bus is never drawn onto (or
    /// used to grey out stops on) a route it isn't actually running.
    private var displayBusIndex: Int? {
        (currentDirection?.anchorPresent ?? true) ? busIndex : nil
    }

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            liveCard
                .wsEntrance()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    routeCard
                        .wsEntrance(delay: 0.06)
                    Color.clear.frame(height: 16)
                }
            }

            cta
                .wsEntrance(delay: 0.12)
        }
        .wsDetailAdBanner()
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

    // MARK: tracking card
    //
    // Information hierarchy, first glance → last: (1) WHEN the bus reaches
    // your stop — the whole reason this screen is open; (2) which bus, toward
    // where; (3) is it live + how full. Same plate / seat-dot / stacked-ETA
    // grammar as WSDepartureRow so a tapped row grows into a card that reads
    // as the same object (anim spec: preserve spatial continuity). Only the
    // ETA numeral animates (numericText); the seat dot's colour crossfades.

    private var liveCard: some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        let minutes = sec.map { max(1, $0 / 60) }
        let sched = !(service?.monitored ?? true)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                WSIcon(glyph: .busSingle, size: 15, weight: .medium, color: ws.dim)
                Text("Tracking bus")
                    .font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer(minLength: 8)
                if service != nil { WSLiveBadge() }
            }

            HStack(spacing: 13) {
                Text(serviceNo)
                    .font(ws.mono(serviceNo.count > 3 ? 16 : 19, weight: .bold))
                    .foregroundStyle(now ? .white : ws.text)
                    .frame(width: 62, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(now ? ws.now : ws.panel2))
                VStack(alignment: .leading, spacing: 5) {
                    Text(destTitle)
                        .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.text)
                        .lineLimit(2)
                    if let load = service?.load {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(load.wsDotColor)
                                .frame(width: 7, height: 7)
                                .animation(.easeInOut(duration: 0.2), value: load)
                            Text(load.wsSeatPhrase)
                                .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                                .lineLimit(1).allowsTightening(true)
                        }
                    } else {
                        Text("Waiting for the next bus…")
                            .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Group {
                        if now {
                            Text("Now")
                                .font(ws.sans(27, weight: .heavy)).foregroundStyle(ws.text)
                        } else if let minutes {
                            // Scheduled-only ETA carries the whisper "~" —
                            // never a banner (feedback_timely_over_honest).
                            (Text(sched ? "~" : "")
                                .font(ws.sans(19, weight: .semibold)).foregroundStyle(ws.dim)
                             + Text("\(minutes)").font(ws.sans(27, weight: .heavy)).foregroundStyle(ws.text)
                             + Text(" min").font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim))
                        } else {
                            Text("—").font(ws.sans(27, weight: .heavy)).foregroundStyle(ws.faint)
                        }
                    }
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    Text(now ? "At your stop" : "To your stop")
                        .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                }
            }
            .padding(.top, 14)
            // The green edge tick — same arriving mark as the departure
            // rows. Anchored to THIS row so it sits centred beside the
            // service plate; overlaying the whole card centred it against
            // the eyebrow row too and it floated mid-air (owner-reported
            // UI bug 2026-07-09).
            .overlay(alignment: .leading) {
                if now {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ws.now)
                        .frame(width: 3, height: 46)
                        .offset(x: -12)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .animation(.snappy(duration: 0.28), value: minutes)
        .padding(.horizontal, 22).padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardA11y(now: now, minutes: minutes, sched: sched))
    }

    private var destTitle: String {
        if let dest = service?.dest, !dest.isEmpty { return "To \(dest)" }
        let name = anchorDirection?.destinationName ?? ""
        return name.isEmpty ? "Bus \(serviceNo)" : "To \(name)"
    }

    private func cardA11y(now: Bool, minutes: Int?, sched: Bool) -> String {
        var parts = ["Tracking bus \(serviceNo)"]
        if let dest = service?.dest, !dest.isEmpty { parts.append("to \(dest)") }
        if now { parts.append("at your stop now") }
        else if let minutes { parts.append("\(sched ? "around " : "")\(minutes) minutes to your stop") }
        if let load = service?.load { parts.append(load.wsSeatPhrase) }
        return parts.joined(separator: ", ")
    }

    // MARK: route card

    @ViewBuilder private var routeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                WSIcon(glyph: .map, size: 15, weight: .medium, color: ws.dim)
                Text("Route")
                    .font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer(minLength: 8)
                if let r = route, !r.stops.isEmpty {
                    Text("\(r.stops.count) stops")
                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                }
            }

            if let r = route, !r.stops.isEmpty {
                // Loop / single-direction services stay silent here; most
                // services run both ways (Android parity: the toggle sits
                // under this same header on soft_bus_screen.dart).
                if let sr = serviceRouteData, sr.directions.count > 1 {
                    WSSegmented(options: sr.directions.map { "To \(shortDest($0.destinationName))" },
                                selection: $selectedDirIndex)
                        .padding(.top, 14)
                }
                timeline(r)
                    .padding(.top, 14)
            } else {
                // Route still resolving — shimmer skeleton, never a spinner
                // (anim spec), never bare "Loading…" text.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array([150, 190, 120, 170, 140].enumerated()), id: \.offset) { _, w in
                        HStack(spacing: 15) {
                            WSShimmerBar(width: 13, height: 13)
                            WSShimmerBar(width: CGFloat(w), height: 13)
                        }
                    }
                }
                .padding(.top, 18).padding(.bottom, 6)
                .accessibilityLabel("Loading route")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 22).padding(.top, 14)
    }

    // MARK: timeline

    private func timeline(_ r: RouteInfo) -> some View {
        // The live bus marker and "your stop" highlight only mean anything
        // on the direction that actually serves this stop — browsing the
        // OTHER direction shows its full, plain route instead of guessing
        // where a bus that isn't running that way would be (Android
        // parity: dir.anchorPresent gates canMarkBoard / the bus estimate
        // there too).
        let anchorHere = currentDirection?.anchorPresent ?? true
        let you = anchorHere ? min(max(r.youIndex, 0), r.stops.count - 1) : -1
        let baseStart = anchorHere ? (displayBusIndex.map { min($0, you) } ?? max(0, you - 6)) : 0
        let baseEnd = anchorHere ? min(r.stops.count - 1, you + 1) : r.stops.count - 1
        let start = showEarlier ? 0 : baseStart
        let end = showLater ? r.stops.count - 1 : baseEnd
        return VStack(alignment: .leading, spacing: 0) {
            if baseStart > 0 {
                collapseChip(expanded: showEarlier,
                             show: "Show \(baseStart) earlier stop\(baseStart == 1 ? "" : "s") · from \(r.stops.first?.name ?? "")",
                             hide: "Hide earlier stops") {
                    showEarlier.toggle()
                }
            }
            ForEach(start...end, id: \.self) { i in
                stepRow(r, index: i, you: you)
                if displayBusIndex == i && i < end {
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selectedDirIndex)
    }

    private func stepRow(_ r: RouteInfo, index i: Int, you: Int) -> some View {
        let stop = r.stops[i]
        let passed = displayBusIndex.map { i < $0 } ?? false
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
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    push(.busStop(code: stop.code))
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(ws.sans(14.5, weight: .bold))
                                .foregroundStyle(passed ? ws.dim : ws.text)
                                .multilineTextAlignment(.leading)
                            Text(stop.code)
                                .font(ws.sans(12, weight: .medium))
                                .foregroundStyle(ws.dim)
                            if let ic { interchangeFlag("MRT", ic.codes) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WSCompressStyle())
            }
        }
    }

    private func youBody(_ stop: RouteStopLive, ic: (name: String, codes: [String])?) -> some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        return VStack(alignment: .leading, spacing: 4) {
            Text(ic != nil ? "Your stop · MRT interchange" : "Your stop")
                .font(ws.sans(11, weight: .heavy)).tracking(0.4).foregroundStyle(ws.dim)
            Text(stop.name).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
            if let sec {
                Text(now ? "Arriving now" : "~\(max(1, sec / 60)) min")
                    .font(ws.sans(12, weight: .semibold)).foregroundStyle(now ? ws.now : ws.dim)
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            }
            if let ic {
                // The interchange line is a doorway into the MRT context —
                // tapping it opens the station (anim spec: the CC pill is a
                // continuity element between the bus and MRT worlds).
                if let st = MrtGeo.station(forCode: ic.codes.first ?? "") {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        push(.mrtStation(st))
                    } label: {
                        interchangeFlag("Change for", ic.codes)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WSCompressStyle())
                } else {
                    interchangeFlag("Change for", ic.codes)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(now ? ws.nowFill : ws.panel2)
        // Green marks "arriving this minute" only; the resting highlight is
        // the neutral nested surface + blue edge (identity stays blue).
        .overlay(alignment: .leading) { Rectangle().fill(now ? ws.now : ws.accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .padding(.bottom, 14)
    }

    private func interchangeFlag(_ label: String, _ codes: [String]) -> some View {
        HStack(spacing: 7) {
            WSIcon(glyph: .train, size: 15, color: ws.dim)
            Text(label).font(ws.sans(11, weight: .medium)).foregroundStyle(ws.dim)
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Bus \(serviceNo) is here").font(ws.sans(12, weight: .bold)).foregroundStyle(ws.text)
                // Its live GPS position sits between the two stops above and
                // below this marker; the seat dot + phrase is the onboard
                // crowd — the same idiom as the departure rows.
                HStack(spacing: 6) {
                    Text("Between these stops")
                        .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                    if let load = service?.load {
                        Text("·").font(ws.mono(11)).foregroundStyle(ws.faint)
                        Circle()
                            .fill(load.wsDotColor)
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: load)
                        Text(load.wsSeatPhrase)
                            .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                            .lineLimit(1).allowsTightening(true)
                    }
                }
            }
            .padding(.top, 5).padding(.bottom, 13)
        }
    }

    /// Tappable expand/collapse for the hidden ends of a long route.
    private func collapseChip(expanded: Bool, show: String, hide: String,
                              action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if reduceMotion { action() }
            else { withAnimation(.snappy(duration: 0.3)) { action() } }
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
                    WSIcon(glyph: expanded ? .chevronDown : .chevron, size: 12, color: ws.faint)
                    Text(expanded ? hide : show)
                        .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 6)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WSCompressStyle())
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
        .buttonStyle(WSCompressStyle())
        .padding(.horizontal, 22).padding(.vertical, 12)
        // Arming reads as a small win (.success); cancelling is a quieter
        // acknowledgement (.impact) — matches the app's "quiet by default"
        // haptic restraint (Feedback.swift).
        .sensoryFeedback(trigger: isAlerted) { _, new in new ? .success : .impact(weight: .light) }
    }

    // MARK: data

    private func loadRoute() async {
        guard let sr = await store.serviceRoute(service: serviceNo, stopCode: stopCode) else { return }
        let isFirstLoad = serviceRouteData == nil
        if reduceMotion { serviceRouteData = sr }
        else { withAnimation(.easeOut(duration: 0.35)) { serviceRouteData = sr } }
        // Preserve a manual direction switch across pull-to-refresh reloads —
        // only (re)seat the selection on first load, or if it's gone stale
        // (fewer directions came back than the index needs).
        if isFirstLoad || selectedDirIndex >= sr.directions.count {
            selectedDirIndex = sr.initialIndex
        }
        // The live bus position is plotted only against the direction that
        // actually serves this stop — grounded here regardless of which
        // direction is currently browsed below, so the tracked bus is never
        // drawn onto a route it isn't actually running.
        guard let anchor = sr.directions.first(where: { $0.anchorPresent }) ?? sr.directions.first,
              !anchor.stops.isEmpty else {
            busIndex = nil
            return
        }
        if let coord = await store.liveBus(service: serviceNo, stopCode: stopCode) {
            let you = min(max(anchor.youIndex, 0), anchor.stops.count - 1)
            var best: (idx: Int, d: Double)? = nil
            for i in 0...you {
                let s = anchor.stops[i]
                let d = haversine(coord.latitude, coord.longitude, s.lat, s.lon)
                if best == nil || d < best!.d { best = (i, d) }
            }
            busIndex = best?.idx
        } else {
            busIndex = nil
        }
    }

    /// Keeps direction-switcher labels tight — same truncation as
    /// WSServiceInfoView's segmented control over this same RouteDirection
    /// data, so the two screens' toggles read consistently.
    private func shortDest(_ s: String) -> String {
        let trimmed = s.replacingOccurrences(of: " Int", with: "")
                       .replacingOccurrences(of: " Stn", with: "")
        return trimmed.count > 12 ? String(trimmed.prefix(12)) + "…" : trimmed
    }
}
