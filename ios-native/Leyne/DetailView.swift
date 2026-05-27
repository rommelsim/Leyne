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
    @State private var routeInfo: RouteInfo?
    @State private var routeLoading = false

    /// Active alight code FOR THE CURRENTLY SELECTED SERVICE. nil unless
    /// the user has armed an alight alert on this exact bus. Reads from
    /// `AppModel.activeAlight` — one ride at a time, app-wide — and
    /// filters to this bus so a different DetailView doesn't accidentally
    /// show the picker as selected.
    private var alightCode: String? {
        guard let a = m.activeAlight, a.busNo == selectedNo else { return nil }
        return a.stopCode
    }

    /// Two-way binding for `RouteProgress`. Setter computes the predicted
    /// "2 stops before alight" fire time from the live RouteInfo (`busIndex`
    /// or `youIndex` as the starting reference, 90 s per route segment as
    /// the cruder-but-acceptable MVP estimate) and arms the alert via
    /// `AppModel.setActiveAlight`. Untap clears the ride and cancels the
    /// pending notification.
    private var alightBinding: Binding<String?> {
        Binding(
            get: { self.alightCode },
            set: { newValue in
                guard let busNo = self.selectedNo else { return }
                guard let route = self.routeInfo else { return }
                if let code = newValue,
                   let alightIdx = route.stops.firstIndex(where: { $0.code == code }) {
                    let stop = route.stops[alightIdx]
                    let base = route.busIndex ?? route.youIndex
                    let stopsToAlight = max(0, alightIdx - base)
                    // Want the heads-up at 2 stops out → wait for the bus
                    // to cross `stopsToAlight - 2` more stops. 90 s avg
                    // per stop is the MVP estimate; refines naturally
                    // when the bus's live position updates and the user
                    // re-opens DetailView (we re-arm on re-set).
                    let stopsToWait = max(0, stopsToAlight - 2)
                    let fireAt = Date().addingTimeInterval(
                        TimeInterval(stopsToWait) * 90)
                    m.setActiveAlight(busNo: busNo, stopCode: code,
                                      stopName: stop.name, fireAt: fireAt)
                } else {
                    m.clearActiveAlight()
                }
            }
        )
    }

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

    /// Coordinate for the visible stop, sourced from the reference dataset.
    /// Returns nil only while DataStore is still bootstrapping; otherwise
    /// it lets RouteMapView render a stop+me fallback map even when route
    /// data is missing.
    private func stopByCode(_ code: String) -> CLLocationCoordinate2D? {
        guard let s = store.stopByCode[code] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

    var body: some View {
        // ZStack with t.bg as the bottom-most layer guarantees the cream
        // background fills the full screen (including behind the status
        // bar) BEFORE the glass top bar paints over it. The earlier
        // `.background(t.bg.ignoresSafeArea())` modifier on a bare VStack
        // didn't always extend behind the status bar when DetailView was
        // hosted inside DetailPager's TabView — the page-style TabView's
        // internal safe-area handling clipped the VStack's frame, so the
        // top safe area stayed transparent and HomeView bled through.
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

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
        }
        // Push-from-right reads as hierarchical drill-down (the iOS-native
        // vocabulary for "you're now one level deeper"), not as a modal
        // sheet rising. Pure slide (no opacity fade) — UIKit's
        // UINavigationController push doesn't fade either, and the
        // combined opacity made the dismiss feel mushy rather than crisp.
        .transition(.move(edge: .trailing))
        .task(id: selectedNo) { await loadRoute() }
    }

    private func loadRoute() async {
        guard let no = selectedNo else { routeInfo = nil; return }
        routeLoading = true
        defer { routeLoading = false }

        // First attempt. The common failure on a cold launch is that the
        // LTA routes dataset (~10k+ entries) hasn't finished loading yet
        // and store.route returns nil. Without a retry the user has to
        // back out of DetailView and re-tap the bus to retry — silently
        // confusing. Two staggered retries cover the typical bootstrap
        // window (~3–5s) without spamming requests.
        var info = await store.route(service: no, stopCode: card.stopCode)
        if info == nil {
            for delay in [1.5, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                // Bail if the user moved to a different service while we
                // were waiting — let the next .task(id:) run own it.
                guard selectedNo == no else { return }
                info = await store.route(service: no, stopCode: card.stopCode)
                if info != nil { break }
            }
        }

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
        // No background — native iOS chrome doesn't paint a material at
        // scroll-zero (the bar is transparent until content scrolls
        // underneath it). The previous `.background(t.glassSurface())`
        // produced a visible band between the safe area and the page
        // below because no content was scrolled beneath the static
        // material. The buttons read fine directly on t.bg.
    }

    private var heading: some View {
        // Title-as-label design: the big bold title IS the user's editable
        // label (defaults to the official stop name). When they rename it,
        // the official stop name surfaces as a secondary subtitle —
        // progressive disclosure, one name in one place. The pencil glyph
        // beside the title is the rename affordance. Walk-minutes move
        // here from the micro meta row since they belong with location
        // context, not buried in the breadcrumb.
        let hasNickname = card.label != card.stopName
        let canRename = m.isPinned(card.stopCode)
        return VStack(alignment: .leading, spacing: 4) {
            Text("STOP \(card.stopCode)")
                .font(t.mono(10)).tracking(1).foregroundStyle(t.dim)
                .padding(.bottom, 2)

            EditableTitle(
                label: card.label,
                canEdit: canRename,
                t: t,
                onRename: { m.rename(code: card.stopCode, to: $0) }
            )

            if hasNickname {
                Text(card.stopName)
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .padding(.top, 1)
            }

            if card.walkMin > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(card.walkMin) min walk").font(t.mono(11))
                }
                .foregroundStyle(t.dim)
                .padding(.top, 4)
            }

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
            .background(t.glassSurface())
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
        .background(t.glassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
        .opacity(enabled ? 1 : 0.55)
    }

    // ─── Mode B: service drill-in ─────────────────────────
    @ViewBuilder private var serviceDetail: some View {
        if let s = selected {
            let eta = fmtETA(s.etaSec)
            heroCard(s: s, eta: eta)

            let liveOn = m.isLiveActivityActive(s, stopCode: card.stopCode)
            Button {
                m.toggleLiveActivity(s, stopName: card.stopName, stopCode: card.stopCode)
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill((liveOn ? t.fg : t.bg).opacity(0.13))
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: liveOn ? "stop.fill" : "lock.rectangle")
                                .font(.system(size: 14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(liveOn ? "Stop Live Activity" : "Start Live Activity")
                                .font(t.sans(15, weight: .semibold))
                            Text(liveOn ? "Bus \(s.no) is on your lock screen"
                                        : "Follow Bus \(s.no) from your lock screen")
                                .font(t.sans(11)).opacity(0.65)
                        }
                    }
                    Spacer()
                    Image(systemName: liveOn ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(liveOn ? t.fg : t.bg)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(liveOn ? t.surface : t.fg, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(t.fg, lineWidth: liveOn ? 1.5 : 0))
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: liveOn)
            .padding(.bottom, 18)

            DSection(t: t, label: "LIVE MAP", hint: routeInfo?.busCoord == nil
                     ? AnyView(Text("BUS GPS UNAVAILABLE").font(t.mono(10)).foregroundStyle(t.dim))
                     : nil)
            RouteMapView(t: t, dark: dark, route: routeInfo, busNo: s.no,
                         loading: routeLoading,
                         fallbackStopCoord: stopByCode(card.stopCode))
                .padding(.bottom, 18)

            if let ri = routeInfo {
                let away = ri.busIndex.map { abs(ri.youIndex - $0) }
                DSection(t: t, label: "ROUTE PROGRESS",
                         hint: away.map { AnyView(Text("\($0) STOPS AWAY")
                            .font(t.mono(10)).foregroundStyle(t.dim)) })
                RouteProgress(t: t, busNo: s.no, route: ri, alightCode: alightBinding)
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
        .background(t.glassSurface())
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
            .background(t.glassSurface())
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
    /// Coordinate of the stop being viewed, sourced by DetailView from
    /// `DataStore.stopByCode`. Lets us render a degraded "stop + me"
    /// map even when route data isn't available — every bus drill-in
    /// gets a map, never a gray "Route unavailable" placeholder.
    var fallbackStopCoord: CLLocationCoordinate2D? = nil

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

    /// Region for the degraded fallback map — centers on the stop and, if
    /// available, expands to include the user's current position.
    private func fallbackRegion(stop: CLLocationCoordinate2D) -> MKCoordinateRegion {
        var lats = [stop.latitude], lons = [stop.longitude]
        if let me = loc.location?.coordinate {
            lats.append(me.latitude); lons.append(me.longitude)
        }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.005, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.005, (maxLon - minLon) * 1.8)))
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
                    // Me — real device location. We draw an explicit blue dot
                    // because `UserAnnotation()` inherits the app accent in
                    // some MapKit builds, rendering as mint/brown rather than
                    // the system locator blue.
                    if let me = loc.location?.coordinate {
                        Annotation("", coordinate: me) {
                            ZStack {
                                Circle().fill(Color(hex: "1E7BFF").opacity(0.22))
                                    .frame(width: 28, height: 28)
                                Circle().fill(Color(hex: "1E7BFF"))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            }
                        }
                    }
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
            } else if let coord = fallbackStopCoord {
                // Degraded map — no route line, no bus pin, but the stop
                // and the user's position are always informative. Every
                // bus drill-in lands here when LTA route data is missing,
                // rather than on a gray "Route unavailable" placeholder.
                Map(initialPosition: .region(fallbackRegion(stop: coord))) {
                    Annotation("", coordinate: coord) {
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
                    if let me = loc.location?.coordinate {
                        Annotation("", coordinate: me) {
                            ZStack {
                                Circle().fill(Color(hex: "1E7BFF").opacity(0.22))
                                    .frame(width: 28, height: 28)
                                Circle().fill(Color(hex: "1E7BFF"))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        legend(t.accent, "STOP")
                        legend(Color(hex: "1E7BFF"), "ME")
                    }.padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(loading ? "LIVE · LTA · ROUTE LOADING" : "LIVE · LTA · ROUTE DATA UNAVAILABLE")
                        .font(t.mono(9)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(10)
                }
            } else {
                // Last-resort fallback for the rare case where even the
                // stop coordinate isn't known yet (DataStore.stopByCode
                // still loading on a cold launch with no network cache).
                ZStack {
                    (dark ? Color(hex: "0f0f0d") : Color(hex: "EEEBE4"))
                    VStack(spacing: 8) {
                        ProgressView().tint(t.dim)
                        Text("Loading map…")
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
            .buttonStyle(PressableRowStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(arriving ? t.liveBg : .clear)
        .overlay(alignment: .leading) {
            if arriving { ArrivingPill(t: t) }
            else { OperatorStripe(op: s.op, t: t) }
        }
        .opacity(tracked ? 1 : 0.55)
    }
}

struct RouteProgress: View {
    let t: Theme
    let busNo: String
    let route: RouteInfo
    @Binding var alightCode: String?

    /// When true, the card swaps from the focused window to the full
    /// route list. Driven by the "Show all N stops" expander pinned at
    /// the bottom of the card; collapses back to the window on tap.
    @State private var showAll = false

    /// Focus window: a bit before the bus → a few beyond your stop,
    /// auto-extended to cover the alight stop if one is set further
    /// down the route (so the user can always see what they picked).
    /// When `showAll` is true, every stop in the route is returned —
    /// the user has opted into seeing the whole journey.
    private var window: [(idx: Int, stop: RouteStopLive)] {
        if showAll {
            return route.stops.enumerated().map { ($0, $1) }
        }
        let base = route.busIndex ?? route.youIndex
        let lo = max(0, min(base, route.youIndex) - 1)
        var hi = min(route.stops.count - 1, max(base, route.youIndex) + 5)
        // Pull the alight stop into view when it sits past the default
        // window upper bound. Cap so we don't accidentally render every
        // stop on long routes — the expander handles the "show me
        // everything" case.
        if let code = alightCode,
           let alightIdx = route.stops.firstIndex(where: { $0.code == code }),
           alightIdx > hi {
            hi = min(route.stops.count - 1, alightIdx + 1)
        }
        return (lo...hi).map { ($0, route.stops[$0]) }
    }

    /// True when the focused window omits at least one stop — the
    /// expander only matters in that case.
    private var hasHiddenStops: Bool {
        if showAll { return false }
        return window.count < route.stops.count
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

            if hasHiddenStops || showAll {
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { showAll.toggle() }
                    Feedback.shared.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showAll
                             ? "Show focused view"
                             : "Show all \(route.stops.count) stops")
                            .font(t.mono(11, weight: .medium))
                            .tracking(0.4)
                    }
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    Divider().overlay(t.line).padding(.horizontal, 18)
                }
            }
        }
        .padding(.vertical, 14)
        .background(t.glassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.line, lineWidth: 1))
    }
}

// MARK: - DetailPager

/// Horizontal-page wrapper around DetailView. Lets the user swipe between
/// pinned stops without backing out to Home — the iOS-native pattern for
/// peer-to-peer navigation across a small list (Mail's mail viewer, Photos'
/// photo viewer, Reminders' lists). Each page is identified by stopCode so
/// per-stop state (selected service, alightCode, routeInfo) is preserved
/// across page swipes for the lifetime of the pager.
///
/// Only mounted when the opened stop is pinned AND there is more than one
/// pin — a singleton list has nothing to swipe between, so RootView falls
/// back to a plain DetailView and avoids the TabView overhead.
struct DetailPager: View {
    @EnvironmentObject var m: AppModel
    let initialStopCode: String
    let initialBusNo: String?
    let t: Theme
    let dark: Bool
    let onClose: () -> Void

    @State private var selection: String
    /// First-run discoverability — the swipe gesture is invisible until
    /// you try it. A small "‹ swipe ›" chip pulses in just below the top
    /// bar the very first time the pager opens, dismisses on the first
    /// swipe or after a ~5-second timeout, then never appears again.
    @AppStorage("leyne.pager.hint.shown") private var hintShown = false
    @State private var hintVisible = false

    init(initialStopCode: String, initialBusNo: String?,
         t: Theme, dark: Bool, onClose: @escaping () -> Void) {
        self.initialStopCode = initialStopCode
        self.initialBusNo = initialBusNo
        self.t = t; self.dark = dark; self.onClose = onClose
        _selection = State(initialValue: initialStopCode)
    }

    var body: some View {
        // ZStack with t.bg below the TabView ensures the pager is opaque
        // and fills the full screen including all safe areas. Without
        // this:
        //   • Bottom bleed: the page-style TabView leaves a few points of
        //     transparent space under each page that revealed the root
        //     TabView's tab bar / Nearby content.
        //   • Over-swipe bleed: swiping past the first or last page lets
        //     the underlying RootView ZStack peek through, which is how
        //     the Nearby tab was becoming visible.
        // A solid cream layer behind the TabView absorbs both cases.
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(m.allPinnedCards, id: \.stopCode) { card in
                    DetailView(
                        card: cardForPage(card),
                        t: t, dark: dark, onClose: onClose
                    )
                    .tag(card.stopCode)
                }
            }
            // No index dots — the DetailView heading already shows the
            // stop name + code on every page, so position is unambiguous.
            .tabViewStyle(.page(indexDisplayMode: .never))

            // First-run swipe-discoverability hint. Floats just below the
            // glass top bar with a pulsing accent so the user notices it,
            // dismisses on first swipe (selection change) or after a few
            // seconds. AppStorage flag prevents it from ever showing again.
            if hintVisible {
                swipeHint
                    .padding(.top, 60)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
        }
        // Match the standalone DetailView transition so the pager and a
        // single page enter/exit identically.
        .transition(.move(edge: .trailing))
        // If the user unpins the currently-visible stop (via DetailView's
        // pin toggle), the page disappears from the underlying ForEach.
        // Close the pager rather than letting TabView strand the selection.
        .onChange(of: m.pins.map(\.code)) { _, codes in
            if !codes.contains(selection) { onClose() }
        }
        // First swipe → dismiss the hint immediately (it served its purpose).
        .onChange(of: selection) { _, _ in
            if hintVisible { dismissHint() }
        }
        .task {
            // Run only on first pager open across the user's install.
            guard !hintShown else { return }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.35)) { hintVisible = true }
            try? await Task.sleep(for: .seconds(5))
            if hintVisible { dismissHint() }
        }
    }

    /// The hint chip — two chevrons flanking a "swipe" label, mint accent
    /// with a soft glass background so it reads as a piece of system UI
    /// rather than a banner. Subtle horizontal pulse hints at the gesture.
    private var swipeHint: some View {
        SwipeHintPill(t: t)
    }

    private func dismissHint() {
        withAnimation(.easeIn(duration: 0.3)) { hintVisible = false }
        hintShown = true
    }

    /// Only the initially-tapped page inherits the busNo the user tapped
    /// on the source card. Sibling pages start at their own stop overview
    /// — opening one stop and swiping over shouldn't auto-drill into a
    /// different stop's service.
    private func cardForPage(_ card: CardModel) -> CardModel {
        var c = card
        c.initialSelectedNo = (card.stopCode == initialStopCode) ? initialBusNo : nil
        return c
    }
}

/// Big editable title for the DetailView heading. Tapping the title (or
/// the pencil glyph beside it) swaps into a TextField bound to the same
/// label. Submit / blur commits via `onRename`. Pencil shows only when
/// the stop is pinned — non-pinned stops can't be renamed because there's
/// no Pin to store the nickname on.
struct EditableTitle: View {
    let label: String
    let canEdit: Bool
    let t: Theme
    let onRename: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if editing {
                TextField("", text: $draft)
                    .focused($focused)
                    .font(t.sans(26, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    .fixedSize()
            } else {
                Text(label)
                    .font(t.sans(26, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(2)
                if canEdit {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(t.dim.opacity(0.65))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard canEdit, !editing else { return }
            draft = label
            editing = true
            focused = true
        }
    }

    private func commit() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, v != label { onRename(v) }
        editing = false
    }
}

/// First-run hint chip for the DetailPager swipe gesture. A chevron on
/// each side with the word "swipe" in between, on a faint mint-tinted
/// glass background — reads as a piece of system UI, not a banner. The
/// chevrons gently pulse horizontally to hint at the gesture direction.
private struct SwipeHintPill: View {
    let t: Theme
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.compact.left")
                .font(.system(size: 14, weight: .semibold))
                .offset(x: pulse ? -3 : 0)
            Text("swipe between stops")
                .font(t.mono(11, weight: .medium))
                .tracking(0.6)
            Image(systemName: "chevron.compact.right")
                .font(.system(size: 14, weight: .semibold))
                .offset(x: pulse ? 3 : 0)
        }
        .foregroundStyle(t.accent)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(t.accent.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(t.accent.opacity(0.3), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
