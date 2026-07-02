// WhereSia — Home · Nearby (screen 1).
//
// Date eyebrow + title, search bar, then one scroll with two sections: a
// horizontal strip of nearby MRT stations (always visible — no filter to
// find them) and the nearby bus stop list. Each stop row: name, code · road ·
// distance, route tiles capped with +N, and the soonest arrival with an
// inline crowd gauge + word (or "Bus A & B" when several are arriving at
// once). Wired to DataStore.nearby + MrtGeo.nearestStations.

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
                LazyVStack(spacing: 0) {
                    mrtSection
                    WSSectionHeader(label: "Bus stops",
                                    meta: WSFmt.upd(store.newestRefresh(amongst: store.nearby.map(\.stopCode)),
                                                    use24h: m.use24h),
                                    live: store.newestRefresh(amongst: store.nearby.map(\.stopCode)) != nil)
                        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 8)
                    busList
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
                store.prefetchNearbyArrivals()
                store.wsWarmCrowd(for: nearbyStations.map(\.station))
            }
        }
    }

    private func bootstrap() {
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
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.dateEyebrow.string(from: Date()).uppercased())
                .font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
            Text("Nearby").font(ws.sans(26, weight: .heavy)).foregroundStyle(ws.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Horizontal strip of the nearest stations — always on screen, so rail is
    /// never buried under a long bus list or hidden behind a filter.
    @ViewBuilder private var mrtSection: some View {
        if !nearbyStations.isEmpty {
            WSSectionHeader(label: "MRT")
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(nearbyStations, id: \.station.id) { item in
                        MrtCard(station: item.station, distanceM: item.distanceM, walkMin: item.walkMin)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private var busStops: [NearbyStop] {
        store.nearby.filter { !m.hiddenNearby.contains($0.stopCode) }
    }

    @ViewBuilder private var busList: some View {
        if busStops.isEmpty {
            emptyHint(coord == nil ? "Turn on location to see stops near you."
                                   : "Finding stops near you…")
        } else {
            ForEach(busStops) { stop in
                StopRow(stop: stop)
                WSRowDivider().padding(.horizontal, 22)
            }
        }
        // The way back from the long-press "Hide from Nearby" action — without
        // this a hidden stop is gone for good (the Me tab is no more).
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

// MARK: - Bus stop row

private struct StopRow: View {
    let stop: NearbyStop
    var tag: String? = nil
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    private var tiles: [String] {
        let fromRoutes = store.servicesAtStop(stop.stopCode)
        return fromRoutes.isEmpty ? store.servicesFor(stop.stopCode).map(\.no) : fromRoutes
    }

    var body: some View {
        // Under @Observable, only a view that itself reads `tick` re-renders
        // each second — this is a separately-tracked child view (not part of
        // WSHomeView's own body), and it renders a live ETA countdown in
        // `whenColumn`, so it needs its own read.
        let _ = m.tick
        Button { push(.busStop(code: stop.stopCode)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if let tag {
                        Text(tag).font(ws.mono(10)).tracking(1.2).foregroundStyle(ws.dim)
                            .padding(.bottom, 3)
                    }
                    Text(stop.stopName).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(subline).font(ws.mono(11.5, weight: .medium)).tracking(0.2).foregroundStyle(ws.dim)
                    if !tiles.isEmpty { TileRow(services: tiles).padding(.top, 9) }
                }
                Spacer(minLength: 8)
                whenColumn
            }
            // Horizontal padding lives INSIDE the row (not at the call site)
            // so the long-press lift shows a properly inset card — a preview
            // snapshotted without it had text flush against its edges
            // (owner-reported UI bug).
            .padding(.horizontal, 22).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Long-press: quick actions without leaving Home. "Hide" feeds the
        // existing hiddenNearby filter; the list footer offers the way back.
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
    }

    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: stop.stopCode, nickname: "")) }
    }

    private var subline: String {
        let road = store.roadName(stop.stopCode)
        var parts = [stop.stopCode]
        if !road.isEmpty { parts.append(road.uppercased()) }
        if stop.distanceM > 0 { parts.append(fmtDistance(stop.distanceM)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var whenColumn: some View {
        let services = store.servicesFor(stop.stopCode)
        // Everything inside fmtETA's "Arr" window (< 60 s), soonest first.
        let arriving = services.filter { wsLiveETASec($0) < 60 }
                               .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
        if arriving.count >= 2 {
            // Several buses at once: name them all instead of silently showing
            // one. The crowd gauge is per-bus, so it drops out here.
            VStack(alignment: .trailing, spacing: 5) {
                Text("Arr").font(ws.mono(19, weight: .bold)).foregroundStyle(ws.text)
                Text(arrivingLabel(arriving)).font(ws.mono(10)).foregroundStyle(ws.dim)
            }
        } else if let soonest = wsSoonest(services) {
            let eta = fmtETA(wsLiveETASec(soonest))
            VStack(alignment: .trailing, spacing: 5) {
                (Text(eta.big).font(ws.mono(19, weight: .bold)).foregroundStyle(ws.text)
                 + Text(eta.big == "Arr" ? "" : " min").font(ws.mono(11, weight: .semibold)).foregroundStyle(ws.dim))
                HStack(spacing: 6) {
                    Text("Bus \(soonest.no) ·").font(ws.mono(10)).foregroundStyle(ws.dim)
                    CrowdGauge(fraction: soonest.load.wsFraction, width: 24)
                    Text(soonest.load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                }
            }
        } else {
            Text("—").font(ws.mono(19, weight: .bold)).foregroundStyle(ws.dim)
        }
    }

    /// "Bus 174 & 165" (+N when more than two are arriving together).
    private func arrivingLabel(_ arriving: [Service]) -> String {
        let nos = arriving.map(\.no)
        let shown = nos.prefix(2).joined(separator: " & ")
        let extra = nos.count - 2
        return extra > 0 ? "Bus \(shown) +\(extra)" : "Bus \(shown)"
    }
}

// MARK: - MRT station card (horizontal strip)

private struct MrtCard: View {
    let station: MrtGeoStation
    let distanceM: Int
    let walkMin: Int
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        Button { push(.mrtStation(station)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                    Spacer(minLength: 0)
                    if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                        CrowdGauge(fraction: crowd.wsFraction, width: 22)
                        Text(crowd.wsWord).font(ws.mono(10, weight: .bold)).foregroundStyle(ws.dim)
                    }
                }
                Text(station.name)
                    .font(ws.sans(15, weight: .bold)).foregroundStyle(ws.text)
                    .lineLimit(1)
                Text(subline).font(ws.mono(10.5)).tracking(0.3).foregroundStyle(ws.dim)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: 186, alignment: .leading)
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
        distanceM > 0 ? "\(fmtDistance(distanceM)) · \(walkMin) min walk".uppercased()
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
