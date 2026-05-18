// Detail — stop overview → drill into a service for a real route + map.
// All data live from LTA; the map is real MapKit.

import SwiftUI
import MapKit
import CoreLocation

struct DetailView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    let card: CardModel
    let t: Theme
    let dark: Bool
    let onClose: () -> Void

    @State private var selectedNo: String?
    @State private var alightCode: String?
    @State private var routeInfo: RouteInfo?
    @State private var routeLoading = false

    init(card: CardModel, t: Theme, dark: Bool, onClose: @escaping () -> Void) {
        self.card = card; self.t = t; self.dark = dark; self.onClose = onClose
        _selectedNo = State(initialValue: card.initialSelectedNo)
    }

    private var selected: Service? { card.services.first { $0.no == selectedNo } }
    private var enteredViaService: Bool { card.initialSelectedNo != nil }
    private var backLabel: String {
        selected != nil ? (enteredViaService ? "Back" : card.stopName) : "Close"
    }
    private func back() {
        if selected != nil && !enteredViaService { selectedNo = nil } else { onClose() }
    }
    private var arrivalState: ArrivalState { store.arrivals[card.stopCode] ?? .loading }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    if selected == nil { stopOverview } else { serviceDetail }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: selectedNo) { await loadRoute() }
    }

    private func loadRoute() async {
        guard let no = selectedNo else { routeInfo = nil; return }
        routeLoading = true
        let info = await store.route(service: no, stopCode: card.stopCode)
        let bus = await store.liveBus(service: no, stopCode: card.stopCode)
        if var ri = info {
            if let b = bus {
                let idx = ri.stops.enumerated().min(by: {
                    haversine($0.element.lat, $0.element.lon, b.latitude, b.longitude)
                        < haversine($1.element.lat, $1.element.lon, b.latitude, b.longitude)
                })?.offset
                ri.busIndex = idx
                ri.busCoord = b
            }
            routeInfo = ri
        } else {
            routeInfo = nil
        }
        routeLoading = false
    }

    // ─── Top bar ──────────────────────────────────────────
    private var topBar: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text(backLabel).lineLimit(1)
                }
                .font(t.sans(17)).foregroundStyle(t.accent)
                .frame(maxWidth: 220, alignment: .leading)
            }
            Spacer()
            Button { m.togglePinForCard(card) } label: {
                let pinned = m.isCardPinned(card)
                HStack(spacing: 6) {
                    Image(systemName: pinned ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text(pinned ? "Pinned stop" : "Pin stop")
                }
                .font(t.sans(12, weight: .medium))
                .foregroundStyle(pinned ? t.accent : t.fg)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(pinned ? t.accent.opacity(0.08) : .clear, in: Capsule())
                .overlay(Capsule().stroke(pinned ? t.accent.opacity(0.25) : t.line, lineWidth: 1))
                .contentShape(Capsule())   // whole pill tappable when unfilled
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if m.isPinned(card.stopCode) {
                    PinTag(label: card.label, t: t, onRename: { m.rename(code: card.stopCode, to: $0) })
                } else {
                    PinTag(label: card.label, t: t)
                }
                Text("· STOP \(card.stopCode)").font(t.mono(10)).tracking(1).foregroundStyle(t.dim)
            }
            Text(card.stopName).font(t.sans(26, weight: .semibold)).foregroundStyle(t.fg)
            if let s = selected {
                Text("VIEWING BUS \(s.no) → \(s.dest)")
                    .font(t.mono(12)).foregroundStyle(t.dim).padding(.top, 6)
            }
        }
        .padding(.bottom, 16)
    }

    // ─── Mode A: stop overview ────────────────────────────
    @ViewBuilder private var stopOverview: some View {
        DSection(t: t, label: "SERVICES AT THIS STOP",
                 hint: AnyView(HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill").font(.system(size: 9))
                    Text("on home")
                 }.foregroundStyle(t.dim)))

        if card.services.isEmpty {
            arrivalsPlaceholder
        } else {
            VStack(spacing: 0) {
                let allNos = card.services.map(\.no)
                let allOn = m.allTracked(code: card.stopCode)
                Button {
                    m.setAllTracked(code: card.stopCode, allNos: allNos, tracked: !allOn)
                } label: {
                    HStack {
                        Text(allOn ? "Untrack all" : "Track all")
                            .font(t.sans(13, weight: .semibold)).foregroundStyle(t.accent)
                        Spacer()
                        Text("\(allNos.filter { m.isTracked(code: card.stopCode, busNo: $0) }.count)/\(allNos.count)")
                            .font(t.mono(11)).foregroundStyle(t.dim)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(t.line)

                ForEach(Array(card.services.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider().overlay(t.line) }
                    ServiceTapRow(
                        s: s, t: t,
                        tracked: m.isTracked(code: card.stopCode, busNo: s.no),
                        onTap: { selectedNo = s.no },
                        onToggleTrack: {
                            m.toggleTracked(code: card.stopCode, busNo: s.no,
                                            allNos: card.services.map(\.no))
                        }
                    )
                }
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.line, lineWidth: 1))
            .padding(.bottom, 8)

            (Text("Tap ") + Text(Image(systemName: "bookmark"))
             + Text(" on a row to add/remove that bus from your Home view."))
                .font(t.mono(11)).foregroundStyle(t.dim).lineSpacing(1.5)
                .padding(.bottom, 14)

            notifyCard
        }
    }

    @ViewBuilder private var arrivalsPlaceholder: some View {
        Group {
            switch arrivalState {
            case .loading:
                HStack { ProgressView().tint(t.dim)
                    Text("Loading live arrivals…").font(t.sans(12)).foregroundStyle(t.dim) }
            case .empty:
                Text("No buses running here right now").font(t.sans(13)).foregroundStyle(t.dim)
            case .error(let msg):
                VStack(spacing: 6) {
                    Text("Couldn’t load arrivals").font(t.sans(13, weight: .medium)).foregroundStyle(t.fg)
                    Text(msg).font(t.sans(11)).foregroundStyle(t.dim)
                    Button { store.ensureArrivals(stop: card.stopCode, force: true) } label: {
                        Text("Retry").font(t.sans(12, weight: .medium)).foregroundStyle(t.bg)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(t.accent, in: Capsule())
                    }.buttonStyle(.plain)
                }
            case .loaded:
                Text("No buses running here right now").font(t.sans(13)).foregroundStyle(t.dim)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var notifyCard: some View {
        let nos = card.services.map(\.no).filter { m.isTracked(code: card.stopCode, busNo: $0) }
        let enabled = !nos.isEmpty && m.isPinned(card.stopCode)
        let title: String = !enabled ? "Pin a bus to enable arrival alerts"
            : (nos.count == 1 ? "Notify me when Bus \(nos[0]) is 2 min away"
               : "Notify me 2 min before arrival")
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(t.accent.opacity(0.13))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "bell").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(t.sans(13, weight: .medium)).foregroundStyle(t.fg)
                if enabled && nos.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(nos.prefix(4), id: \.self) { no in
                            Text(no).font(t.mono(10, weight: .bold))
                                .foregroundStyle(t.accent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(t.accent.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(t.accent.opacity(0.19), lineWidth: 1))
                        }
                        if nos.count > 4 { Text("+\(nos.count - 4)").font(t.mono(10)).foregroundStyle(t.dim) }
                    }
                } else {
                    Text(enabled ? "We'll buzz so you don't keep checking your phone"
                         : "Pin this stop to get arrival alerts")
                        .font(t.sans(11)).foregroundStyle(t.dim)
                }
            }
            Spacer(minLength: 0)
            TogglePill(on: enabled, t: t)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
        .opacity(enabled ? 1 : 0.55)
    }

    // ─── Mode B: service drill-in ─────────────────────────
    @ViewBuilder private var serviceDetail: some View {
        if let s = selected {
            let eta = fmtETA(s.etaSec)
            heroCard(s: s, eta: eta)

            Button {
                m.startLiveActivity(s, stopName: card.stopName, stopCode: card.stopCode)
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8).fill(t.bg.opacity(0.13))
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: "lock.rectangle").font(.system(size: 14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Start Live Activity").font(t.sans(15, weight: .semibold))
                            Text("Follow Bus \(s.no) from your lock screen")
                                .font(t.sans(11)).opacity(0.65)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(t.bg)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(t.fg, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)

            DSection(t: t, label: "LIVE MAP", hint: routeInfo?.busCoord == nil
                     ? AnyView(Text("BUS GPS UNAVAILABLE").font(t.mono(10)).foregroundStyle(t.dim))
                     : nil)
            RouteMapView(t: t, dark: dark, route: routeInfo, busNo: s.no, loading: routeLoading)
                .padding(.bottom, 18)

            if let ri = routeInfo {
                let away = ri.busIndex.map { abs(ri.youIndex - $0) }
                DSection(t: t, label: "ROUTE PROGRESS",
                         hint: away.map { AnyView(Text("\($0) STOPS AWAY")
                            .font(t.mono(10)).foregroundStyle(t.dim)) })
                RouteProgress(t: t, busNo: s.no, route: ri, alightCode: $alightCode)
                    .padding(.bottom, 18)
                onBusAlertCard(ri)
            } else if routeLoading {
                DSection(t: t, label: "ROUTE PROGRESS", hint: nil)
                HStack { ProgressView().tint(t.dim)
                    Text("Loading route…").font(t.sans(12)).foregroundStyle(t.dim) }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func heroCard(s: Service, eta: ETA) -> some View {
        let now = Date()
        let follows: [Int] = [s.followingDate, s.thirdDate].compactMap { d in
            d.map { max(0, Int($0.timeIntervalSince(now)) / 60) }
        }
        return VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(s.no).font(t.mono(24, weight: .bold)).foregroundStyle(t.fg)
                        Text("→ \(s.dest)").font(t.sans(12)).foregroundStyle(t.dim).lineLimit(1)
                    }
                    Text("NEXT ARRIVAL").font(t.mono(11)).foregroundStyle(t.dim)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(eta.big)
                        .font(t.mono(eta.big == "Arr" ? 44 : 64, weight: .light))
                        .foregroundStyle(s.load.color(t))
                    Text(eta.small).font(t.mono(16)).foregroundStyle(t.dim)
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)

            if !follows.isEmpty {
                HStack(spacing: 14) {
                    Text("FOLLOWING").font(t.mono(10)).foregroundStyle(t.dim)
                    HStack(spacing: 14) {
                        ForEach(Array(follows.enumerated()), id: \.offset) { i, mins in
                            if i > 0 { Text("·").foregroundStyle(t.line) }
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(mins)").font(t.mono(18, weight: .medium)).foregroundStyle(t.fg)
                                Text("min").font(t.mono(10)).foregroundStyle(t.dim)
                            }
                            .opacity(1 - Double(i) * 0.22)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .overlay(alignment: .top) { Divider().overlay(t.line).padding(.horizontal, 20) }
            }
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(t.line, lineWidth: 1))
        .padding(.bottom, 16)
    }

    private func onBusAlertCard(_ ri: RouteInfo) -> some View {
        let alightIdx = ri.stops.firstIndex { $0.code == alightCode }
        let alightName = alightIdx.map { ri.stops[$0].name }
        let enabled = alightIdx != nil
        let base = ri.busIndex ?? ri.youIndex
        let stopsToAlight = (alightIdx.map { $0 - base } ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            DSection(t: t, label: "ON-BUS ALERT", hint: nil)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(t.accent.opacity(0.13))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "figure.walk.departure")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(enabled ? "Buzz me 2 stops before \(alightName!)"
                         : "Riding this bus? Pick where to alight")
                        .font(t.sans(13, weight: .medium)).foregroundStyle(t.fg)
                    Text(enabled
                         ? "\(max(0, stopsToAlight)) stop\(stopsToAlight == 1 ? "" : "s") until arrival · so you don't miss it"
                         : "Tap a stop below to set as your destination")
                        .font(t.sans(11)).foregroundStyle(t.dim)
                }
                Spacer(minLength: 0)
                TogglePill(on: enabled, t: t)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
            .opacity(enabled ? 1 : 0.65)
        }
    }
}

// ─── Real MapKit route map ────────────────────────────────
struct RouteMapView: View {
    let t: Theme
    let dark: Bool
    let route: RouteInfo?
    let busNo: String
    let loading: Bool

    @EnvironmentObject private var loc: LocationManager

    // Frame just the three points we show: your stop, the live bus, and you.
    private func region(_ r: RouteInfo) -> MKCoordinateRegion {
        let you = r.stops[min(max(r.youIndex, 0), r.stops.count - 1)]
        var lats = [you.lat], lons = [you.lon]
        if let b = r.busCoord { lats.append(b.latitude); lons.append(b.longitude) }
        if let me = loc.location?.coordinate { lats.append(me.latitude); lons.append(me.longitude) }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.6),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.6)))
    }

    var body: some View {
        ZStack {
            if let r = route, !r.stops.isEmpty {
                let youStop = r.stops[min(max(r.youIndex, 0), r.stops.count - 1)]
                Map(initialPosition: .region(region(r))) {
                    // Your bus stop
                    Annotation("", coordinate: .init(latitude: youStop.lat, longitude: youStop.lon)) {
                        VStack(spacing: 2) {
                            Image(systemName: "bus.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(t.accent, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            Text("STOP").font(t.mono(8, weight: .bold)).tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(t.accent, in: Capsule())
                        }
                    }
                    // Live bus position
                    if let b = r.busCoord {
                        Annotation("", coordinate: b) {
                            Text(busNo)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(t.live, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5))
                                .shadow(color: t.live.opacity(0.7), radius: 6)
                        }
                    }
                    // Me — real device location (system blue dot)
                    UserAnnotation()
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        legend(t.live, "BUS \(busNo)")
                        legend(t.accent, "STOP")
                        legend(Color(hex: "1E7BFF"), "ME")
                    }.padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(r.busCoord == nil ? "LIVE · LTA · NO BUS GPS" : "LIVE · LTA")
                        .font(t.mono(9)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(10)
                }
            } else {
                ZStack {
                    (dark ? Color(hex: "0f0f0d") : Color(hex: "EEEBE4"))
                    VStack(spacing: 8) {
                        if loading { ProgressView().tint(t.dim) }
                        Text(loading ? "Loading route…" : "Route unavailable")
                            .font(t.sans(12)).foregroundStyle(t.dim)
                    }
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.line, lineWidth: 1))
    }

    private func legend(_ dot: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text).font(t.mono(9)).foregroundStyle(t.dim).fixedSize()
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(t.surface, in: Capsule())
        .overlay(Capsule().stroke(t.line, lineWidth: 1))
    }
}

// ─── Helpers ──────────────────────────────────────────────
struct DSection: View {
    let t: Theme
    let label: String
    let hint: AnyView?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(t.mono(11)).tracking(1).foregroundStyle(t.dim)
            Spacer()
            if let hint { hint }
        }
        .padding(.horizontal, 4).padding(.bottom, 6)
    }
}

struct TogglePill: View {
    let on: Bool
    let t: Theme
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? t.accent : t.line).frame(width: 44, height: 26)
            Circle().fill(.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.2), radius: 1.5)
                .padding(.horizontal, 2)
        }
        .opacity(on ? 1 : 0.6)
    }
}

struct ServiceTapRow: View {
    let s: Service
    let t: Theme
    let tracked: Bool
    let onTap: () -> Void
    let onToggleTrack: () -> Void

    var body: some View {
        let eta = fmtETA(s.etaSec)
        let eta2 = fmtETA(s.followingSec)
        let arriving = eta.live
        HStack(spacing: 12) {
            Button(action: onToggleTrack) {
                ZStack {
                    Circle()
                        .fill(tracked ? t.accent : .clear)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(tracked ? t.accent : t.line, lineWidth: 1.5))
                    if tracked {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                HStack(spacing: 14) {
                    Text(s.no).font(t.mono(20, weight: .bold)).foregroundStyle(t.fg)
                        .frame(minWidth: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.dest).font(t.sans(14, weight: .medium))
                            .foregroundStyle(t.fg).lineLimit(1)
                        HStack(spacing: 8) {
                            LoadDotLabel(load: s.load, t: t, dotSize: 6, fontSize: 11)
                            if !s.wab {
                                Text("·").foregroundStyle(t.line)
                                HStack(spacing: 4) {
                                    StepUpGlyph(color: t.crit, size: 11)
                                    Text("Step-up").font(t.mono(10))
                                }.foregroundStyle(t.crit)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(eta.big)
                                .font(t.mono(eta.big == "Arr" ? 22 : 30, weight: .medium))
                                .foregroundStyle(arriving ? t.live : t.fg)
                            Text(eta.small).font(t.mono(11)).foregroundStyle(t.dim)
                        }
                        Text("then \(eta2.big)\(eta2.big == "Arr" ? "" : "m")")
                            .font(t.mono(10)).foregroundStyle(t.dim)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(arriving ? t.liveBg : .clear)
        .overlay(alignment: .leading) {
            if arriving { Capsule().fill(t.live).frame(width: 3).padding(.vertical, 8) }
        }
        .opacity(tracked ? 1 : 0.55)
    }
}

struct RouteProgress: View {
    let t: Theme
    let busNo: String
    let route: RouteInfo
    @Binding var alightCode: String?

    /// Focus window: a bit before the bus → a few beyond your stop.
    private var window: [(idx: Int, stop: RouteStopLive)] {
        let base = route.busIndex ?? route.youIndex
        let lo = max(0, min(base, route.youIndex) - 1)
        let hi = min(route.stops.count - 1, max(base, route.youIndex) + 5)
        return (lo...hi).map { ($0, route.stops[$0]) }
    }

    var body: some View {
        let busIdx = route.busIndex ?? -1
        VStack(spacing: 0) {
            ForEach(window, id: \.idx) { entry in
                let i = entry.idx
                let stop = entry.stop
                let isYou = i == route.youIndex
                let isBus = i == busIdx
                let isAlight = alightCode == stop.code
                let passed = busIdx >= 0 && i < busIdx
                let canAlight = i > max(busIdx, 0) && !isYou
                HStack(spacing: 12) {
                    ZStack {
                        VStack(spacing: 0) {
                            Rectangle().fill(passed ? t.dim : t.line).frame(width: 2)
                            Rectangle().fill(i < busIdx ? t.dim : t.line).frame(width: 2)
                        }
                        Circle()
                            .fill(isAlight ? t.accent : (isYou ? t.accent : (passed ? t.dim : t.surface)))
                            .frame(width: isYou || isAlight ? 12 : 8, height: isYou || isAlight ? 12 : 8)
                            .overlay(Circle().stroke(t.fg,
                                lineWidth: (!isYou && !isAlight && !passed) ? 2 : 0))
                    }
                    .frame(width: 18).frame(maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop.name)
                            .font(t.sans(14, weight: isYou || isBus || isAlight ? .semibold : .regular))
                            .foregroundStyle(t.fg).lineLimit(1)
                        Text(stop.code
                             + (isYou ? " · YOUR STOP" : "")
                             + (isBus ? " · BUS HERE NOW" : "")
                             + (isAlight ? " · ALIGHT HERE" : ""))
                            .font(t.mono(10)).foregroundStyle(t.dim)
                    }
                    Spacer(minLength: 0)

                    if isBus {
                        Text("BUS \(busNo)").font(t.mono(10, weight: .semibold)).tracking(0.5)
                            .foregroundStyle(t.live)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(t.liveBg, in: Capsule())
                            .overlay(Capsule().stroke(t.live, lineWidth: 1))
                    } else if isAlight {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk.departure").font(.system(size: 9, weight: .bold))
                            Text("ALIGHT")
                        }
                        .font(t.mono(10, weight: .semibold)).tracking(0.5).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(t.accent, in: Capsule())
                    } else if canAlight {
                        Text("tap to alight").font(t.mono(9)).foregroundStyle(t.dim.opacity(0.6))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(isAlight ? t.accent.opacity(0.07) : .clear)
                .opacity(passed ? 0.45 : 1)
                .contentShape(Rectangle())
                .onTapGesture { if canAlight { alightCode = isAlight ? nil : stop.code } }
            }
        }
        .padding(.vertical, 14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.line, lineWidth: 1))
    }
}
