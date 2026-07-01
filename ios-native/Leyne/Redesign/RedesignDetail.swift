// Detail screens (iOS) — Stop, Station and Route.

import SwiftUI

// ===================================================================== STOP

struct RDStopScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore

    var body: some View {
        let stop = m.currentStop
        let arrivals = stop.arrivals
        return VStack(spacing: 0) {
            HStack {
                RDCircleButton(symbol: "arrow.left", bordered: false, iconSize: 24, t: t) { m.back() }
                Spacer()
                Button(action: { m.toggleSaveStop() }) {
                    ZStack {
                        Circle().strokeBorder(t.outlineVariant, lineWidth: 1)
                        RDSym(m.stopSaved ? "bookmark.fill" : "bookmark", size: 21,
                              color: m.stopSaved ? t.primary : t.onVariant)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(stop.name).font(rdFont(28, .heavy)).foregroundStyle(t.onSurface)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    RDMrtBadgeRow(stopName: stop.name)
                }
                HStack(spacing: 12) {
                    if !stop.dist.isEmpty {
                        HStack(spacing: 5) {
                            RDSym("figure.walk", size: 16, color: t.onVariant)
                            Text(stop.dist).font(rdFont(12.5, .bold)).foregroundStyle(t.onSurface)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(t.scHigh).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    if !stop.code.isEmpty {
                        Text(stop.code).font(rdFont(12, .semibold)).foregroundStyle(t.onVariant)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 9) {
                    if arrivals.isEmpty {
                        VStack(spacing: 6) {
                            RDSym("bus", size: 26, color: t.outline)
                            Text("No live arrivals right now")
                                .font(rdFont(13, .semibold)).foregroundStyle(t.onVariant)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        ForEach(arrivals) { a in routeCard(a) }
                        HStack(spacing: 7) {
                            RDSym("clock", size: 16, color: t.onVariant)
                            Text(freshnessLabel).font(rdFont(11.5, .medium)).foregroundStyle(t.onVariant)
                        }
                        .padding(8)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
        .background(t.surface)
        .onAppear {
            if let code = m.currentNearby?.stopCode { store.ensureArrivals(stop: code) }
        }
    }

    private var freshnessLabel: String {
        guard let code = m.currentNearby?.stopCode, let last = store.lastRefresh(code) else {
            return "Live from LTA"
        }
        let s = Int(Date().timeIntervalSince(last))
        return s < 60 ? "Live from LTA · refreshed \(max(0, s))s ago"
                      : "Live from LTA · refreshed \(s / 60)m ago"
    }

    private func routeCard(_ a: RDArrival) -> some View {
        let occ = rdOcc(a.load, t)
        return Button(action: { m.openBus(service: a.route, stopCode: m.currentNearby?.stopCode) }) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.route).font(rdFont(19, .black)).foregroundStyle(t.onSurface)
                    Text(a.dest).font(rdFont(10, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                    HStack(spacing: 4) {
                        RDDot(color: occ.color, size: 6)
                        Text(occ.label).font(rdFont(10, .medium)).foregroundStyle(t.onVariant)
                    }
                    .padding(.top, 5)
                }
                .frame(width: 72, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(a.min).font(rdFont(26, .black)).foregroundStyle(t.primary)
                        Text("min").font(rdFont(9, .medium)).foregroundStyle(t.onVariant)
                    }
                    if let then = a.then {
                        Text(then).font(rdFont(10, .medium)).foregroundStyle(t.onVariant)
                    }
                }
                RDSym("chevron.right", size: 20, color: t.outline).padding(.leading, 14)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .background(t.scLow)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(t.outlineVariant, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ================================================================== STATION

struct RDStationScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore

    // Nearest bus stop to THIS station (for the transfer card) — resolved once
    // on appear so we don't haversine the full ~5k-stop index every render.
    @State private var nearStopCode: String? = nil
    @State private var nearStopName: String = ""
    @State private var nearStopWalk: Int = 0
    @State private var stripPulse = false

    private var station: MrtGeoStation? {
        guard let name = m.activeStationName else { return nil }
        return MrtGeo.all.first { $0.name == name }
    }

    private func lineFor(_ code: String) -> MRTLine? {
        MRTLine(rawValue: String(code.prefix(2)).uppercased())
    }

    private var lines: [MRTLine] {
        guard let s = station else { return [] }
        var seen = Set<MRTLine>(); var out: [MRTLine] = []
        for c in s.codes {
            guard let l = lineFor(c), !seen.contains(l) else { continue }
            seen.insert(l); out.append(l)
        }
        return out
    }

    private var crowd: CrowdLevel? {
        guard let s = station else { return nil }
        for line in lines {
            if let list = store.crowdByLine[line],
               let sc = list.first(where: { s.codes.contains($0.code) }) { return sc.level }
        }
        return nil
    }

    private var disruption: TrainAlert? {
        store.trainAlerts.first { ($0.line.map { lines.contains($0) }) ?? false }
    }

    private var walkText: String? {
        guard let s = station, let loc = LocationManager.shared.location else { return nil }
        let d = haversine(loc.coordinate.latitude, loc.coordinate.longitude, s.lat, s.lon)
        return "\(max(1, Int((d / 80).rounded()))) min walk · \(fmtDistance(Int(d.rounded())))"
    }

    var body: some View {
        let s = station
        return VStack(spacing: 0) {
            HStack {
                RDCircleButton(symbol: "arrow.left", iconColor: t.onSurface, iconSize: 23, t: t) { m.back() }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(s?.name ?? "Station").font(rdFont(28, .heavy)).foregroundStyle(t.onSurface)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let s {
                    HStack(spacing: 6) {
                        ForEach(s.codes.prefix(3), id: \.self) { code in
                            Text(code).font(rdFont(11, .heavy)).foregroundStyle(rdMrtBadgeFg(code))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(mrtLineColorFor(code))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    .padding(.top, 9)
                }
                if let line = lines.first {
                    HStack(spacing: 7) {
                        RDDot(color: line.color, size: 9)
                        Text(lines.map { "\($0.displayName) Line" }.joined(separator: " · "))
                            .font(rdFont(12.5, .semibold)).foregroundStyle(t.onVariant).lineLimit(1)
                    }
                    .padding(.top, 9)
                }
                HStack(spacing: 8) {
                    if let walkText { chip(icon: "figure.walk", text: walkText, bg: t.scHigh, fg: t.onSurface) }
                    if let crowd {
                        let cc = crowdStyle(crowd)
                        chip(dot: cc.dot, text: cc.label, bg: cc.bg, fg: cc.fg)
                    }
                }
                .padding(.top, 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 14) {
                    lineStatusCard
                    liftCard
                    if let line = lines.first { lineStripCard(line) }
                    busConnections
                    trainNote
                }
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 20)
            }
        }
        .background(t.surface)
        .onAppear {
            store.refreshTrainAlertsIfStale()
            store.refreshLiftMaintenanceIfStale()
            for line in lines { store.refreshCrowd(line: line) }
            computeNearestStop()
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { stripPulse = true }
        }
    }

    @ViewBuilder
    private func chip(icon: String? = nil, dot: Color? = nil, text: String, bg: Color, fg: Color) -> some View {
        HStack(spacing: 5) {
            if let icon { RDSym(icon, size: 16, color: t.onVariant) }
            if let dot { RDDot(color: dot) }
            Text(text).font(rdFont(12.5, .bold)).foregroundStyle(fg)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(bg).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func crowdStyle(_ c: CrowdLevel) -> (label: String, dot: Color, bg: Color, fg: Color) {
        switch c {
        case .low:      return ("Not crowded", t.bus, t.busContainer, t.onBusContainer)
        case .moderate: return ("Some crowd", t.amber, t.amberContainer, t.onAmberContainer)
        case .high:     return ("Crowded", t.mrt, t.mrtContainer, t.onMrtContainer)
        case .unknown:  return ("Crowd —", t.outline, t.scHigh, t.onVariant)
        }
    }

    /// Network status. Neutral grey when everything is normal (nothing needs
    /// attention — no false-alarm green/red); colour is reserved for an actual
    /// disruption: amber for a delay, red when a service is suspended.
    private var lineStatusCard: some View {
        let alert = disruption
        let suspended = (alert?.title.localizedCaseInsensitiveContains("suspend") ?? false)
            || (alert?.detail.localizedCaseInsensitiveContains("suspend") ?? false)
        let lineColor = lines.first?.color ?? t.primary
        let bg: Color   = alert == nil ? t.scLow : (suspended ? t.mrtContainer : t.amberContainer)
        let fg: Color   = alert == nil ? t.onSurface : (suspended ? t.onMrtContainer : t.onAmberContainer)
        let sub: Color  = alert == nil ? t.onVariant : fg
        let accent: Color = alert == nil ? lineColor : (suspended ? t.mrt : t.amber)
        let icon = alert == nil ? "checkmark.circle.fill" : (suspended ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
        let lineName = lines.first?.displayName ?? "Line"
        return Button(action: { m.toLines() }) {
            HStack(spacing: 0) {
                Rectangle().fill(accent).frame(width: 3)   // line-colour left accent
                HStack(spacing: 11) {
                    RDSym(icon, size: 18, color: accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert?.title ?? "No disruptions")
                            .font(rdFont(13, .heavy)).foregroundStyle(fg).lineLimit(1)
                        Text(alert?.detail ?? "\(lineName) Line · tap for network status")
                            .font(rdFont(11, .medium)).foregroundStyle(sub).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RDSym("chevron.right", size: 17, color: sub)
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
            }
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Transfer card — the nearest bus stop to this station and the real bus
    /// services calling there (live from LTA), so "getting there" is concrete.
    private var busConnections: some View {
        let nums = stationServiceNumbers
        return Button(action: { m.go("switch") }) {
            HStack(spacing: 0) {
                Rectangle().fill(t.primary.opacity(0.55)).frame(width: 3)
                VStack(alignment: .leading, spacing: nums.isEmpty ? 0 : 9) {
                    HStack(spacing: 11) {
                        RDSym("bus.fill", size: 19, color: t.primary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("NEARBY BUSES").font(rdFont(9, .heavy)).foregroundStyle(t.onVariant).kerning(0.54)
                            Text(nearStopName.isEmpty ? "Buses & stops nearby" : nearStopName)
                                .font(rdFont(14, .heavy)).foregroundStyle(t.onSurface).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if nearStopWalk > 0 {
                            Text("\(nearStopWalk) min walk")
                                .font(rdFont(11, .medium)).foregroundStyle(t.onVariant)
                        }
                        RDSym("chevron.right", size: 17, color: t.outline)
                    }
                    if !nums.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(nums.prefix(5), id: \.self) { no in
                                Text(no).font(rdFont(12.5, .heavy)).foregroundStyle(t.onSurface)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(t.scHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            if nums.count > 5 {
                                Text("+\(nums.count - 5)").font(rdFont(12, .bold)).foregroundStyle(t.onVariant)
                            }
                        }
                        .padding(.leading, 30)
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
            }
            .background(t.scLow)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.outlineVariant, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var trainNote: some View {
        HStack(spacing: 7) {
            RDSym("info.circle", size: 14, color: t.onVariant)
            Text("Showing live line status and nearby connections.")
                .font(rdFont(11.5, .medium)).foregroundStyle(t.onVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4).padding(.top, 2)
    }

    // MARK: - Interactive line strip (real — from the bundled MRT geo dataset)

    /// The ordered stations on `line`, by their numeric code (CC1, CC2, … CC29).
    private func lineSequence(_ line: MRTLine) -> [MrtGeoStation] {
        let prefix = line.rawValue
        func num(_ st: MrtGeoStation) -> Int? {
            for c in st.codes where c.hasPrefix(prefix) {
                let digits = c.dropFirst(prefix.count).prefix(while: { $0.isNumber })
                if let n = Int(digits) { return n }
            }
            return nil
        }
        return MrtGeo.all.compactMap { st in num(st).map { (st, $0) } }
            .sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    /// A horizontal, tappable strip of every station on the line, this one
    /// highlighted and centred, termini labelled — fills the screen with real,
    /// useful orientation instead of blank space. Tap a station to jump to it.
    private func lineStripCard(_ line: MRTLine) -> some View {
        let seq = lineSequence(line)
        let curID = station?.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(line.color).frame(width: 3)
                HStack(spacing: 7) {
                    Text("ON THE \(line.displayName.uppercased()) LINE")
                        .font(rdFont(9.5, .heavy)).foregroundStyle(t.onVariant).kerning(0.5)
                    Spacer()
                    Text("\(seq.count) stops").font(rdFont(10.5, .medium)).foregroundStyle(t.onVariant)
                }
                .padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 10)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // .top so every node's rail row lines up — otherwise the taller
                    // (highlighted) current node re-centres and the line zig-zags.
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(seq.enumerated()), id: \.element.id) { i, st in
                            stripNode(st, line: line, isCur: st.id == curID,
                                      first: i == 0, last: i == seq.count - 1)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .onAppear { if let curID { proxy.scrollTo(curID, anchor: .center) } }
            }
            .padding(.bottom, 12)
        }
        .background(t.scLow)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.outlineVariant, lineWidth: 1))
    }

    private func stripNode(_ st: MrtGeoStation, line: MRTLine, isCur: Bool, first: Bool, last: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Rectangle().fill(first ? Color.clear : line.color.opacity(0.5))
                    .frame(height: 3).frame(maxWidth: .infinity)
                ZStack {
                    if isCur {   // pulsing halo = "you are here" + the strip feels alive
                        Circle().fill(line.color.opacity(stripPulse ? 0 : 0.35))
                            .frame(width: stripPulse ? 30 : 15, height: stripPulse ? 30 : 15)
                    }
                    Circle().fill(isCur ? line.color : line.color.opacity(0.6))
                        .frame(width: isCur ? 14 : 9, height: isCur ? 14 : 9)
                        .overlay(Circle().stroke(t.scLow, lineWidth: isCur ? 3 : 0))
                }
                .frame(width: isCur ? 16 : 10, height: 16)
                Rectangle().fill(last ? Color.clear : line.color.opacity(0.5))
                    .frame(height: 3).frame(maxWidth: .infinity)
            }
            .frame(height: 16)
            Text(st.name)   // every station is labelled now, not just the ends
                .font(rdFont(isCur ? 10.5 : 9.5, isCur ? .heavy : .medium))
                .foregroundStyle(isCur ? t.onSurface : t.onVariant)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 58)
        }
        .frame(width: 62)
        .contentShape(Rectangle())
        .onTapGesture { if !isCur { m.openStation(named: st.name) } }
    }

    // MARK: - Honest facilities (lift outages only — we don't know the full inventory)

    @ViewBuilder private var liftCard: some View {
        if let lift = liftForStation {
            HStack(spacing: 0) {
                Rectangle().fill(t.amber).frame(width: 3)
                HStack(spacing: 11) {
                    RDSym("figure.roll", size: 19, color: t.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lift maintenance").font(rdFont(13, .heavy)).foregroundStyle(t.onSurface)
                        Text(lift.detail).font(rdFont(11, .medium)).foregroundStyle(t.onVariant).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
            }
            .background(t.amberContainer.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var liftForStation: LiftMaintenance? {
        guard let s = station else { return nil }
        return store.liftMaintenance.first {
            $0.stationName.localizedCaseInsensitiveContains(s.name)
                || s.name.localizedCaseInsensitiveContains($0.stationName)
        }
    }

    // MARK: - Nearest bus stop to this station (transfer card)

    private func computeNearestStop() {
        guard let s = station else { return }
        var bestCode: String? = nil; var bestName = ""; var bestD = Double.greatestFiniteMagnitude
        for v in store.stopByCode.values {
            let d = haversine(s.lat, s.lon, v.Latitude, v.Longitude)
            if d < bestD { bestD = d; bestCode = v.BusStopCode; bestName = v.Description }
        }
        guard let code = bestCode else { return }
        nearStopCode = code
        nearStopName = bestName
        nearStopWalk = max(1, Int((bestD / 80).rounded()))
        store.ensureArrivals(stop: code)
    }

    private var stationServiceNumbers: [String] {
        guard let code = nearStopCode else { return [] }
        var seen = Set<String>(); var out: [String] = []
        for s in store.servicesFor(code) where seen.insert(s.no).inserted {
            out.append(s.no); if out.count >= 12 { break }
        }
        return out
    }
}

// ==================================================================== ROUTE

struct RDRouteScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var app: AppModel
    @State private var route: RouteInfo?

    private var svcNo: String { m.activeService ?? "" }
    private var stopCode: String? { m.activeRouteStop }

    /// The live arrival for this bus at the anchor stop — drives the ETA and
    /// the amenity row (load / deck / wheelchair) from real LTA data.
    private var liveService: Service? {
        guard let code = stopCode else { return nil }
        return store.servicesFor(code).first { $0.no == svcNo }
    }

    private var destinationName: String {
        route?.stops.last?.name ?? liveService?.dest ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(t.outlineVariant).frame(height: 1).padding(.horizontal, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ROUTE").font(rdFont(11.5, .heavy)).kerning(0.8).foregroundStyle(t.onVariant)
                        .padding(.leading, 2).padding(.bottom, 14)
                    if let route {
                        RDRouteTimeline(m: m, t: t, route: route).padding(.leading, 8)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading route…").font(rdFont(13, .medium)).foregroundStyle(t.onVariant)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 34)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
            }
            notifyButton
        }
        .background(t.surface)
        .onAppear { reload() }
    }

    private func reload() {
        guard let code = stopCode else { return }
        store.ensureArrivals(stop: code)
        let svc = svcNo
        Task {
            let r = await store.route(service: svc, stopCode: code)
            await MainActor.run { route = r }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                RDCircleButton(symbol: "arrow.left", iconSize: 23, t: t) { m.back() }
                Spacer()
                RDCircleButton(symbol: m.routeSaved ? "bookmark.fill" : "bookmark",
                               iconColor: m.routeSaved ? t.primary : t.onVariant, iconSize: 22, t: t) { m.saveRoute() }
            }
            HStack(spacing: 7) {
                RDSym("bus.fill", size: 16, color: t.onVariant)
                Text(svcNo).font(rdFont(22, .black)).foregroundStyle(t.onSurface)
            }
            .padding(.leading, 11).padding(.trailing, 14).padding(.vertical, 6)
            .background(t.scHigh).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 10)
            // Destination + ETA share a baseline so the ETA reads as part of the
            // hero, not a floating number.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(destinationName.isEmpty ? "Route" : destinationName)
                    .font(rdFont(26, .heavy)).foregroundStyle(t.onSurface).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                // Arriving reads green ("Now"); otherwise a neutral countdown —
                // blue is reserved for interactive controls, not status.
                Group {
                    if let s = liveService, rdMinLabel(s.etaSec) == "0" {
                        Text("Now").font(rdFont(26, .black)).foregroundStyle(t.bus)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(liveService.map { rdMinLabel($0.etaSec) } ?? "—")
                                .font(rdFont(30, .black)).foregroundStyle(t.onSurface)
                                .contentTransition(.numericText())   // cross-fades 12→11 instead of jumping
                            Text("min").font(rdFont(13, .bold)).foregroundStyle(t.onVariant)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: liveService?.etaSec)
            }
            .padding(.top, 10)
            HStack(spacing: 8) {
                if let code = stopCode {
                    Text("From \(store.stopName(code))")
                        .font(rdFont(13.5, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(stopsAwayText).font(rdFont(12, .semibold)).foregroundStyle(t.onVariant)
            }
            .padding(.top, 5)
            amenities.padding(.top, 14).padding(.bottom, 14)
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    /// "N stops away" when LTA has placed the bus upstream; otherwise neutral.
    private var stopsAwayText: String {
        guard let r = route, let b = r.busIndex, b >= 0, b < r.youIndex else { return "to your stop" }
        let n = r.youIndex - b
        return n == 1 ? "1 stop away" : "\(n) stops away"
    }

    /// Amenities as compact chips on one row (occupancy keeps its semantic
    /// colour; deck / accessibility are neutral) instead of a big icon block.
    @ViewBuilder private var amenities: some View {
        if let s = liveService {
            let occ = rdOcc(rdLoad(s.load), t)
            let occShort: String = switch rdLoad(s.load) {
            case .seats: "Seats"
            case .standing: "Standing"
            case .packed: "Packed"
            }
            HStack(spacing: 8) {
                amenityChip(occ.symbol, occShort, occ.color)
                amenityChip("bus.fill", s.deck.word, t.onVariant)
                if s.wab { amenityChip("figure.roll", "Accessible", t.onVariant) }
                Spacer(minLength: 0)
            }
        }
    }

    private func amenityChip(_ symbol: String, _ label: String, _ iconColor: Color) -> some View {
        HStack(spacing: 4) {
            RDSym(symbol, size: 12, color: iconColor)
            Text(label).font(rdFont(11.5, .semibold)).foregroundStyle(t.onSurface)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(t.scHigh).clipShape(Capsule())
    }

    /// Compact floating pill — secondary by weight (most riders won't arm it
    /// every trip), lifted off the content with a soft shadow.
    /// Whether a real arrival alert is currently armed for this bus at this stop
    /// (reads the live `AppModel.alerts`, so the pill reflects true state).
    private var isAlerted: Bool {
        guard let code = stopCode else { return false }
        return app.alerts.contains { $0.kind == .arrival && $0.busNo == svcNo && $0.stopCode == code }
    }

    /// Arms/removes a real OS notification (+ Live Activity) via the app's
    /// existing arrival-alert system — no more mock in-app card.
    private func toggleNotify() {
        guard let code = stopCode else { return }
        Task { @MainActor in
            if !app.notificationsEnabled { await app.setNotificationsEnabled(true) }
            switch app.toggleArrivalAlert(busNo: svcNo, stopCode: code,
                                          stopName: store.stopName(code), dest: destinationName) {
            case .armed:   m.notify("Alert set · we’ll notify you when \(svcNo) is 1 stop away")
            case .removed: m.notify("Alert removed")
            }
        }
    }

    private var notifyButton: some View {
        let on = isAlerted
        return Button(action: { toggleNotify() }) {
            HStack(spacing: 8) {
                RDSym(on ? "bell.fill" : "bell", size: 18, color: t.onPrimary)
                Text(on ? "Notifying you" : "Notify me").font(rdFont(14.5, .bold)).foregroundStyle(t.onPrimary)
            }
            .padding(.horizontal, 32).frame(height: 54)
            .background(on ? t.bus : t.primary).clipShape(Capsule())
            .shadow(color: (on ? t.bus : t.primary).opacity(0.32), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.top, 8).padding(.bottom, 16)
    }
}
