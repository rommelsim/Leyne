// WhereSia — Home · Nearby (screen 1).
//
// "Departly green-dark" board redesign (design-greendark branch): a header
// with a quiet "<area> · updated Ns ago" caption, a search pill that
// collapses on scroll, All/Buses/MRT filter chips, then one scroll with a
// hero "closest stop" card, a "More bus stops" card (2 rows, expandable),
// and an "MRT stations" card. Wired to the same data as before —
// DataStore.nearby + MrtGeo.nearestStations — this is a visual/structural
// pass only.

import SwiftUI
import CoreLocation

struct WSHomeView: View {
    var onSearch: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Filter: Int, CaseIterable { case all, buses, mrt }
    @State private var filter: Filter = .all
    @State private var expandedStops = false
    /// Widest station name in the MRT card — every row's name column takes
    /// this width so the line badges align vertically (owner call).
    @State private var mrtNameColumnWidth: CGFloat?

    private var coord: CLLocationCoordinate2D? { location.location?.coordinate }

    private var nearbyStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] {
        guard let c = coord else { return [] }
        return MrtGeo.nearestStations(to: c, limit: 4)
    }

    /// Display order of the nearby stop list, frozen at first paint. GPS
    /// wobble re-sorts `store.nearby` every few seconds, which made the whole
    /// screen "jump around" (owner field test 2026-07-24). The list keeps its
    /// first-paint order; a re-sort happens only on explicit pull-to-refresh
    /// or when the user has genuinely moved (several hundred metres — a new
    /// context, not jitter). Distances/ETAs inside the rows stay live.
    @State private var frozenOrder: [String] = []
    @State private var frozenAt: CLLocationCoordinate2D? = nil

    /// Hidden-filtered nearby bus stops in the frozen display order (newly
    /// appearing stops append at the end rather than shuffling in).
    private var busStops: [NearbyStop] {
        let live = store.nearby.filter { !m.hiddenNearby.contains($0.stopCode) }
        guard !frozenOrder.isEmpty else { return live }
        let idx = Dictionary(uniqueKeysWithValues: frozenOrder.enumerated().map { ($1, $0) })
        return live.sorted { (idx[$0.stopCode] ?? .max) < (idx[$1.stopCode] ?? .max) }
    }

    /// (Re)freeze the list order to the store's current distance sort.
    private func refreezeOrder() {
        frozenOrder = store.nearby.map(\.stopCode)
        frozenAt = coord
    }

    /// Freeze on first data; re-freeze only after a genuine move (~350 m).
    private func syncFrozenOrder() {
        if frozenOrder.isEmpty { if !store.nearby.isEmpty { refreezeOrder() }; return }
        if let here = coord, let anchor = frozenAt,
           haversine(here.latitude, here.longitude,
                     anchor.latitude, anchor.longitude) > 350 {
            refreezeOrder()
        }
    }

    var body: some View {
        let _ = m.tick   // per-second live countdown refresh
        Group {
            // Owner pick 2026-07-24 ("4b reference blue", Nearby Soft.dc.html):
            // the soft-blue product style IS the Nearby screen — in every
            // appearance. It's a light-palette design, so it renders
            // identically in dark mode (owner lives in dark and wants to see
            // it; a true dark twin is designed separately). `darkBody` keeps
            // the greendark board around for a quick revert.
            softBody
        }
        .onAppear(perform: bootstrap)
        .onChange(of: location.location) { _, loc in
            if let loc { store.updateNearby(loc); store.prefetchNearbyArrivals() }
            syncFrozenOrder()
            store.wsWarmCrowd(for: nearbyStations.map(\.station))
        }
        // Nearby rows otherwise only refresh on a location change — sit
        // still and they go stale. The freshness window inside
        // ensureArrivals turns this into an actual fetch ~every 25s.
        .onChange(of: m.tick) { _, _ in
            store.prefetchNearbyArrivals()
            if frozenOrder.isEmpty { syncFrozenOrder() }   // first data may land async
        }
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

    // MARK: - Dark body (greendark board — unchanged)

    private var darkBody: some View {
        VStack(spacing: 0) {
            header
            filterChips

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Search bar scrolls WITH the content — driving a collapse
                    // from scroll offset resized the viewport, which re-crossed
                    // the threshold and fought itself (owner-reported jitter).
                    searchBar
                    if coord == nil {
                        locationOffState
                    } else if busStops.isEmpty, nearbyStations.isEmpty, case .loading = store.referenceState {
                        skeletonStack
                    } else if busStops.isEmpty, case .error = store.referenceState {
                        errorHint
                    } else {
                        if filter != .mrt { hero }
                        if filter != .mrt { moreStopsSection(proxy) }
                        if filter != .buses { mrtSection }
                    }
                    Color.clear.frame(height: 90)   // floating tab bar clearance
                }
                .padding(.horizontal, 18).padding(.top, 14)
            }
            .refreshable {
                // The one sanctioned re-sort: pull-to-refresh re-freezes the
                // list to the current distance order and refetches arrivals.
                if let loc = location.location { store.updateNearby(loc) }
                refreezeOrder()
                store.prefetchNearbyArrivals()
            }
            }
        }
        .background(ws.background())
    }

    // MARK: - Soft body ("4b reference blue" — owner pick 2026-07-24)

    private var softBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                softCaptionRow
                if coord == nil {
                    locationOffState
                } else if busStops.isEmpty, nearbyStations.isEmpty, case .loading = store.referenceState {
                    skeletonStack
                } else if busStops.isEmpty, case .error = store.referenceState {
                    errorHint
                } else {
                    if filter != .mrt, let stop = busStops.first {
                        SoftHeroCard(stop: stop).wsEntrance()
                    }
                    // Chips join the entrance stagger (hero → chips → stops):
                    // without it they painted instantly while the cards were
                    // still drifting in, reading as a glitch on every tab
                    // switch (owner 2026-07-25).
                    softChips.wsEntrance(delay: 0.02)
                    if filter != .mrt { softStopsSection }
                    if filter != .buses { softMrtSection }
                    hiddenFooter
                }
                // The tab bar is a bottom safeAreaInset (WSRoot), so the
                // scroll view is already inset for it — this used to add a
                // SECOND 90pt of clearance, which is the empty band under the
                // MRT tiles the owner flagged (2026-07-25).
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .refreshable {
            if let loc = location.location { store.updateNearby(loc) }
            refreezeOrder()
            store.prefetchNearbyArrivals()
        }
        .background(SoftBlue.bg.ignoresSafeArea())
        // Native nav bar (owner 2026-07-25): system large title + real
        // toolbar buttons, replacing the hand-built header row and its two
        // white rounded tiles. SF Symbols in a system toolbar get the
        // platform's own sizing, tint, press feedback and Liquid Glass
        // treatment on iOS 26 — none of which a custom tile can match.
        .navigationTitle("Nearby")
        .navigationBarTitleDisplayMode(.inline)   // owner 2026-07-25: large titles left a big empty band at the top
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass", action: onSearch)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nearby map", systemImage: "map") { push(.map) }
            }
        }
    }

    /// Header caption: where the data is anchored + how fresh it is. The
    /// header's job is orientation ("this is Nearby, it's live, here's
    /// search/map") — the greeting + "Buses near X" title read as filler
    /// (owner 2026-07-25) and the area name belongs with the freshness fact.
    private var softCaption: String {
        let area = store.nearby.first.map { store.roadName($0.stopCode) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let codes = store.nearby.map(\.stopCode)
        if let last = store.newestRefresh(amongst: codes) {
            let secs = max(0, Int(Date().timeIntervalSince(last)))
            let when = secs < 5 ? "just now" : secs < 60 ? "\(secs)s ago" : "\(secs / 60)m ago"
            return area.map { "\($0) · updated \(when)" } ?? "Updated \(when)"
        }
        return area ?? "Stops and stations around you"
    }

    /// The freshness line. The title and the two actions moved to the system
    /// nav bar, so all that's left of the old header is the one fact the nav
    /// bar can't carry: where this data is anchored and how old it is.
    private var softCaptionRow: some View {
        Text(softCaption)
            .font(ws.sans(12.5, weight: .medium)).foregroundStyle(SoftBlue.sub)
            .lineLimit(1)
    }

    private var softChips: some View {
        HStack(spacing: 8) {
            softChip("All", .all)
            softChip("Buses", .buses)
            softChip("MRT", .mrt)
            Spacer(minLength: 0)
        }
    }

    private func softChip(_ label: String, _ f: Filter) -> some View {
        let on = filter == f
        return Button {
            withAnimation(SoftMotion.flow) { filter = f }
        } label: {
            Text(label)
                .font(ws.sans(13, weight: .semibold))
                .foregroundStyle(on ? .white : SoftBlue.sub)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(on ? SoftBlue.ink : Color.white))
                .shadow(color: SoftBlue.shadow, radius: 5, y: 3)
        }
        .buttonStyle(SoftPressStyle())
    }

    @ViewBuilder private var softStopsSection: some View {
        let rest = Array(busStops.dropFirst())
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nearby stops")
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                    Spacer()
                    if rest.count > 3 {
                        Button {
                            withAnimation(SoftMotion.flow) { expandedStops.toggle() }
                        } label: {
                            Text(expandedStops ? "Show fewer" : "View all")
                                .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(SoftBlue.blue)
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
                .padding(.horizontal, 4)

                let shown = expandedStops ? rest : Array(rest.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, stop in
                        SoftStopRow(stop: stop)
                        if i < shown.count - 1 {
                            Rectangle().fill(SoftBlue.hairline).frame(height: 1)
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: SoftBlue.shadow, radius: 9, y: 6)
            }
            .wsEntrance(delay: 0.045)
        }
    }

    @ViewBuilder private var softMrtSection: some View {
        if !nearbyStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("MRT stations")
                    .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(nearbyStations.prefix(4)), id: \.station.id) { item in
                        SoftMrtTile(station: item.station, distanceM: item.distanceM)
                    }
                }
            }
            .wsEntrance(delay: 0.09)
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
        syncFrozenOrder()
        store.ensureRoutes()
        store.prefetchNearbyArrivals()
        store.wsWarmCrowd(for: nearbyStations.map(\.station))
    }

    // MARK: header

    private var headerCaption: String {
        let area = store.nearby.first.map { store.roadName($0.stopCode) }
                       .flatMap { $0.isEmpty ? nil : $0 }
                   ?? nearbyStations.first?.station.name
                   ?? "Nearby you"
        let codes = store.nearby.map(\.stopCode)
        guard let last = store.newestRefresh(amongst: codes) else { return "\(area) · updated —" }
        let secs = max(0, Int(Date().timeIntervalSince(last)))
        let when = secs < 5 ? "just now" : secs < 60 ? "\(secs)s ago" : "\(secs / 60)m ago"
        return "\(area) · updated \(when)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Nearby")
                    .font(ws.sans(24, weight: .bold)).tracking(-0.48)
                    .foregroundStyle(ws.text)
                Text(headerCaption)
                    .font(ws.sans(12, weight: .regular)).foregroundStyle(ws.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Map — browse every stop and station around you (iOS-only feature,
            // owner-mandated; the design file has no map button).
            Button { push(.map) } label: {
                WSIcon(glyph: .map, size: 15, color: ws.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ws.isDark ? Color.white.opacity(0.07) : ws.panel2))
                    .overlay(Circle().stroke(ws.isDark ? Color.white.opacity(0.09) : ws.rule, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel("Nearby map")
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var searchBar: some View {
        Button(action: onSearch) {
            HStack(spacing: 10) {
                WSIcon(glyph: .search, size: 14, color: ws.dim)
                Text("Search stops, buses, stations")
                    .font(ws.sans(14, weight: .regular)).foregroundStyle(ws.dim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .wsNativeGlass()   // native Liquid Glass (owner call)
            .shadow(color: .black.opacity(ws.isDark ? 0.5 : 0.08), radius: 15, y: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(SoftPressStyle())
        .padding(.horizontal, 4)   // 18 content gutter + 4 = the 22pt bar inset
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            chip("All", .all)
            chip("Buses", .buses)
            chip("MRT", .mrt)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 2)
    }

    private func chip(_ label: String, _ f: Filter) -> some View {
        let on = filter == f
        return Button {
            withAnimation(SoftMotion.flow) { filter = f }
        } label: {
            Text(label)
                .font(ws.sans(12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? ws.text : ws.dim)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? (ws.isDark ? Color.white.opacity(0.10) : ws.panel2) : .clear)
                .overlay(Capsule().stroke(on ? (ws.isDark ? Color.white.opacity(0.12) : ws.rule) : ws.rule,
                                          lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(SoftPressStyle())
    }

    // MARK: hero (closest stop)

    @ViewBuilder private var hero: some View {
        if let stop = busStops.first {
            WSHeroStopCard(stop: stop)
                .wsEntrance()
        }
    }

    // MARK: more bus stops

    @ViewBuilder private func moreStopsSection(_ proxy: ScrollViewProxy) -> some View {
        let rest = Array(busStops.dropFirst())
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("MORE BUS STOPS")
                    .font(ws.sans(11, weight: .bold)).tracking(0.9).foregroundStyle(ws.dim)
                    .padding(.horizontal, 4).padding(.bottom, 10)

                let shown = expandedStops ? rest : Array(rest.prefix(2))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, stop in
                        WSMoreStopRow(stop: stop)
                        if i < shown.count - 1 { WSRowDivider().padding(.leading, 16) }
                    }
                    // Footer lives INSIDE the card (design): its hairline is the
                    // row separator; outside the card it read as a stray line.
                    if rest.count > 2 {
                        Button {
                            if expandedStops {
                                // Collapse + anchor the section top in one animated
                                // pass — without the explicit scroll target the
                                // shrinking content made everything below (ad card,
                                // MRT card) jitter as the offset re-clamped.
                                withAnimation(SoftMotion.flow) {
                                    expandedStops = false
                                    proxy.scrollTo("more-bus-stops", anchor: .top)
                                }
                            } else {
                                withAnimation(SoftMotion.flow) { expandedStops = true }
                            }
                        } label: {
                            VStack(spacing: 0) {
                                WSRowDivider()
                                Text(expandedStops ? "Show fewer stops" : "Show all \(busStops.count) stops nearby")
                                    .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.accent)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 11).padding(.horizontal, 16)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
                .wsCard(radius: 18)
                // No ad on Nearby (owner call, 2026-07-24) — the native slot
                // was removed; detail-screen banners are unaffected.

                hiddenFooter
            }
            .padding(.top, 4)
            .wsEntrance(delay: 0.045)
            .id("more-bus-stops")   // scroll anchor for the collapse action
        } else {
            hiddenFooter
        }
    }

    @ViewBuilder private var hiddenFooter: some View {
        // The way back from the long-press "Hide from Nearby" action — without
        // this a hidden stop is gone for good (the Me tab is no more).
        let hiddenHere = store.nearby.filter { m.hiddenNearby.contains($0.stopCode) }.count
        if hiddenHere > 0 {
            Button {
                withAnimation(SoftMotion.flow) { m.hiddenNearby = [] }
            } label: {
                Text("\(hiddenHere) \(hiddenHere == 1 ? "stop" : "stops") hidden · SHOW")
                    .font(ws.mono(11, weight: .medium)).tracking(0.4)
                    .foregroundStyle(ws.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
        }
    }

    // MARK: MRT stations

    /// True when any of the currently-listed nearby stations sits on a line
    /// with an active disruption — drives the card's amber glow edge.
    private var mrtHasAlert: Bool {
        nearbyStations.contains { item in
            item.station.codes.contains { code in
                guard let line = wsLine(forStationCode: code) else { return false }
                return store.trainAlerts.contains { $0.line == line }
            }
        }
    }

    @ViewBuilder private var mrtSection: some View {
        if !nearbyStations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("MRT STATIONS")
                    .font(ws.sans(11, weight: .bold)).tracking(0.9).foregroundStyle(ws.dim)
                    .padding(.horizontal, 4).padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(nearbyStations.enumerated()), id: \.element.station.id) { i, item in
                        WSStationRow(station: item.station, distanceM: item.distanceM,
                                     nameColumnWidth: mrtNameColumnWidth)
                        if i < nearbyStations.count - 1 { WSRowDivider().padding(.leading, 16) }
                    }
                }
                .onPreferenceChange(WSNameColumnKey.self) { mrtNameColumnWidth = $0 }
                .wsCard(radius: 18)
                .overlay(alignment: .top) {
                    if mrtHasAlert { WSGlowEdge(color: WSTheme.amber) }
                }
            }
            .padding(.top, 4)
            .wsEntrance(delay: 0.09)
        }
    }

    // MARK: status states

    private var locationOffState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(ws.isDark ? Color.white.opacity(0.05) : ws.panel2).frame(width: 52, height: 52)
                    .overlay(Circle().stroke(ws.isDark ? Color.white.opacity(0.1) : ws.rule, lineWidth: 1))
                WSIcon(glyph: .location, size: 16, color: ws.dim)
            }
            VStack(spacing: 5) {
                Text("Location is off")
                    .font(ws.sans(15, weight: .bold)).foregroundStyle(ws.text)
                Text("Turn on location to see the stops and stations closest to you.")
                    .font(ws.sans(12.5, weight: .regular)).foregroundStyle(ws.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                location.requestPermission()
            } label: {
                Text("Turn on Location")
                    .font(ws.sans(13.5, weight: .bold)).foregroundStyle(WSTheme.accentInk)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(ws.mintGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(SoftPressStyle())
            Button(action: onSearch) {
                Text("Search instead")
                    .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.accent)
            }
            .buttonStyle(SoftPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30).padding(.top, 70)
    }

    private var errorHint: some View {
        // The stop directory failed to load (LTA flake) — the old copy
        // claimed we were still "finding" forever. Stay quiet, be accurate,
        // offer the way back. Foreground/appear also auto-retry, so the tap
        // is a shortcut, not a chore.
        Button {
            Task { await store.bootstrap() }
        } label: {
            HStack {
                Text("Stops aren’t loading right now — tap to retry.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .wsCard(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private var skeletonStack: some View {
        // Skeletons mirror the loaded layout's anatomy AND dimensions — one
        // hero-sized card, then row-sized cards — so the swap to real content
        // doesn't shift anything below it (field test: "everything is
        // jumping around").
        VStack(spacing: 10) {
            WSSkeletonCard(hero: true).wsEntrance()
            ForEach(1..<4, id: \.self) { i in
                WSSkeletonCard(delaySeconds: Double(i) * 0.15).wsEntrance(delay: Double(i) * 0.04)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Skeleton card

/// Placeholder row card matching a real bus-stop row's anatomy (title bar +
/// subtitle bar on the left, ETA-chip bar on the right) instead of a single
/// featureless block — shimmer staggers 150ms per card like the design.
private struct WSSkeletonCard: View {
    var delaySeconds: Double = 0
    /// Hero variant mirrors WSHeroStopCard's anatomy (name + metadata line,
    /// then tile + big ETA next to a side column) at the same dimensions, so
    /// the loaded card lands without pushing content below it.
    var hero: Bool = false
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Group {
            if hero {
                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 6) {
                        bar(w: 170, h: 16, r: 6)
                        bar(w: 120, h: 11, r: 5, dim: true)
                    }
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            bar(w: 92, h: 24, r: 7)
                            bar(w: 130, h: 10, r: 5, dim: true)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 7) {
                            bar(w: 84, h: 12, r: 5, dim: true)
                            bar(w: 84, h: 12, r: 5, dim: true)
                            bar(w: 84, h: 12, r: 5, dim: true)
                        }
                    }
                    .frame(minHeight: 74)
                }
                .padding(.horizontal, 16).padding(.vertical, 15)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        bar(w: 140, h: 14, r: 6)
                        bar(w: 90, h: 10, r: 5, dim: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    bar(w: 56, h: 22, r: 8)
                }
                // Matches WSMoreStopRow's 16/14 row inset exactly — the
                // skeleton must occupy the same height as the loaded row.
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .wsCard(radius: 18)
        .opacity(dimmed ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(SoftMotion.breathe.delay(delaySeconds)) {
                dimmed = true
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(w: CGFloat, h: CGFloat, r: CGFloat, dim: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(Color.white.opacity(dim ? 0.06 : 0.09))
            .frame(width: w, height: h)
    }
}

// MARK: - Hero (closest stop) card

private struct WSHeroStopCard: View {
    let stop: NearbyStop
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    private var services: [Service] { store.servicesFor(stop.stopCode) }
    private var featured: Service? { wsSoonest(services) }
    private var others: [Service] {
        guard let f = featured else { return [] }
        return services.filter { $0.no != f.no }
            .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
            .prefix(3)
            .map { $0 }
    }
    private var interchange: (name: String, codes: [String])? { wsInterchange(forStopName: stop.stopName) }
    private var featuredETASec: Int { featured.map { wsLiveETASec($0) } ?? .max }
    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }

    var body: some View {
        // Live countdown depends on `tick`, tracked by the parent — this
        // view re-renders alongside it since it reads `store.servicesFor`.
        Button { push(.busStop(code: stop.stopCode, service: nil)) } label: {
            VStack(alignment: .leading, spacing: 11) {
                // Read order (field test 2026-07-24): stop NAME leads, then the
                // hero bus + ETA, then the secondary services. Code, distance
                // and MRT chips are identity info, not urgency — they collapse
                // into ONE quiet metadata line under the name (no chip
                // background, no mint distance; the pulse-dot decoration went
                // too — the glow edge already carries "live").
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.stopName)
                            .font(ws.sans(16.5, weight: .bold)).foregroundStyle(ws.text)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text("\(stop.stopCode) · \(fmtDistance(stop.distanceM))")
                                .font(ws.mono(11, weight: .regular)).foregroundStyle(ws.dim)
                            if let interchange {
                                ForEach(interchange.codes.prefix(2), id: \.self) { LineBullet(code: $0) }
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    WSIcon(glyph: .chevron, size: 14, color: ws.dim)
                        .padding(.top, 2)
                }

                // Featured side takes all flexible width; the side column hugs
                // a compact fixed width so tile → ETA don't drift apart
                // (owner call: divider sits right, no dead space in the rows).
                // The side column sits tight against the hero (10pt gutters
                // around a shared hairline) so it reads as the SAME stop's
                // other services, not a detached widget (field test).
                HStack(alignment: .center, spacing: 0) {
                    featuredColumn.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 10)
                    Rectangle().fill(ws.rule).frame(width: 1).frame(maxHeight: .infinity)
                    othersColumn
                        .padding(.leading, 10)
                }
                .frame(minHeight: 74)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            // Whole card is the tap target — without this only the drawn
            // text/tiles hit-tested (owner-reported).
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .wsCard(radius: 20, emphasized: true)
        .overlay(alignment: .top) {
            WSGlowEdge(color: ws.accent, breathing: featuredETASec <= 60)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button(action: togglePin) {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "bookmark.slash" : "bookmark")
            }
            Button(role: .destructive) {
                withAnimation(SoftMotion.flow) { m.hideFromNearby(code: stop.stopCode) }
            } label: {
                Label("Hide from Nearby", systemImage: "eye.slash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    @ViewBuilder private var featuredColumn: some View {
        if let featured {
            let eta = fmtETA(wsLiveETASec(featured)).big
            HStack(spacing: 12) {
                WSFeaturedTile(no: featured.no)
                VStack(alignment: .leading, spacing: 3) {
                    WSBigETA(text: eta == "Arr" ? eta : "\(eta) min", size: 28)
                        .id(featured.no)   // swap animates via contentTransition below
                    (Text("Next bus").font(ws.sans(11.5, weight: .semibold)).foregroundStyle(ws.accent)
                     + Text(" · to \(featured.dest)").font(ws.sans(11.5, weight: .regular)).foregroundStyle(ws.dim))
                        .lineLimit(1)
                }
            }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .animation(SoftMotion.flow, value: featured.no)
        } else {
            Text("No live arrivals").font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
        }
    }

    @ViewBuilder private var othersColumn: some View {
        if others.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(others) { svc in
                    HStack(spacing: 0) {
                        WSServiceTile(no: svc.no, size: 11)
                        Spacer(minLength: 8)
                        Text(fmtETA(wsLiveETASec(svc)).big + (fmtETA(wsLiveETASec(svc)).big == "Arr" ? "" : " min"))
                            .font(ws.mono(12.5, weight: .regular))
                            .foregroundStyle(Color(wsHex: "CFD4DA"))
                    }
                    .frame(width: 108)   // compact rows: tile ↔ ETA stay close
                }
            }
        }
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: stop.stopCode, nickname: "")) }
    }

    private var a11y: String {
        var parts = ["Closest stop", stop.stopName, fmtDistance(stop.distanceM)]
        if let featured {
            let eta = fmtETA(wsLiveETASec(featured))
            parts.append("Bus \(featured.no) \(eta.big == "Arr" ? "arriving now" : "in \(eta.big) minutes")")
        }
        return parts.joined(separator: ", ")
    }
}

/// 44pt rounded-square mint tile for the hero card's featured service.
private struct WSFeaturedTile: View {
    let no: String
    @Environment(\.ws) private var ws
    var body: some View {
        Text(no)
            .font(ws.sans(19, weight: .heavy))
            .foregroundStyle(ws.accent)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: 44, height: 44)
            .background(ws.accent.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ws.accent.opacity(0.4), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - "More bus stops" row

private struct WSMoreStopRow: View {
    let stop: NearbyStop
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    private var interchange: (name: String, codes: [String])? { wsInterchange(forStopName: stop.stopName) }
    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }

    var body: some View {
        // Quiet row (owner update 2026-07-24): name, stop chip, distance,
        // chevron — no ETA / service badge; that detail lives one tap away.
        Button { push(.busStop(code: stop.stopCode, service: nil)) } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(stop.stopName)
                            .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(ws.text)
                            .lineLimit(2)
                        if let code = interchange?.codes.first { LineBullet(code: code) }
                    }
                    HStack(spacing: 7) {
                        WSStopCodeChip(code: stop.stopCode, compact: true)
                        Text(fmtDistance(stop.distanceM))
                            .font(ws.mono(11, weight: .regular)).foregroundStyle(ws.dim)
                    }
                }
                Spacer(minLength: 8)
                WSIcon(glyph: .chevron, size: 14, color: ws.dim)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)   // shared row inset (matches MRT rows)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button(action: togglePin) {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "bookmark.slash" : "bookmark")
            }
            Button(role: .destructive) {
                withAnimation(SoftMotion.flow) { m.hideFromNearby(code: stop.stopCode) }
            } label: {
                Label("Hide from Nearby", systemImage: "eye.slash")
            }
        }
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: stop.stopCode, nickname: "")) }
    }
}

// MARK: - MRT station row

/// Max station-name width across the MRT card's rows → shared name column,
/// so every row's line badges start at the same x (owner call).
private struct WSNameColumnKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = max(value ?? 0, next) }
    }
}

private struct WSStationRow: View {
    let station: MrtGeoStation
    let distanceM: Int
    var nameColumnWidth: CGFloat? = nil
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// The first active disruption touching one of this station's lines, if any.
    private var alert: TrainAlert? {
        for code in station.codes {
            if let line = wsLine(forStationCode: code),
               let hit = store.trainAlerts.first(where: { $0.line == line }) {
                return hit
            }
        }
        return nil
    }

    var body: some View {
        // Quiet row (owner update 2026-07-24): name · line badges · a small
        // pulsing amber "!" only when a serving line is disrupted (details on
        // the station screen); healthy = plain silence. Right: distance + ›.
        // Names share a measured column so badges align across rows.
        Button { push(.mrtStation(station)) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(station.name)
                    .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.text)
                    .lineLimit(1)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: WSNameColumnKey.self, value: g.size.width)
                    })
                    .frame(width: nameColumnWidth, alignment: .leading)
                HStack(spacing: 5) {
                    ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                }
                if alert != nil {
                    ZStack {
                        Circle()
                            .stroke(WSTheme.amber.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        Text("!")
                            .font(ws.sans(11, weight: .bold)).foregroundStyle(WSTheme.amber)
                    }
                    .opacity(pulsing ? 0.45 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(SoftMotion.breathe) { pulsing = true }
                    }
                    .accessibilityLabel("Service disruption")
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text(fmtDistance(distanceM))
                        .font(ws.mono(11, weight: .regular)).foregroundStyle(ws.dim)
                    WSIcon(glyph: .chevron, size: 12, color: ws.dim)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)   // shared row inset (matches bus rows)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button { m.toggleMrtSaved(station) } label: {
                Label(m.isMrtSaved(station) ? "Remove from Saved" : "Save station",
                      systemImage: m.isMrtSaved(station) ? "bookmark.slash" : "bookmark")
            }
        }
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        var parts = ["\(station.name) MRT", wsLineNames(from: station.codes), fmtDistance(distanceM)]
        if let alert { parts.append(alert.title) } else { parts.append("normal service") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Soft-blue "4b" components (tokens live in WSSoftTheme.swift)

/// The one gradient hero: the closest stop NAMED as the title, then its next
/// three departures as a mini board, then the Open-stop capsule.
///
/// Reordered 2026-07-25 (owner): the card used to lead with the soonest bus
/// ("Bus 165 · Hougang Ctrl Int") while the stop name sat above it in 14pt,
/// so the biggest words on the screen answered a question the user hadn't
/// asked yet — WHERE am I standing comes before WHICH bus. The stop name is
/// now the title; the buses follow it as a board.
///
/// The countdown ring went with that change (owner call, same session). It
/// owned a third of the card to say one number, that number belonged to only
/// one of the several buses at the stop, and it forced every other departure
/// into a cramped "then …" strip. Three services with their own destinations
/// and their own times is strictly more of the answer in the same space; the
/// walk time it used to carry moved into the title caption, where it reads as
/// a property of the STOP (which it is) rather than of one bus.
private struct SoftHeroCard: View {
    let stop: NearbyStop
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    private var services: [Service] { store.servicesFor(stop.stopCode) }
    private var featured: Service? { board.first }
    /// The board: next three DISTINCT services by live ETA. One service can
    /// appear twice in the feed (this bus + the following one); the board is
    /// "which buses can I take", so the second sighting is noise here.
    private var board: [Service] {
        var seen = Set<String>()
        return services
            .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
            .filter { seen.insert($0.no).inserted }
            .prefix(3).map { $0 }
    }
    /// Freshness dip on the soonest time whenever this stop's feed refreshes.
    @State private var dataPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { push(.busStop(code: stop.stopCode, service: nil)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Title block. The glyph carries "bus stop" — it's the same
                // mark the Nearby rows and the widget use, so no eyebrow row
                // has to spell it out (owner 2026-07-25, "too much wording").
                // The caption carries how far and how long to walk; on this
                // screen the nearest thing is self-evidently the closest, so
                // no "CLOSEST" label either.
                HStack(alignment: .top, spacing: 10) {
                    WSIcon(glyph: .busSingle, size: 15, weight: .semibold, color: .white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.20),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.stopName)
                            .font(ws.sans(21, weight: .heavy)).tracking(-0.3)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                        // Fixed metadata format app-wide (owner 2026-07-25):
                        // STOP CODE · MIN WALK · METRES AWAY. The code is what
                        // you match against the pole you're standing at; the
                        // walk time is the decision; the metres are how you
                        // pick between two stops the same walk time apart.
                        Text(wsStopCodeLabel(stop.stopCode,
                                             suffix: "\(max(1, stop.walkMin)) min walk · \(fmtDistance(stop.distanceM)) away"))
                            .font(ws.sans(11.5, weight: .semibold)).monospacedDigit()
                            .opacity(0.8).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }

                if board.isEmpty {
                    Text("No live arrivals right now")
                        .font(ws.sans(14, weight: .semibold))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(board.enumerated()), id: \.element.id) { i, s in
                            if i > 0 {
                                Rectangle().fill(Color.white.opacity(0.20))
                                    .frame(height: 1)
                            }
                            SoftHeroBoardRow(no: s.no, dest: s.dest,
                                             etaBig: fmtETA(wsLiveETASec(s)).big,
                                             lead: i == 0,
                                             pulse: i == 0 && dataPulse)
                        }
                    }
                }

                Text("Open stop")
                    .font(ws.sans(12, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(SoftBlue.heroGradient,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: SoftBlue.blue.opacity(0.30), radius: 13, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(SoftPressStyle())
        // Live tell: every feed refresh for this stop dips the ring numeral —
        // the data itself signals it's fresh (owner 2026-07-25).
        .onChange(of: store.lastRefresh(stop.stopCode)) { _, _ in
            guard !reduceMotion else { return }
            dataPulse = true
            withAnimation(.easeOut(duration: 0.7)) { dataPulse = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        var parts = ["Closest stop", stop.stopName, fmtDistance(stop.distanceM)]
        if let f = featured {
            let eta = fmtETA(wsLiveETASec(f)).big
            parts.append("Bus \(f.no) \(eta == "Arr" ? "arriving now" : "in \(eta) minutes")")
        }
        return parts.joined(separator: ", ")
    }
}

/// White-card stop row: bus tile · name + code·min-walk · soonest-bus ETA
/// chip. Same save/hide context menu as the greendark rows.
private struct SoftStopRow: View {
    let stop: NearbyStop
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }

    var body: some View {
        Button { push(.busStop(code: stop.stopCode, service: nil)) } label: {
            HStack(spacing: 12) {
                // Bus glyph, not a bare "B" — the letter read as a mystery
                // badge in the field (owner 2026-07-25).
                WSIcon(glyph: .busSingle, size: 16, color: SoftBlue.blue)
                    .frame(width: 38, height: 38)
                    .background(SoftBlue.chipBg,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.stopName)
                        .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                        .lineLimit(1)
                    // Same metadata format as the hero. The row is narrower,
                    // so "away" is dropped from the distance — the field
                    // order already says what it is.
                    Text(wsStopCodeLabel(stop.stopCode,
                                         suffix: "\(max(1, stop.walkMin)) min walk · \(fmtDistance(stop.distanceM))"))
                        .font(ws.sans(11.5)).monospacedDigit().foregroundStyle(SoftBlue.sub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                // The row's "answer": the soonest departure at this stop —
                // service badge and time as two separate pieces so the
                // number never runs into the minutes (owner 2026-07-25).
                // Segmented pill with fixed segment widths: the number/time
                // boundary sits at the same x in every row (owner 2026-07-25).
                if let s = wsSoonest(store.servicesFor(stop.stopCode)) {
                    SoftBusTimePill(no: s.no, etaBig: fmtETA(wsLiveETASec(s)).big,
                                    noWidth: 46, timeWidth: 56)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .contextMenu {
            Button {
                if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) {
                    m.pins.remove(at: i)
                } else {
                    m.pins.append(Pin(code: stop.stopCode, nickname: ""))
                }
            } label: {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "bookmark.slash" : "bookmark")
            }
            Button(role: .destructive) {
                withAnimation(SoftMotion.flow) { m.hideFromNearby(code: stop.stopCode) }
            } label: {
                Label("Hide from Nearby", systemImage: "eye.slash")
            }
        }
    }
}

/// 2-up MRT tile: line pill(s), station name, distance · crowd.
private struct SoftMrtTile: View {
    let station: MrtGeoStation
    let distanceM: Int
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        Button { push(.mrtStation(station)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(station.codes.prefix(2), id: \.self) { LineBullet(code: $0) }
                }
                Text(station.name)
                    .font(ws.sans(13.5, weight: .bold)).foregroundStyle(SoftBlue.ink)
                    .lineLimit(1)
                Text(meta)
                    .font(ws.sans(11)).monospacedDigit().foregroundStyle(SoftBlue.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: SoftBlue.shadow, radius: 9, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel("\(station.name) MRT, \(meta)")
    }

    private var meta: String {
        var parts = [fmtDistance(distanceM)]
        if let crowd = store.wsCrowd(for: station), crowd != .unknown {
            parts.append(crowd.wsWord)
        }
        return parts.joined(separator: " · ")
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
