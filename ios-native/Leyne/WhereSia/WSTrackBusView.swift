// WhereSia — Track bus (screen 7).
//
// Map-first tracking screen (owner 2026-07-11). The live map is the hero: it
// fills from the top down to just above the alert button, with a pull-up sheet
// floating over it. The sheet's header IS the ETA — the thing you grab to pull
// the route up is the same element that tells you when the bus arrives (anim
// spec: spatial continuity). Scrolling up collapses the map behind the rising
// sheet and slides the full "On the way" timeline into view; scrolling back
// down re-expands it. Tapping the map opens a full-screen interactive map with
// the approach stops and a live-info bar.
//
// Position is APPROXIMATE — LTA gives coords + ETAs for the next buses only, so
// per-stop minute times are not invented (only the your-stop ETA is real).
// iOS-only native MapKit (Android deliberately has no bus map — android-no-map).

import SwiftUI
import MapKit
import CoreLocation

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
    @State private var busCoord: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var refreshTick = false

    /// Scroll-driven collapse: how far the sheet has been pulled up. Drives the
    /// hero map's height + fade so the map appears to slide out behind the sheet.
    @State private var scrollY: CGFloat = 0
    /// The full-screen interactive map (tap the hero to open).
    @State private var showFullMap = false

    /// How much of the ETA sheet header overlaps (floats over) the hero map at
    /// rest — the "grab me" peek.
    private let headerPeek: CGFloat = 96

    /// The tracked stop's own coordinate (for the live map).
    private var stopCoord: CLLocationCoordinate2D? {
        guard let s = store.stopByCode[stopCode] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

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

    /// The live bus marker's stop index — meaningful only against the
    /// direction that actually serves this stop. Nil while the OTHER
    /// direction is being browsed, so a tracked bus is never drawn onto (or
    /// used to grey out stops on) a route it isn't actually running.
    private var displayBusIndex: Int? { busIndex }

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            GeometryReader { geo in
                let restingMap = geo.size.height * 0.56
                // The transparent window in the scroll content that lets the
                // map show through; the sheet header floats over its last
                // `headerPeek` points.
                let mapSpacer = max(140, restingMap - headerPeek)
                ZStack(alignment: .top) {
                    // ── Hero map: a non-interactive preview. Shrinks + fades
                    //    as the sheet is pulled up so it reads as sliding out.
                    heroMap(height: max(headerPeek, restingMap - scrollY))
                        .opacity(1 - Double(min(1, scrollY / mapSpacer)) * 0.85)
                        .allowsHitTesting(false)

                    // ── The pull-up sheet: ETA header (the grabber) + route.
                    ScrollView {
                        VStack(spacing: 0) {
                            // Transparent over the map — tapping it (i.e.
                            // tapping "the map") opens the full-screen map.
                            Color.clear.frame(height: mapSpacer)
                                .contentShape(Rectangle())
                                .onTapGesture { openFull() }
                            etaHeader
                                .wsEntrance()
                            routeCard
                                .wsEntrance(delay: 0.08)
                            Color.clear.frame(height: 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) {
                        $0.contentOffset.y + $0.contentInsets.top
                    } action: { _, y in
                        scrollY = max(0, y)
                    }

                    // Affordance that the map is tappable — fades on scroll.
                    mapTapHint
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .opacity(Double(max(0, 1 - scrollY / 60)))
                        .allowsHitTesting(false)
                }
            }

            cta
                .wsEntrance(delay: 0.16)
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
        .fullScreenCover(isPresented: $showFullMap) {
            WSBusFullMap(serviceNo: serviceNo,
                         seg: approachSegment(),
                         stopCoord: stopCoord,
                         busCoord: busCoord,
                         etaText: fullMapETA.text,
                         etaNow: fullMapETA.now,
                         crowd: (service?.load).map { ($0.wsDotColor, $0.wsSeatPhrase) },
                         onClose: { showFullMap = false })
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

    private func openFull() {
        UISelectionFeedbackGenerator().selectionChanged()
        showFullMap = true
    }

    private var fullMapETA: (text: String, now: Bool) {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        if now { return ("Arriving", true) }
        if let sec { return ("\(max(1, sec / 60)) min", false) }
        return ("—", false)
    }

    // MARK: ETA header (the sheet grabber)
    //
    // The header of the pull-up sheet doubles as the ETA hero: a grab handle,
    // which bus toward where + LIVE, then the big your-stop ETA. Same plate /
    // seat-dot / stacked-ETA grammar as WSDepartureRow so a tapped row grows
    // into a card that reads as the same object. Only the ETA numeral animates
    // (numericText); the seat dot's colour crossfades.

    private var etaHeader: some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        let minutes = sec.map { max(1, $0 / 60) }
        let sched = !(service?.monitored ?? true)
        return VStack(spacing: 0) {
            // Grab handle — signals the sheet pulls up over the map.
            Capsule().fill(ws.rule).frame(width: 40, height: 5)
                .padding(.top, 10).padding(.bottom, 14)

            // ── Header: which bus, toward where, live. ──────────────────
            HStack(spacing: 12) {
                RouteTile(text: serviceNo, size: .large)
                VStack(alignment: .leading, spacing: 3) {
                    Text(destTitle)
                        .font(ws.sans(16, weight: .heavy)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    if let load = service?.load {
                        HStack(spacing: 6) {
                            Circle().fill(load.wsDotColor).frame(width: 7, height: 7)
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
                if service != nil { WSLiveBadge() }
            }

            WSRowDivider().padding(.vertical, 14)

            // ── ETA hero: the whole reason the screen is open. ──────────
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Group {
                    if now {
                        Text("Arriving")
                            .font(ws.sans(32, weight: .heavy)).foregroundStyle(ws.now)
                    } else if let minutes {
                        // Scheduled-only ETA carries the whisper "~" — never a
                        // banner (feedback_timely_over_honest).
                        (Text(sched ? "~" : "").font(ws.sans(20, weight: .semibold)).foregroundStyle(ws.dim)
                         + Text("\(minutes)").font(ws.sans(36, weight: .heavy)).foregroundStyle(ws.text)
                         + Text(" min").font(ws.sans(16, weight: .semibold)).foregroundStyle(ws.dim))
                    } else {
                        Text("—").font(ws.sans(32, weight: .heavy)).foregroundStyle(ws.faint)
                    }
                }
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                Spacer(minLength: 8)
                Text(now ? "at your stop" : "to your stop")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Green left tick while arriving — the same "now" mark as the rows.
        .overlay(alignment: .leading) {
            if now {
                RoundedRectangle(cornerRadius: 2).fill(ws.now)
                    .frame(width: 4).padding(.vertical, 16)
                    .transition(.opacity)
            }
        }
        // A soft shadow so the sheet reads as floating over the map.
        .shadow(color: .black.opacity(0.18), radius: 14, y: -2)
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .animation(.snappy(duration: 0.28), value: minutes)
        .padding(.horizontal, 22)
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

    // MARK: hero map
    //
    // The one thing a "tracking" view should show, promoted to the hero: the
    // bus on its way to your stop. Non-interactive preview (tap opens the
    // full-screen map); shared marker content with the full-screen map via
    // WSApproachMapContent so the two draw identically.

    /// The stops on the live approach (bus → your stop) with their coords —
    /// the segment the map draws as a route line + stop markers.
    private func approachSegment() -> [(coord: CLLocationCoordinate2D, isYou: Bool)] {
        guard let dir = anchorDirection, !dir.stops.isEmpty else { return [] }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let lo = (busIndex.map { min($0, you) }) ?? max(0, you - 4)
        return (lo...you).map { i in
            (CLLocationCoordinate2D(latitude: dir.stops[i].lat, longitude: dir.stops[i].lon), i == you)
        }
    }

    @ViewBuilder private func heroMap(height: CGFloat) -> some View {
        Map(position: $camera, interactionModes: []) {
            WSApproachMapContent(ws: ws, serviceNo: serviceNo,
                                 seg: approachSegment(),
                                 stopCoord: stopCoord, busCoord: busCoord)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipped()
        // A small legend so the marks are self-explanatory.
        .overlay(alignment: .bottomLeading) { mapLegend.padding(.bottom, headerPeek - 8) }
        .overlay(alignment: .topTrailing) {
            if busCoord == nil {
                Text("Live bus updating…")
                    .font(ws.sans(11, weight: .semibold)).foregroundStyle(ws.dim)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(ws.panel))
                    .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
                    .padding(.top, 10).padding(.trailing, 14)
            }
        }
        .accessibilityLabel(busCoord == nil
            ? "Map of your stop and the bus route; live bus position updating. Double tap to expand."
            : "Map showing bus \(serviceNo) approaching your stop. Double tap to expand.")
    }

    private var mapTapHint: some View {
        HStack(spacing: 5) {
            WSIcon(glyph: .map, size: 12, weight: .semibold, color: ws.text)
            Text("Tap to expand")
                .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.text)
        }
        .padding(.horizontal, 11).frame(height: 30)
        .wsGlassChrome(cornerRadius: 15, tint: ws.tabbar)
        .padding(.top, 10).padding(.trailing, 22)
    }

    private var mapLegend: some View {
        HStack(spacing: 10) {
            legendDot(ws.accent, "Your stop")
            legendDot(ws.now, "Bus")
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(ws.panel.opacity(0.92)))
        .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
        .padding(.leading, 14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(ws.sans(10.5, weight: .semibold)).foregroundStyle(ws.dim)
        }
    }

    /// Frame the map to fit your stop, the bus, and the approach segment.
    private func refitMap() {
        camera = .region(wsApproachRegion(seg: approachSegment(),
                                          stop: stopCoord, bus: busCoord))
    }

    // MARK: route card — the live "approach" (Option A, owner 2026-07-10)
    //
    // NOT the whole line. The old card listed all ~32 stops as a static
    // timeline — a foreign idiom to the rest of the app, and dead space that
    // never changed (LTA gives no per-stop times). This shows only the segment
    // that's actually live: how many stops the bus is from you, plus the
    // handful on final approach. The full end-to-end route lives on Service
    // Info (the ⓘ / "Full route ›" link). Grounded on the anchor direction —
    // no direction switcher (that's a full-route concern).

    @ViewBuilder private var routeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                WSIcon(glyph: .busSingle, size: 15, weight: .medium, color: ws.dim)
                Text("On the way")
                    .font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer(minLength: 8)
                if serviceRouteData != nil {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        push(.serviceInfo(no: serviceNo, fromStop: stopCode))
                    } label: {
                        HStack(spacing: 4) {
                            Text("Full route")
                                .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.accentSoft)
                            WSIcon(glyph: .chevron, size: 10, color: ws.accentSoft)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WSCompressStyle())
                    .accessibilityLabel("See the full route for bus \(serviceNo)")
                }
            }

            if let dir = anchorDirection, !dir.stops.isEmpty {
                approach(dir).padding(.top, 14)
            } else {
                // Route still resolving — shimmer skeleton, never a spinner.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array([150, 190, 120].enumerated()), id: \.offset) { _, w in
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

    // MARK: approach

    private func approach(_ dir: RouteDirection) -> some View {
        let stops = dir.stops
        let you = min(max(dir.youIndex, 0), stops.count - 1)
        let busIdx = busIndex.map { min($0, you) }
        // Window: bus → your stop when a live position exists; otherwise just
        // the last few stops before you — spatial context, no invented count.
        let start = busIdx ?? max(0, you - 3)
        let r = RouteInfo(stops: stops, youIndex: you, busIndex: busIdx, busCoord: nil)
        return VStack(alignment: .leading, spacing: 0) {
            approachHeadline(you: you, busIdx: busIdx).padding(.bottom, 14)
            ForEach(start...you, id: \.self) { i in
                stepRow(r, index: i, you: you)
                if busIdx == i && i < you { vehicleRow(r) }
            }
        }
    }

    /// "6 stops away · Seats available" — the one genuinely live line in this
    /// card. Falls back to "Final approach" when there's no GPS to count from.
    @ViewBuilder private func approachHeadline(you: Int, busIdx: Int?) -> some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        HStack(spacing: 8) {
            if let busIdx {
                let away = max(0, you - busIdx)
                if now || away == 0 {
                    Text("Arriving")
                        .font(ws.sans(17, weight: .heavy)).foregroundStyle(now ? ws.now : ws.text)
                } else {
                    (Text("\(away)").font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                     + Text(away == 1 ? " stop away" : " stops away")
                        .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim))
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                }
            } else {
                Text("Final approach")
                    .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
            }
            if let load = service?.load {
                Text("·").font(ws.mono(12)).foregroundStyle(ws.faint)
                Circle().fill(load.wsDotColor).frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: load)
                Text(load.wsSeatPhrase)
                    .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    .lineLimit(1).allowsTightening(true)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.28), value: busIdx)
    }

    private func stepRow(_ r: RouteInfo, index i: Int, you: Int) -> some View {
        let stop = r.stops[i]
        let passed = displayBusIndex.map { i < $0 } ?? false
        let isYou = i == you
        // Stops beyond the user's fade to 40% (design spec §6) — the journey
        // that matters ends at your stop; the tail is context, not content.
        let future = you >= 0 && i > you
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
        .opacity(future ? 0.4 : 1)
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
            busCoord = nil
            refitMap()
            return
        }
        if let coord = await store.liveBus(service: serviceNo, stopCode: stopCode) {
            busCoord = coord
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
            busCoord = nil
        }
        refitMap()
    }
}

// MARK: - Shared map content
//
// The approach markers, drawn identically by the hero preview and the
// full-screen map: the route polyline, upcoming-stop dots, the highlighted
// YOUR STOP pin, and the live green bus plate. The board's one hard rule holds
// — colour is data (blue = your stop, green = the live bus); everything else
// stays neutral.

struct WSApproachMapContent: MapContent {
    let ws: WSTheme
    let serviceNo: String
    let seg: [(coord: CLLocationCoordinate2D, isYou: Bool)]
    let stopCoord: CLLocationCoordinate2D?
    let busCoord: CLLocationCoordinate2D?

    @MapContentBuilder var body: some MapContent {
        // The user's own live location (system blue dot).
        UserAnnotation()

        // The route the bus is taking to reach you.
        if seg.count >= 2 {
            MapPolyline(coordinates: seg.map(\.coord))
                .stroke(ws.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        // Upcoming stops on that segment (small neutral dots).
        ForEach(Array(seg.enumerated()), id: \.offset) { _, s in
            if !s.isYou {
                Annotation("", coordinate: s.coord, anchor: .center) {
                    Circle().fill(ws.bg)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(ws.accent, lineWidth: 3))
                }
                .annotationTitles(.hidden)
            }
        }
        // YOUR STOP — the boarding stop, highlighted distinctly: a labelled
        // accent pin with a halo, unmistakable vs the small route dots, the
        // green bus, and the blue user dot.
        if let stopCoord {
            Annotation("Your stop", coordinate: stopCoord, anchor: .bottom) {
                VStack(spacing: 3) {
                    Text("YOUR STOP")
                        .font(ws.mono(9, weight: .bold)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(Capsule().fill(ws.accent))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    ZStack {
                        Circle().fill(ws.accent).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                        Circle().fill(.white).frame(width: 6, height: 6)
                    }
                    .background { WSPing(cornerRadius: 999) }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
            }
            .annotationTitles(.hidden)
        }

        // THE BUS — live position, green plate.
        if let busCoord {
            Annotation("Bus \(serviceNo)", coordinate: busCoord, anchor: .center) {
                Text(serviceNo)
                    .font(ws.mono(12, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(ws.now))
                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            }
            .annotationTitles(.hidden)
        }
    }
}

/// Frame a region that fits your stop, the live bus, and the approach segment.
func wsApproachRegion(seg: [(coord: CLLocationCoordinate2D, isYou: Bool)],
                      stop: CLLocationCoordinate2D?,
                      bus: CLLocationCoordinate2D?) -> MKCoordinateRegion {
    var lats: [Double] = [], lons: [Double] = []
    if let stop { lats.append(stop.latitude); lons.append(stop.longitude) }
    if let bus { lats.append(bus.latitude); lons.append(bus.longitude) }
    for s in seg { lats.append(s.coord.latitude); lons.append(s.coord.longitude) }
    guard let minLat = lats.min(), let maxLat = lats.max(),
          let minLon = lons.min(), let maxLon = lons.max() else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1.3421, longitude: 103.8198),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    }
    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                       longitude: (minLon + maxLon) / 2),
        span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.008),
                               longitudeDelta: max((maxLon - minLon) * 1.5, 0.008)))
}

// MARK: - Full-screen map
//
// Tapping the hero opens this: the same approach markers on a fully interactive
// map, with a close button and a glass live-info bar (bus, ETA, crowd) docked
// at the bottom. A momentary snapshot — the markers reflect the position at the
// moment it opened (cover-first; a live-updating morph can come later).

private struct WSBusFullMap: View {
    let serviceNo: String
    let seg: [(coord: CLLocationCoordinate2D, isYou: Bool)]
    let stopCoord: CLLocationCoordinate2D?
    let busCoord: CLLocationCoordinate2D?
    let etaText: String
    let etaNow: Bool
    let crowd: (color: Color, phrase: String)?
    var onClose: () -> Void

    @Environment(\.ws) private var ws
    @State private var camera: MapCameraPosition

    init(serviceNo: String,
         seg: [(coord: CLLocationCoordinate2D, isYou: Bool)],
         stopCoord: CLLocationCoordinate2D?,
         busCoord: CLLocationCoordinate2D?,
         etaText: String, etaNow: Bool,
         crowd: (color: Color, phrase: String)?,
         onClose: @escaping () -> Void) {
        self.serviceNo = serviceNo
        self.seg = seg
        self.stopCoord = stopCoord
        self.busCoord = busCoord
        self.etaText = etaText
        self.etaNow = etaNow
        self.crowd = crowd
        self.onClose = onClose
        _camera = State(initialValue: .region(
            wsApproachRegion(seg: seg, stop: stopCoord, bus: busCoord)))
    }

    var body: some View {
        // ZStack (not chained .overlay) with .plain button styles + explicit
        // contentShape — the same idiom WSMapView uses so the controls win the
        // tap over the interactive Map's gesture layer (owner: X/recenter were
        // unresponsive with .overlay + WSCompressStyle).
        ZStack {
            Map(position: $camera) {
                WSApproachMapContent(ws: ws, serviceNo: serviceNo,
                                     seg: seg, stopCoord: stopCoord, busCoord: busCoord)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    title
                    Spacer(minLength: 8)
                    closeButton
                }
                Spacer(minLength: 0)
                HStack { Spacer(minLength: 0); recenterButton }
                    .padding(.bottom, 12)
                infoBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            RouteTile(text: serviceNo, size: .small)
            Text("Live position")
                .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.text)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .wsGlassChrome(cornerRadius: 20, tint: ws.tabbar)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            WSIcon(glyph: .close, size: 16, weight: .bold, color: ws.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .wsGlassChrome(cornerRadius: 22, tint: ws.tabbar)
        .accessibilityLabel("Close map")
    }

    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                camera = .region(wsApproachRegion(seg: seg, stop: stopCoord, bus: busCoord))
            }
        } label: {
            WSIcon(glyph: .scope, size: 18, color: ws.text)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .wsGlassChrome(cornerRadius: 23, tint: ws.tabbar)
        .accessibilityLabel("Recenter map")
    }

    private var infoBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(etaNow ? "Arriving" : "\(etaText)")
                    .font(ws.sans(20, weight: .heavy))
                    .foregroundStyle(etaNow ? ws.now : ws.text)
                Text("to your stop")
                    .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
            }
            Spacer(minLength: 8)
            if let crowd {
                HStack(spacing: 6) {
                    Circle().fill(crowd.color).frame(width: 8, height: 8)
                    Text(crowd.phrase)
                        .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.dim)
                        .lineLimit(1).allowsTightening(true)
                }
            }
        }
        .padding(.horizontal, 18).frame(height: 66)
        .wsGlassChrome(cornerRadius: 22, tint: ws.tabbar)
        .padding(.horizontal, 16).padding(.bottom, 20)
    }
}
