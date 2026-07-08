// WhereSia — Home · Nearby (screen 1).
//
// Date eyebrow + title, search bar, then one scroll in answer-first order:
// the CLOSEST STOP hero card (stop name, walk line, live ETA chips — the
// next five minutes at that stop), a horizontal strip of nearby MRT
// stations, then the remaining nearby bus stops. Hero chips carry live
// times ("48 · Now", "93 · 4 min", soonest first) with a width-computed +N
// overflow; green is reserved for a bus arriving this minute (fully neutral
// card otherwise) — owner spec 2026-07-07 (home-hero-redesign).

import SwiftUI
import CoreLocation
import MapKit

struct WSHomeView: View {
    var onSearch: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.scenePhase) private var scenePhase

    private var coord: CLLocationCoordinate2D? { location.location?.coordinate }

    private var nearbyStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] {
        guard let c = coord else { return [] }
        return MrtGeo.nearestStations(to: c, limit: 4)
    }

    var body: some View {
        let _ = m.tick   // per-second live countdown refresh
        VStack(spacing: 0) {
            header
            searchBar

            ScrollView {
                // Minimal, answer-first Home (owner decision 2026-07-07):
                // ONLY the closest stop, the nearest station, and the map
                // door. Everything else nearby lives behind the map.
                LazyVStack(spacing: 0) {
                    heroSection
                    nearestMrtSection
                    mapCard
                    // One native ad per board — below the door card, so the
                    // minimal screen keeps its Home impression. Renders
                    // nothing until a creative loads.
                    NativeAdCard()
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                    emptyStateOrFooter
                    Color.clear.frame(height: 24)
                }
            }
            .wsEntrance()
        }
        .background(ws.bg)
        .onAppear(perform: bootstrap)
        .onChange(of: location.location) { _, loc in
            if let loc { store.updateNearby(loc); store.prefetchNearbyArrivals() }
            store.wsWarmCrowd(for: nearbyStations.map(\.station))
        }
        // Nearby rows otherwise only refresh on a location change — sit
        // still and they go stale. The freshness window inside
        // ensureArrivals turns this into an actual fetch ~every 25s.
        .onChange(of: m.tick) { _, _ in store.prefetchNearbyArrivals() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A launch-time bootstrap failure shouldn't outlive a trip
                // to the background — retry quietly on return.
                if case .error = store.referenceState {
                    Task { await store.bootstrap() }
                }
                store.prefetchNearbyArrivals()
                store.wsWarmCrowd(for: nearbyStations.map(\.station))
            }
        }
    }

    private func bootstrap() {
        // Returning to Home after a failed launch bootstrap retries it.
        if case .error = store.referenceState {
            Task { await store.bootstrap() }
        }
        location.start()
        // Home renders UNDERNEATH the onboarding overlay (RootView ZStack), so
        // its onAppear runs on first launch too — requesting here fired the
        // system location dialog over the WELCOME step, before the primer
        // (owner-reported; also an App Store 5.1.1(iv) risk). During
        // onboarding, the location primer owns the request.
        if location.status == .notDetermined && !m.showOnboarding {
            location.requestPermission()
        }
        if let loc = location.location { store.updateNearby(loc) }
        store.ensureRoutes()
        store.prefetchNearbyArrivals()
        store.wsWarmCrowd(for: nearbyStations.map(\.station))
    }

    // MARK: header

    /// Departure-board eyebrow: the live date, not a brand lockup — the brand
    /// lives on the app icon; this line earns its place by being useful.
    private static let dateEyebrow: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_SG")
        f.dateFormat = "EEEE · d MMM"
        return f
    }()

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateEyebrow.string(from: Date()).uppercased())
                    .font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                Text("Departures").font(ws.sans(26, weight: .heavy)).foregroundStyle(ws.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Map — browse every stop and station around you (iOS-only feature).
            Button { push(.map) } label: {
                WSIcon(glyph: .map, size: 18)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(ws.panel))
                    .overlay(Circle().stroke(ws.rule, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nearby map")
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var searchBar: some View {
        Button(action: onSearch) {
            HStack(spacing: 11) {
                WSIcon(glyph: .search, size: 19, color: ws.dim)
                Text("Stop, bus, MRT or postal code")
                    .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer()
            }
            .padding(.horizontal, 15).frame(height: 50)
            .background(ws.input)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.top, 15)
    }

    // MARK: list content

    /// The answer card: the closest stop with live ETA chips. First thing
    /// under search because it's the reason the app was opened.
    @ViewBuilder private var heroSection: some View {
        if let closest = busStops.first {
            ClosestStopCard(stop: closest)
                .padding(.horizontal, 22).padding(.top, 20)
        }
    }

    /// The nearest station only, promoted to a full-width card — Home's
    /// second answer ("how's the train"). The other stations live on the map.
    @ViewBuilder private var nearestMrtSection: some View {
        if let item = nearbyStations.first {
            MrtCard(station: item.station, distanceM: item.distanceM,
                    walkMin: item.walkMin, fullWidth: true)
                .padding(.horizontal, 22).padding(.top, 14)
        }
    }

    /// The door to everything else nearby: a live map preview around the
    /// user, captioned — a preview self-explains in a way an icon never did
    /// (the old ghost-circle map button read as decoration).
    private var mapCard: some View {
        Button { push(.map) } label: {
            ZStack(alignment: .bottomLeading) {
                if let coord {
                    Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))),
                        interactionModes: [])
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .allowsHitTesting(false)
                } else {
                    ws.panel2
                    WSIcon(glyph: .map, size: 26, color: ws.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 8) {
                    WSIcon(glyph: .map, size: 14, color: ws.text)
                    Text("All stops & stations")
                        .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.text)
                    Spacer(minLength: 0)
                    WSIcon(glyph: .chevron, size: 12, color: ws.dim)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.thinMaterial)
            }
            .frame(height: 148)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.top, 14)
        .accessibilityLabel("Map — all stops and stations nearby")
    }

    private var busStops: [NearbyStop] {
        store.nearby.filter { !m.hiddenNearby.contains($0.stopCode) }
    }

    /// Empty-state hints (Home still owns "nothing nearby") plus the way back
    /// from the long-press "Hide from Nearby" action.
    @ViewBuilder private var emptyStateOrFooter: some View {
        if busStops.isEmpty {
            if coord == nil {
                emptyHint("Turn on location to see stops near you.")
            } else if case .error = store.referenceState {
                // The stop directory failed to load (LTA flake) — the old
                // copy claimed we were still "finding" forever. Stay quiet,
                // be accurate, offer the way back. Foreground/appear also
                // auto-retry, so the tap is a shortcut, not a chore.
                Button {
                    Task { await store.bootstrap() }
                } label: {
                    emptyHint("Stops aren’t loading right now — tap to retry.")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                emptyHint("Finding stops near you…")
            }
        }
        let hiddenHere = store.nearby.filter { m.hiddenNearby.contains($0.stopCode) }.count
        if hiddenHere > 0 {
            Button {
                withAnimation(.snappy(duration: 0.25)) { m.hiddenNearby = [] }
            } label: {
                Text("\(hiddenHere) \(hiddenHere == 1 ? "stop" : "stops") hidden · SHOW")
                    .font(ws.mono(11, weight: .medium)).tracking(0.4)
                    .foregroundStyle(ws.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 18)
    }
}

// MARK: - Closest stop hero card
//
// Describes the next five minutes at the closest stop, not the stop itself:
// big name, a whisper-quiet walk line (no stop code / road — that's detail-
// screen material), then live ETA chips sorted soonest-first. Chips deep-link
// to their bus; the card itself opens the stop. Green ("Now") exists only
// while a bus is genuinely arriving — at rest the card is fully neutral.

private struct ClosestStopCard: View {
    let stop: NearbyStop
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the slow border/glow breath while something is arriving.
    @State private var breathe = false

    /// Live services soonest-first, so any truncation hides only the least
    /// urgent buses — the one you're running for is never behind the +N.
    /// Ties break on service number so equal ETAs don't trade places on
    /// every refresh tick (Swift's sort is not guaranteed stable).
    private var services: [Service] {
        store.servicesFor(stop.stopCode).sorted {
            let (a, b) = (wsLiveETASec($0), wsLiveETASec($1))
            return a == b ? $0.no.localizedStandardCompare($1.no) == .orderedAscending
                          : a < b
        }
    }
    private var anyArriving: Bool {
        services.first.map { wsLiveETASec($0) < 60 } ?? false
    }

    var body: some View {
        // Child views track their own observation — the per-second countdown
        // needs this view to read `tick` itself (same note as StopRow).
        let _ = m.tick
        let arriving = anyArriving
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("CLOSEST STOP").font(ws.mono(10)).tracking(1.2).foregroundStyle(ws.dim)
                Spacer(minLength: 8)
                // Freshness whisper — the LIVE/Updated section header left
                // Home with the stop list, and the hero is the only live
                // thing on the screen now.
                Text(WSFmt.upd(store.newestRefresh(amongst: [stop.stopCode]), use24h: m.use24h))
                    .font(ws.mono(10)).tracking(0.4).foregroundStyle(ws.faint)
            }
            Text(stop.stopName)
                .font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                .padding(.top, 7)
            Text(walkLine)
                .font(ws.mono(11.5, weight: .medium)).tracking(0.3).foregroundStyle(ws.dim)
                .padding(.top, 5)
            chipArea.padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ws.panel)
        .overlay(shape.stroke(arriving ? ws.now.opacity(breathe ? 0.8 : 0.45) : ws.rule,
                              lineWidth: arriving ? 1.5 : 1))
        .clipShape(shape)
        // Dark theme reads this as an edge glow; light theme as a soft green
        // ambient shadow — same meaning, different physics.
        .shadow(color: arriving ? ws.now.opacity(breathe ? 0.30 : 0.14) : .clear, radius: 16)
        .contentShape(shape)
        .onTapGesture { push(.busStop(code: stop.stopCode)) }
        .contentShape(.contextMenuPreview, shape)
        .contextMenu {
            Button(action: togglePin) {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "bookmark.slash" : "bookmark")
            }
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.25)) { m.hideFromNearby(code: stop.stopCode) }
            } label: {
                Label("Hide from Nearby", systemImage: "eye.slash")
            }
        }
        .onChange(of: arriving, initial: true) { _, isOn in
            if isOn && !reduceMotion {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { breathe = false }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(a11y)
    }

    // MARK: board

    /// Rows on the board before the "+N more" footer. The Departures screen
    /// has the vertical room now (the stop list left Home), so the hero
    /// spends it on a real mini departure board: per-service rows with
    /// destination, crowd, the next arrival AND the one after it.
    private static let boardCap = 4

    @ViewBuilder private var chipArea: some View {
        if services.isEmpty {
            // No live arrivals yet (still fetching, or service ended) — fall
            // back to the plain route tiles so the card never sits empty.
            let tiles = routeTiles
            if !tiles.isEmpty { TileRow(services: tiles) }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(services.prefix(Self.boardCap).enumerated()),
                        id: \.element.no) { index, svc in
                    if index > 0 { WSRowDivider() }
                    BoardRow(service: svc, stopCode: stop.stopCode)
                }
                if services.count > Self.boardCap {
                    WSRowDivider()
                    Button { push(.busStop(code: stop.stopCode)) } label: {
                        HStack(spacing: 8) {
                            Text("+\(services.count - Self.boardCap) MORE \(services.count - Self.boardCap == 1 ? "SERVICE" : "SERVICES")")
                                .font(ws.mono(10, weight: .medium)).tracking(1.0)
                                .foregroundStyle(ws.dim)
                            Spacer(minLength: 0)
                            WSIcon(glyph: .chevron, size: 11, color: ws.faint)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(services.count - Self.boardCap) more services — open stop")
                }
            }
        }
    }

    // MARK: derived

    private var routeTiles: [String] {
        let fromRoutes = store.servicesAtStop(stop.stopCode)
        return fromRoutes.isEmpty ? store.servicesFor(stop.stopCode).map(\.no) : fromRoutes
    }

    /// "1 MIN WALK · 40M" — walk time first (how humans think), raw distance
    /// as the whisper after. ~80 m/min, matching the MRT cards' pacing.
    private var walkLine: String {
        guard stop.distanceM > 0 else { return "" }
        let walkMin = max(1, Int((Double(stop.distanceM) / 80).rounded()))
        return "\(walkMin) MIN WALK · \(fmtDistance(stop.distanceM).uppercased())"
    }

    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: stop.stopCode, nickname: "")) }
    }

    private var a11y: String {
        var parts = ["Closest stop, \(stop.stopName)"]
        if stop.distanceM > 0 {
            parts.append("\(max(1, Int((Double(stop.distanceM) / 80).rounded()))) minute walk")
        }
        for svc in services.prefix(3) {
            let sec = wsLiveETASec(svc)
            parts.append(sec < 60 ? "bus \(svc.no) arriving now"
                                  : "bus \(svc.no) in \(max(1, sec / 60)) minutes")
        }
        return parts.joined(separator: ", ")
    }
}

/// One board row: service number (green while inside the arrival window),
/// destination + crowd in the middle, the next arrival AND the one after it
/// on the right ("Now / then 12 min"). Minute digits roll like an odometer;
/// promotion to Now springs the number's tint. Tapping deep-links to the bus.
private struct BoardRow: View {
    let service: Service
    let stopCode: String
    @Environment(AppModel.self) private var m: AppModel
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = m.tick
        let sec = wsLiveETASec(service)
        let now = sec < 60
        let minutes = max(1, sec / 60)
        let followMin = liveFollowingMin()
        Button { push(.trackBus(stopCode: stopCode, no: service.no)) } label: {
            HStack(spacing: 12) {
                Text(service.no)
                    .font(ws.mono(17, weight: .bold))
                    .foregroundStyle(now ? ws.now : ws.text)
                    .frame(minWidth: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    if !service.dest.isEmpty {
                        Text("to \(service.dest)")
                            .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        CrowdGauge(fraction: service.load.wsFraction, width: 22)
                        Text(service.load.wsWord).font(ws.mono(9.5)).foregroundStyle(ws.dim)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Group {
                        if now {
                            Text("Now").font(ws.mono(15, weight: .bold)).foregroundStyle(ws.now)
                        } else {
                            (Text("\(minutes)").font(ws.mono(15, weight: .bold)).foregroundStyle(ws.text)
                             + Text(" min").font(ws.mono(10)).foregroundStyle(ws.dim))
                        }
                    }
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    if let followMin {
                        Text("then \(followMin) min")
                            .font(ws.mono(9.5)).foregroundStyle(ws.faint)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Promotion to "Now" springs the tint change; the countdown roll rides
        // the same value-scoped animations (numericText needs one to animate).
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.4, dampingFraction: 0.75), value: now)
        .animation(.snappy(duration: 0.3), value: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(now: now, minutes: minutes, followMin: followMin))
    }

    /// Live minutes to the bus after next, recomputed from the absolute
    /// timestamp so it ticks with the board. nil when LTA has no second bus.
    private func liveFollowingMin() -> Int? {
        let sec: Int
        if let d = service.followingDate {
            sec = max(0, Int(d.timeIntervalSince(Date())))
        } else if service.followingSec > 0 {
            sec = service.followingSec
        } else {
            return nil
        }
        return max(1, sec / 60)
    }

    private func a11y(now: Bool, minutes: Int, followMin: Int?) -> String {
        var parts = [now ? "Bus \(service.no), arriving now"
                         : "Bus \(service.no), \(minutes) minutes"]
        if !service.dest.isEmpty { parts.append("to \(service.dest)") }
        parts.append(service.load.wsWord)
        if let followMin { parts.append("then \(followMin) minutes") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - MRT station card (nearest station, full width on Home)

private struct MrtCard: View {
    let station: MrtGeoStation
    let distanceM: Int
    let walkMin: Int
    /// Home's promoted nearest-station card spans the gutter; the compact
    /// 186 pt form remains for horizontal strips (e.g. the map's callouts).
    var fullWidth: Bool = false
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        Button { push(.mrtStation(station)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    // Two bullets max in the fixed-width card — three plus the
                    // crowd chip can't fit 186pt (the full set lives on the
                    // station screen). Full width fits them all. Bullets are
                    // fixedSize, so an overflow would draw past the card
                    // instead of wrapping.
                    ForEach(fullWidth ? station.codes : Array(station.codes.prefix(2)),
                            id: \.self) { LineBullet(code: $0) }
                    Spacer(minLength: 0)
                    if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                        CrowdGauge(fraction: crowd.wsFraction, width: 22)
                        Text(crowd.wsWord).font(ws.mono(10, weight: .bold)).foregroundStyle(ws.dim)
                            .lineLimit(1)
                    }
                }
                Text(station.name)
                    .font(ws.sans(15, weight: .bold)).foregroundStyle(ws.text)
                    .lineLimit(1)
                Text(subline).font(ws.mono(10.5)).tracking(0.3).foregroundStyle(ws.dim)
                    .lineLimit(1)
                // Full-width card has the room for the plain-language crowd
                // hint ("PLENTY OF ROOM") — the gauge says how much, this
                // says what it means.
                if fullWidth, let crowd = store.wsCrowd(for: station), crowd != .unknown {
                    Text(crowd.wsHint)
                        .font(ws.mono(9.5)).tracking(0.6).foregroundStyle(ws.faint)
                        .lineLimit(1)
                }
            }
            .padding(fullWidth ? 16 : 14)
            .frame(width: fullWidth ? nil : 186, alignment: .leading)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .background(ws.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button { m.toggleMrtSaved(station) } label: {
                Label(m.isMrtSaved(station) ? "Remove from Saved" : "Save station",
                      systemImage: m.isMrtSaved(station) ? "bookmark.slash" : "bookmark")
            }
        }
        .accessibilityLabel(a11y)
    }

    private var subline: String {
        // Walk time leads (the human unit), raw distance follows — the same
        // order as the hero card's walk line.
        distanceM > 0 ? "\(walkMin) min walk · \(fmtDistance(distanceM))".uppercased()
                      : wsLineNames(from: station.codes).uppercased()
    }

    private var a11y: String {
        var parts = ["\(station.name) MRT", wsLineNames(from: station.codes)]
        if distanceM > 0 { parts.append("\(walkMin) minute walk") }
        if let crowd = store.wsCrowd(for: station), crowd != .unknown {
            parts.append("crowd \(crowd.wsWord)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Distinct human line names from a station's codes, e.g. "North South / Thomson–East Coast".
func wsLineNames(from codes: [String]) -> String {
    var names: [String] = []
    for c in codes {
        let name: String
        switch c.prefix(2).uppercased() {
        case "NS": name = "North South"
        case "EW", "CG": name = "East West"
        case "NE": name = "North East"
        case "CC", "CE": name = "Circle"
        case "DT": name = "Downtown"
        case "TE": name = "Thomson–East Coast"
        default: name = "LRT"
        }
        if !names.contains(name) { names.append(name) }
    }
    return names.joined(separator: " / ")
}
