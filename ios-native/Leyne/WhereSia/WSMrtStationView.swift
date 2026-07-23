// WhereSia — MRT station (screen 5).
//
// Station name + line bullets + service state, then three dense cards:
// STATION CROWD (live gauge + word; per-line platform rows only when the
// station is an interchange — for single-line stations they'd duplicate the
// headline reading), BUS STOPS AT THIS STATION (nearest stops ≤ 400 m with
// their live soonest arrival — tap through), and CROWD FORECAST (LTA's real
// PCDForecast 30-min series — NOT mocked — with a "busiest around…" note).

import SwiftUI
import CoreLocation

struct WSMrtStationView: View {
    let station: MrtGeoStation
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var forecast: [ForecastPoint] = []
    /// True when today's series exists but is entirely spent (now past the
    /// final slot's end) — the station is closed for the night. Renders a
    /// quiet "service has ended" line instead of the stale tail the old
    /// windowing showed, whose last slot got flagged "now" and produced
    /// "Busiest around now" on a closed station (owner-reported 2026-07-04).
    @State private var forecastEnded = false
    @State private var titleCollapsed = false
    /// Full-line diagram sheet (the "LINE MAP" link) — jump to any station.
    @State private var showLineMap = false
    /// Scroll-driven collapse of the line-map hero (same logic as the bus
    /// view's map): the cards slide up over the shrinking/fading line strip.
    @State private var scrollY: CGFloat = 0

    /// How much of the station sheet header floats over the line-map hero at
    /// rest — the "grab me" peek.
    private let headerPeek: CGFloat = 92

    struct ForecastPoint: Identifiable {
        let id = UUID()
        let time: String
        let fraction: CGFloat
        let isNow: Bool
        let level: CrowdLevel
    }

    private var lines: [MRTLine] {
        var out: [MRTLine] = []
        for c in station.codes { if let l = wsLine(forStationCode: c), !out.contains(l) { out.append(l) } }
        return out
    }

    private var status: String {
        let disrupted = station.codes.contains { code in
            store.trainAlerts.contains { $0.line == wsLine(forStationCode: code) }
        }
        return disrupted ? "SERVICE DISRUPTED" : "NORMAL SERVICE"
    }

    private var crowdNow: CrowdLevel { store.wsCrowd(for: station) ?? .unknown }

    /// Standard network-wide hours (owner decision 2026-07-03) — the app
    /// carries no per-station timetable, so every station shows the same
    /// window. Mirrored on Android in soft_mrt_station_screen.dart.
    private var hoursLine: String {
        m.use24h ? "OPEN DAILY · 05:30 – 00:00" : "OPEN DAILY · 5:30 AM – 12:00 AM"
    }

    var body: some View {
        // titleRow's "UPD h:mm" stamp is `WSFmt.upd(Date(), ...)` — a live
        // wall-clock read, not a stored fetch timestamp — so this view needs
        // a tick dependency to keep advancing under @Observable's
        // per-property tracking (ObservableObject used to refresh it for
        // free via the blanket per-second objectWillChange).
        let _ = m.tick
        Group {
            // The line map is the hero (owner 2026-07-11) — it collapses on
            // scroll while the cards slide up over it, the same motion as the
            // bus view's map. LRT-only / dead-end stops have no neighbour
            // strip, so they fall back to the plain stacked layout.
            if let map = wsLineNeighbors(around: station, radius: 2), map.items.count > 1 {
                heroLayout(map: map)
            } else {
                plainLayout
            }
        }
        .wsEntrance()
        .background(ws.bg)
        .wsHeaderBar(eyebrow: "MRT station", title: station.name,
                     collapsed: titleCollapsed, onBack: onBack) {
            WSHairButton(glyph: m.isMrtSaved(station) ? .bookmarkFilled : .bookmark) {
                m.toggleMrtSaved(station)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: m.isMrtSaved(station))
        .onAppear {
            store.wsWarmCrowd(for: [station])
            for l in lines { store.refreshForecast(line: l) }
            for item in nearbyStops { store.ensureArrivals(stop: item.stop.BusStopCode, silent: true) }
            // Live service disruptions + lift outages for this station (same
            // feeds the Alerts tab uses).
            store.refreshTrainAlertsIfStale(force: true)
            store.refreshLiftMaintenanceIfStale(force: true)
            loadForecast()
        }
        .sheet(isPresented: $showLineMap) {
            if let prefix = primaryLineCode.flatMap({ wsCodeParts($0)?.prefix }) {
                WSLineMapSheet(
                    prefix: prefix,
                    currentCode: primaryLineCode ?? "",
                    colour: WSLine.color(forStationCode: station.codes.first ?? ""),
                    lineName: wsLineNames(from: station.codes),
                    onSelect: { push(.mrtStation($0)) })
                .environment(\.ws, ws)
            }
        }
    }

    /// The station's code on its primary heavy-rail line (e.g. "CC20").
    private var primaryLineCode: String? {
        station.codes.first { wsLine(forStationCode: $0) != nil }
    }

    // MARK: hero layout (collapsing line map)

    private func heroLayout(map: (prefix: String, items: [(code: String, name: String, current: Bool)])) -> some View {
        let colour = WSLine.color(forStationCode: station.codes.first ?? "")
        return GeometryReader { geo in
            let restingHero = geo.size.height * 0.34
            let spacer = max(110, restingHero - headerPeek)
            let fade = 1 - Double(min(1, scrollY / spacer)) * 0.85
            ZStack(alignment: .top) {
                // Flat line-identity tint behind the hero — collapses + fades
                // behind the rising sheet. Non-interactive. Was a gradient
                // wash; flattened 2026-07-22 (ornament, and a vertical fade is
                // exactly what glare flattens into mud anyway). The line colour
                // stays because here it IS data: station identity.
                colour.opacity(0.10)
                    .frame(height: max(headerPeek, restingHero - scrollY))
                    .frame(maxWidth: .infinity)
                    .opacity(fade)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 12) {
                        // Transparent window that lets the line map show through.
                        Color.clear.frame(height: spacer)
                        stationSheetHeader.wsEntrance()
                        alertsCard.wsEntrance(delay: 0.04)
                        crowdCard.wsEntrance(delay: 0.06)
                        facilitiesCard.wsEntrance(delay: 0.12)
                        adCard.wsEntrance(delay: 0.18)
                        busCard.wsEntrance(delay: 0.24)
                        forecastCard.wsEntrance(delay: 0.30)
                        Color.clear.frame(height: 12)
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.y + $0.contentInsets.top
                } action: { _, y in
                    scrollY = max(0, y)
                    titleCollapsed = y > 44
                }

                // The interactive line strip floats ON TOP of the sheet, not
                // behind it: a ScrollView swallows touches meant for layers
                // beneath it, so a strip drawn behind can't be tapped, swiped,
                // or its LINE MAP button pressed. Here it slides up + fades with
                // scroll to still read as "collapsing", and drops its hit
                // testing once scrolled so it never blocks the cards below.
                lineStrip(map: map, colour: colour)
                    .offset(y: -scrollY)
                    .opacity(fade)
                    .allowsHitTesting(scrollY < 8)
            }
        }
    }

    private var plainLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Staggered launch sequence (anim spec): head → cards, 60ms
                // steps, fade + 12pt rise.
                titleRow.padding(.top, 12).wsEntrance(delay: 0)
                alertsCard.wsEntrance(delay: 0.04)
                crowdCard.wsEntrance(delay: 0.06)
                facilitiesCard.wsEntrance(delay: 0.12)
                adCard.wsEntrance(delay: 0.18)
                busCard.wsEntrance(delay: 0.24)
                forecastCard.wsEntrance(delay: 0.30)
                Color.clear.frame(height: 12)
            }
            .padding(.bottom, 8)
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 44
        } action: { _, isPast in
            titleCollapsed = isPast
        }
    }

    // The hero content: the line name + LINE MAP link, then the station framed
    // by its neighbours as a horizontally scrollable strip — the one place
    // colour = line identity. Drawn as a front overlay (see heroLayout) so it's
    // interactive; the gradient wash lives on a separate layer behind the sheet.
    private func lineStrip(map: (prefix: String, items: [(code: String, name: String, current: Bool)]),
                           colour: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                Text("\(wsLineNames(from: station.codes)) Line")
                    .font(ws.sans(14, weight: .heavy)).foregroundStyle(colour).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showLineMap = true
                } label: {
                    HStack(spacing: 4) {
                        Text("LINE MAP")
                            .font(ws.mono(10, weight: .bold)).tracking(1)
                        WSIcon(glyph: .chevron, size: 9, color: ws.faint)
                    }
                    .foregroundStyle(ws.faint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            Spacer(minLength: 0).frame(height: 20)
            railStrip(prefix: map.prefix, currentCode: primaryLineCode ?? "", colour: colour)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// The whole line as a horizontally scrollable strip, auto-centred on the
    /// current station. One continuous rail (a single rectangle behind the
    /// nodes — no per-column seams, so the line never looks jagged) with a
    /// fixed-width column per station. Neighbours push their own station; the
    /// current station is inert. Swipe to walk the line, or tap LINE MAP for
    /// the full jump-to-any diagram.
    private func railStrip(prefix: String, currentCode: String, colour: Color) -> some View {
        let seq = wsLineSequence(prefix: prefix)
        let colW: CGFloat = 84
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .top) {
                    // Single continuous rail, spanning first node centre to last,
                    // sitting at the node band's vertical centre (22 / 2 = 11).
                    Rectangle().fill(colour.opacity(0.4))
                        .frame(height: 4)
                        .padding(.horizontal, colW / 2)
                        .padding(.top, 9)
                    HStack(spacing: 0) {
                        ForEach(seq, id: \.code) { s in
                            lineColumn(code: s.code, name: s.name,
                                       current: s.code == currentCode, colW: colW)
                        }
                    }
                }
                .padding(.horizontal, 22)
                // Headroom above the node band so the current-station ping
                // ring (scales to 2× its 18pt anchor) has room to expand
                // into without the ScrollView clipping its top edge.
                .padding(.top, 10)
            }
            .onAppear { proxy.scrollTo(currentCode, anchor: .center) }
        }
    }

    @ViewBuilder
    private func lineColumn(code: String, name: String, current: Bool, colW: CGFloat) -> some View {
        let column = VStack(spacing: 10) {
            Circle()
                .fill(current ? WSLine.color(forStationCode: code) : ws.bg)
                .frame(width: current ? 18 : 12, height: current ? 18 : 12)
                .overlay(Circle().stroke(WSLine.color(forStationCode: code),
                                         lineWidth: current ? 4 : 3))
                .background { if current { WSPing(cornerRadius: 999) } }
                .frame(height: 22)
            VStack(spacing: 3) {
                Text(code)
                    .font(ws.mono(11, weight: .bold))
                    .foregroundStyle(current ? ws.text : WSLine.color(forStationCode: code))
                Text(name)
                    .font(ws.sans(current ? 12.5 : 11, weight: current ? .bold : .medium))
                    .foregroundStyle(current ? ws.text : ws.dim)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: colW)
        .contentShape(Rectangle())
        .id(code)

        if current {
            column
        } else {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                if let st = MrtGeo.station(forCode: code) { push(.mrtStation(st)) }
            } label: { column }
            .buttonStyle(WSCompressStyle())
        }
    }

    // The floating sheet header — the grabber that carries the station name,
    // line bullets, status, and the live crowd word (the "reason" summary,
    // like the bus view's ETA header).
    private var stationSheetHeader: some View {
        VStack(spacing: 0) {
            Capsule().fill(ws.rule).frame(width: 40, height: 5)
                .padding(.top, 10).padding(.bottom, 14)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(station.name)
                            .font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text).lineLimit(1)
                        ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                    }
                    Text("\(statusLine)  ·  \(WSFmt.upd(Date(), use24h: m.use24h))")
                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                }
                Spacer(minLength: 8)
                if crowdNow != .unknown {
                    VStack(alignment: .trailing, spacing: 4) {
                        WSLiveBadge()
                        Text(crowdNow.wsWord)
                            .font(ws.sans(13, weight: .bold)).foregroundStyle(ws.text)
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(ws.rule, lineWidth: 1))
        .padding(.horizontal, 22)
    }

    /// Bus stops physically at/around the station (≤ 400 m walk).
    private var nearbyStops: [(stop: LTABusStop, distanceM: Int)] {
        store.wsStopsNear(CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), limit: 3)
            .filter { $0.distanceM <= 400 }
    }

    /// Card-grammar head (owner spec 2026-07-08): name + line bullets on one
    /// line, quiet status/hours meta under it — same voice as Home's cards.
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(station.name)
                    .font(ws.sans(25, weight: .heavy)).foregroundStyle(ws.text)
                    .lineLimit(1)
                ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                Spacer(minLength: 0)
            }
            Text("\(statusLine) · \(WSFmt.upd(Date(), use24h: m.use24h))")
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                .padding(.top, 8)
            Text(hoursDisplay)
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.faint)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private func sentenceCase(_ s: String) -> String {
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    private var statusLine: String {
        status == "NORMAL SERVICE" ? "Normal service" : "Service disrupted"
    }
    private var hoursDisplay: String {
        m.use24h ? "Open daily  ·  05:30 – 00:00" : "Open daily  ·  5:30 AM – 12:00 AM"
    }

    // MARK: station crowd (headline + per-platform rows for interchanges)

    private var crowdCard: some View {
        WSCard(title: "Station crowd now", glyph: .train) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crowdNow.wsWord).font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
                        // Sentence case — the card grammar speaks quietly now
                        // (the shared wsHint strings stay caps for Android/mono
                        // call sites).
                        Text(sentenceCase(crowdNow.wsHint))
                            .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    }
                    Spacer()
                    if crowdNow != .unknown { WSLiveBadge() }
                }
                .padding(.top, 8)
                // CrowdGauge needs a concrete width up front; a GeometryReader
                // reads the real local container width (respects the card's
                // own padding, rotation, and multitasking/split-view) instead
                // of a hardcoded UIScreen.main.bounds calculation.
                GeometryReader { geo in
                    CrowdGauge(fraction: crowdNow.wsFraction, width: geo.size.width, height: 9)
                }
                .frame(height: 9)

                // Per-line platform readings only where they can differ from
                // the headline — i.e. interchanges. On a single-line station
                // this would repeat the number above (the old "By line" card).
                if lines.count > 1 {
                    WSRowDivider().padding(.top, 6)
                    ForEach(lines.indices, id: \.self) { i in
                        let line = lines[i]
                        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
                        let level = store.crowdByLine[line]?.first { $0.code == code }?.level ?? .unknown
                        HStack(spacing: 10) {
                            LineBullet(code: line.pcdLineCode, isLineCode: true)
                            Text("\(line.displayName) platform")
                                .font(ws.sans(13, weight: .bold)).foregroundStyle(ws.text)
                            Spacer()
                            CrowdGauge(fraction: level.wsFraction, width: 44)
                            Text(level.wsWord).font(ws.mono(10.5)).foregroundStyle(ws.dim)
                        }
                        .padding(.top, 7)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: bus connections

    @ViewBuilder private var busCard: some View {
        let near = nearbyStops
        if !near.isEmpty {
            WSCard(title: "Bus stops at this station", glyph: .busSingle) {
                VStack(spacing: 0) {
                    ForEach(near.indices, id: \.self) { i in
                        let item = near[i]
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            push(.busStop(code: item.stop.BusStopCode))
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.stop.Description)
                                        .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.text)
                                        .lineLimit(1)
                                    Text("\(item.stop.BusStopCode)  ·  \(fmtDistance(item.distanceM))")
                                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                                        // Distance updates crossfade only —
                                        // no slide, no pulse (anim spec).
                                        .contentTransition(.opacity)
                                }
                                Spacer(minLength: 8)
                                if let s = wsSoonest(store.servicesFor(item.stop.BusStopCode)) {
                                    let sec = wsLiveETASec(s)
                                    let minutes = max(1, sec / 60)
                                    Group {
                                        if sec < 60 {
                                            Text("Now").font(ws.sans(17, weight: .heavy))
                                                .foregroundStyle(ws.text)
                                        } else if sec < 120 {
                                            Text("Arriving").font(ws.sans(14, weight: .heavy))
                                                .foregroundStyle(ws.text)
                                        } else {
                                            (Text("\(minutes)")
                                                .font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
                                             + Text(" min")
                                                .font(ws.sans(11, weight: .semibold)).foregroundStyle(ws.dim))
                                        }
                                    }
                                    .contentTransition(.numericText(countsDown: true))
                                    // The number needs an animation keyed to
                                    // its value for numericText to fire —
                                    // only the digits move, never the row.
                                    .animation(.snappy(duration: 0.28), value: minutes)
                                    .animation(.snappy(duration: 0.28), value: sec < 60)
                                }
                                WSIcon(glyph: .chevron, size: 12, color: ws.faint)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(WSCompressStyle())
                        // Long-press: act on the stop without leaving the
                        // station screen (anim spec: lift + blur + menu are
                        // the system's own 250ms spring).
                        .contextMenu {
                            Button { toggleStopPin(item.stop.BusStopCode) } label: {
                                Label(isStopPinned(item.stop.BusStopCode)
                                          ? "Remove from Saved" : "Save stop",
                                      systemImage: isStopPinned(item.stop.BusStopCode)
                                          ? "bookmark.slash" : "bookmark")
                            }
                            ShareLink(item: "\(item.stop.Description) — bus stop \(item.stop.BusStopCode)") {
                                Label("Share stop", systemImage: "square.and.arrow.up")
                            }
                        }
                        if i < near.count - 1 { WSRowDivider() }
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: station facilities
    //
    // The mockup's 3×2 amenity grid. These are network-standard amenities
    // present at effectively every MRT station (toilets, lifts, step-free
    // access, escalators, fare top-up, retail) — presentational, greyscale,
    // matching the "colour = data" rule (chrome stays neutral). Live lift-
    // maintenance status still lives in the crowd/alerts path; this grid is
    // the at-a-glance "what's here".

    private var facilitiesCard: some View {
        WSCard(title: "Station facilities", glyph: .info) { WSStationFacilitiesGrid() }
            .padding(.horizontal, 22)
    }

    // MARK: service alerts (live disruptions + lift outages at THIS station)
    //
    // Same feeds as the Alerts tab (DataStore.trainAlerts by line +
    // liftMaintenance by station), filtered to this station. Only rendered when
    // something's actually wrong — otherwise the header's "Normal service" says
    // it all.

    /// Line disruptions touching any of this station's lines.
    private var stationAlerts: [TrainAlert] {
        let mine = Set(lines)
        return store.trainAlerts.filter { $0.line.map(mine.contains) ?? false }
    }
    /// Lift outages reported at this station.
    private var stationLifts: [LiftMaintenance] {
        store.liftMaintenance.filter {
            $0.stationName.caseInsensitiveCompare(station.name) == .orderedSame
        }
    }

    @ViewBuilder private var alertsCard: some View {
        let alerts = stationAlerts
        let lifts = stationLifts
        if !alerts.isEmpty || !lifts.isEmpty {
            WSCard(title: "Service alerts", glyph: .alerts) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(alerts.indices, id: \.self) { i in
                        let a = alerts[i]
                        HStack(alignment: .top, spacing: 12) {
                            LineBullet(code: a.lineCode, size: .large, isLineCode: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
                                Text(a.detail)
                                    .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim).lineSpacing(2)
                                if a.freeBus || a.freeShuttle {
                                    HStack(spacing: 6) {
                                        if a.freeBus { miniBadge("FREE BUS") }
                                        if a.freeShuttle { miniBadge("FREE SHUTTLE") }
                                    }.padding(.top, 3)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if i < alerts.count - 1 || !lifts.isEmpty { WSRowDivider() }
                    }
                    ForEach(lifts.indices, id: \.self) { i in
                        let lift = lifts[i]
                        HStack(alignment: .top, spacing: 12) {
                            WSIcon(glyph: .lift, size: 18, color: ws.text)
                                .frame(width: 34, height: 34)
                                .background(ws.panel2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Lift out of service").font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
                                Text(lift.detail)
                                    .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim).lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                            miniBadge("LIFT")
                        }
                        .padding(.vertical, 10)
                        if i < lifts.count - 1 { WSRowDivider() }
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private func miniBadge(_ text: String) -> some View {
        Text(text).font(ws.mono(9.5, weight: .bold)).tracking(0.7).foregroundStyle(ws.dim)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ws.rule, lineWidth: 1))
    }

    // MARK: inline ad
    //
    // In-content MREC (300×250) styled as one of the sheet cards, replacing the
    // old anchored bottom banner that read as bolted-on system chrome on this
    // dark editorial layout. Self-suppresses when ads are disabled.
    @ViewBuilder private var adCard: some View {
        if !AdConfig.adsSuppressed {
            MediumRectAd()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    // MARK: forecast

    private var forecastCard: some View {
        WSCard(title: "Crowd forecast today", glyph: .clock) {
            VStack(alignment: .leading, spacing: 6) {
                if forecast.isEmpty {
                    Text(forecastEnded
                         ? "Service has ended for today — forecast returns in the morning."
                         : "Forecast unavailable right now.")
                        .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                        .padding(.vertical, 12)
                } else {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(forecast) { p in
                            ForecastBar(fraction: p.fraction, time: p.time, isNow: p.isNow)
                        }
                    }
                    .padding(.top, 6)
                    if let busiest = busiestNote {
                        (Text("Busiest around ").foregroundStyle(ws.dim)
                         + Text(busiest).fontWeight(.bold).foregroundStyle(ws.text)
                         + Text(". Leave a little earlier to beat the crowd.").foregroundStyle(ws.dim))
                            .font(ws.sans(11.5, weight: .medium))
                            .padding(.top, 12)
                    }
                    // No provenance footnote — users don't care where the
                    // data comes from (owner, 2026-07-02); the card title +
                    // time labels say everything.
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private func isStopPinned(_ code: String) -> Bool {
        m.pins.contains { $0.code == code }
    }
    private func toggleStopPin(_ code: String) {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }

    private var busiestNote: String? {
        guard let peak = forecast.max(by: { $0.fraction < $1.fraction }), peak.fraction > 0 else { return nil }
        // A flat window has no meaningful "busiest" — suppress the note
        // rather than crown an arbitrary slot (Android `_peakOf` parity).
        let known = forecast.filter { $0.level != .unknown }
        guard !known.allSatisfy({ $0.level == known.first?.level }) else { return nil }
        return peak.isNow ? "now" : peak.time
    }

    private func loadForecast() {
        guard let line = lines.first else { return }
        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
        Task {
            guard let intervals = try? await LTAService.shared.stationForecast(trainLine: line.pcdLineCode)
            else { return }
            let now = Date()
            let mine = intervals
                .filter { $0.station == code }
                .sorted { $0.start < $1.start }
            // Service day over? (now past the final slot's start + 30 min.)
            // Show the closed line instead of a stale tail — mirrors
            // ForecastWindow.build's closed gate on Android.
            if let last = mine.last, now >= last.start.addingTimeInterval(30 * 60) {
                await MainActor.run { forecast = []; forecastEnded = true }
                return
            }
            // Take the upcoming window (from the last past interval through the
            // next five), so "now" anchors the chart.
            let upcomingIdx = mine.firstIndex { $0.start >= now } ?? max(0, mine.count - 1)
            let start = max(0, upcomingIdx - 1)
            let window = Array(mine[start..<min(mine.count, start + 6)])
            let pts = window.map { iv -> ForecastPoint in
                let level = CrowdLevel.from(iv.crowdLevel)
                let isNow = iv.start <= now && (mine.first { $0.start > iv.start }?.start ?? .distantFuture) > now
                return ForecastPoint(
                    time: isNow ? "now" : WSFmt.clock(iv.start, use24h: m.use24h),
                    fraction: level.wsFraction, isNow: isNow, level: level)
            }
            await MainActor.run { forecast = pts; forecastEnded = false }
        }
    }
}

// MARK: - Full line diagram (the "LINE MAP" sheet)
//
// The whole line as a scrollable vertical list with the rail running down the
// side — the jump-to-any-station view. Auto-scrolls to the current station on
// open; tapping any other station dismisses and pushes it.
private struct WSLineMapSheet: View {
    let prefix: String
    let currentCode: String
    let colour: Color
    let lineName: String
    var onSelect: (MrtGeoStation) -> Void

    @Environment(\.ws) private var ws
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let seq = wsLineSequence(prefix: prefix)
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                LineBullet(code: currentCode)
                Text("\(lineName) Line")
                    .font(ws.sans(18, weight: .heavy)).foregroundStyle(ws.text)
                Spacer()
                Button { dismiss() } label: {
                    WSIcon(glyph: .close, size: 15, color: ws.dim)
                        .frame(width: 32, height: 32)
                        .background(ws.panel2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(seq.enumerated()), id: \.element.code) { i, s in
                            row(code: s.code, name: s.name,
                                isFirst: i == 0, isLast: i == seq.count - 1)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onAppear { proxy.scrollTo(currentCode, anchor: .center) }
            }
        }
        .background(ws.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(code: String, name: String, isFirst: Bool, isLast: Bool) -> some View {
        let cur = code == currentCode
        Button {
            guard !cur, let st = MrtGeo.station(forCode: code) else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            dismiss()
            onSelect(st)
        } label: {
            HStack(spacing: 14) {
                // Rail + node column: two flexible half-segments meeting at the
                // node's centre, continuous across the fixed-height rows.
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(isFirst ? Color.clear : colour.opacity(0.4)).frame(width: 4)
                        Rectangle().fill(isLast ? Color.clear : colour.opacity(0.4)).frame(width: 4)
                    }
                    Circle()
                        .fill(cur ? colour : ws.bg)
                        .frame(width: cur ? 16 : 12, height: cur ? 16 : 12)
                        .overlay(Circle().stroke(colour, lineWidth: cur ? 4 : 3))
                }
                .frame(width: 34)

                Text(code)
                    .font(ws.mono(12, weight: .bold))
                    .foregroundStyle(cur ? ws.text : colour)
                    .frame(width: 48, alignment: .leading)
                Text(name)
                    .font(ws.sans(cur ? 16 : 15, weight: cur ? .bold : .medium))
                    .foregroundStyle(cur ? ws.text : ws.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if cur {
                    Text("YOU ARE HERE")
                        .font(ws.mono(9, weight: .bold)).tracking(1).foregroundStyle(ws.faint)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(WSCompressStyle())
        .id(code)
    }
}
