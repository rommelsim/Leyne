// WhereSia — Home · Nearby (screen 1).
//
// Brand header, search bar, filter chips (All / Bus / MRT / Saved), then a list
// of nearby stops + MRT stations. Each stop row: name, code · road · distance,
// route tiles capped with +N, and the soonest arrival with an inline crowd
// gauge + word. Wired to DataStore.nearby + MrtGeo.nearestStations.

import SwiftUI
import CoreLocation

struct WSHomeView: View {
    var onSearch: () -> Void
    var onOpenMe: () -> Void = {}

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var filter = 0   // 0 All · 1 Bus · 2 MRT · 3 Saved

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
            WSFilterChips(options: ["All", "Bus", "MRT", "Saved"], selection: $filter)
                .padding(.horizontal, 22).padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    WSSectionHeader(label: "Nearby",
                                    meta: WSFmt.upd(store.newestRefresh(amongst: store.nearby.map(\.stopCode)),
                                                    use24h: m.use24h))
                        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
                    content
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
    }

    private func bootstrap() {
        location.start()
        if location.status == .notDetermined { location.requestPermission() }
        if let loc = location.location { store.updateNearby(loc) }
        store.ensureRoutes()
        store.prefetchNearbyArrivals()
        store.wsWarmCrowd(for: nearbyStations.map(\.station))
    }

    // MARK: header

    private var header: some View {
        HStack {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 11).fill(ws.text)
                    .frame(width: 38, height: 38)
                    .overlay(WSIcon(glyph: .busSingle, size: 22, color: ws.bg))
                VStack(alignment: .leading, spacing: 1) {
                    Text("WHERESIA").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                    Text("Nearby").font(ws.sans(20, weight: .heavy)).foregroundStyle(ws.text)
                }
            }
            Spacer()
            WSHairButton(glyph: .me, action: onOpenMe)
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    private var searchBar: some View {
        Button(action: onSearch) {
            HStack(spacing: 11) {
                WSIcon(glyph: .search, size: 19, color: ws.dim)
                Text("Search stop, bus or MRT")
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

    @ViewBuilder
    private var content: some View {
        switch filter {
        case 1: busList
        case 2: mrtList
        case 3: savedList
        default:
            busList
            mrtList
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
                    .padding(.horizontal, 22)
                WSRowDivider().padding(.horizontal, 22)
            }
        }
    }

    @ViewBuilder private var mrtList: some View {
        ForEach(nearbyStations, id: \.station.id) { item in
            MrtRow(station: item.station, distanceM: item.distanceM)
                .padding(.horizontal, 22)
            WSRowDivider().padding(.horizontal, 22)
        }
    }

    @ViewBuilder private var savedList: some View {
        let pins = m.pins
        if pins.isEmpty && m.savedMrtStations.isEmpty {
            emptyHint("Nothing saved yet. Tap the bookmark on a stop or station.")
        } else {
            ForEach(pins, id: \.code) { pin in
                StopRow(stop: NearbyStop(id: pin.code, stopName: store.stopName(pin.code),
                                         stopCode: pin.code, distanceM: 0, walkMin: 0,
                                         services: store.servicesFor(pin.code)),
                        tag: pin.nickname.isEmpty ? nil : pin.nickname.uppercased())
                    .padding(.horizontal, 22)
                WSRowDivider().padding(.horizontal, 22)
            }
            ForEach(m.savedMrtStations) { st in
                MrtRow(station: st, distanceM: 0).padding(.horizontal, 22)
                WSRowDivider().padding(.horizontal, 22)
            }
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
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if let soonest = wsSoonest(services) {
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
}

// MARK: - MRT station row

private struct MrtRow: View {
    let station: MrtGeoStation
    let distanceM: Int
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        Button { push(.mrtStation(station)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.name).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(subline).font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                    HStack(spacing: 5) {
                        ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                    }
                }
                Spacer(minLength: 8)
                if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                    WSChip(gauge: crowd.wsFraction, text: crowd.wsWord)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subline: String {
        var parts: [String] = []
        if distanceM > 0 { parts.append(fmtDistance(distanceM)) }
        let lines = wsLineNames(from: station.codes)
        if !lines.isEmpty { parts.append(lines) }
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
