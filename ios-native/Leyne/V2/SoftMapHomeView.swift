// SoftMapHomeView — map-first Home (redesign exploration, branch
// `redesign-main-view`).
//
// Reframes the main view from "a list of stops" to a spatial map: you + the
// nearby bus stops + MRT stations as markers, with a draggable bottom panel of
// nearby departures. The panel reuses the existing SoftNearbyStopCard (live
// arrivals, save state, tap-to-open), so all the real data flows unchanged —
// only the *shell* is new.
//
// v1 scope (prototype to react to):
//   • Full-screen Map: user location + stop markers + MRT markers, tap a marker
//     to open that stop / station.
//   • Bottom panel: peek ⇄ expanded (tap the grabber), scrollable list of the
//     nearby stop cards.
//   • Nav bar: title + search + alerts bell.
// Deferred to v2: a draggable-by-finger sheet, a tap-marker preview card, the
// inline native ad (it's List-specific today), light-mode tuning.

import SwiftUI
import MapKit

struct SoftMapHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @StateObject private var loc = LocationManager.shared

    let onOpenStop: (String) -> Void
    let onOpenBus: (String, String) -> Void
    let onOpenMrtStation: (MrtGeoStation) -> Void
    let onOpenAlerts: () -> Void
    let onOpenSearch: () -> Void

    /// Camera follows the user by default, falling back to a sensible auto frame
    /// before the first fix arrives.
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var panelExpanded = false

    private var t: Theme { m.t }

    // MARK: Data

    private var nearbyStops: [NearbyStop] {
        let hidden = m.hiddenNearby
        return ds.nearby
            .filter { !hidden.contains($0.stopCode) }
            .sorted { $0.distanceM < $1.distanceM }
    }

    private var nearbyStations: [MrtGeoStation] {
        guard let here = loc.location else { return [] }
        return MrtGeo.nearestStations(to: here.coordinate, limit: 6,
                                      withinMeters: max(m.searchRadiusM, 1200))
            .map { $0.station }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                mapLayer.ignoresSafeArea()
                departuresPanel(maxHeight: geo.size.height)
            }
        }
        .navigationTitle("SG Transit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { searchButton }
            ToolbarItem(placement: .topBarTrailing) { alertsBell }
        }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l) }
            ds.prefetchNearbyArrivals()
            warmArrivals()
        }
        .onChange(of: loc.location) { _, new in
            if let l = new { ds.updateNearby(l); ds.prefetchNearbyArrivals() }
        }
        .onChange(of: ds.nearby) { _, _ in warmArrivals() }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(nearbyStops) { stop in
                if let c = coord(stop.stopCode) {
                    Annotation(stop.stopName.isEmpty ? stop.stopCode : stop.stopName,
                               coordinate: c, anchor: .center) {
                        stopMarker(stop)
                    }
                }
            }
            ForEach(nearbyStations) { st in
                Annotation(st.name,
                           coordinate: CLLocationCoordinate2D(latitude: st.lat,
                                                              longitude: st.lon),
                           anchor: .center) {
                    mrtMarker(st)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton() }
    }

    private func coord(_ code: String) -> CLLocationCoordinate2D? {
        guard let s = ds.stopByCode[code] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

    private func stopMarker(_ stop: NearbyStop) -> some View {
        Button {
            fb.select(); m.addRecent(stop.stopName); onOpenStop(stop.stopCode)
        } label: {
            Image(systemName: "bus.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(colors: [Color(hex: "2563EB"), Color(hex: "06B6D4")],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func mrtMarker(_ st: MrtGeoStation) -> some View {
        Button {
            fb.select(); onOpenMrtStation(st)
        } label: {
            Image(systemName: "tram.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: "E22319"), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom panel

    private func departuresPanel(maxHeight: CGFloat) -> some View {
        let height = panelExpanded ? maxHeight * 0.62 : 248
        return VStack(spacing: 0) {
            grabber
            panelHeader
            ScrollView {
                LazyVStack(spacing: 10) {
                    if nearbyStops.isEmpty {
                        Text(loc.location == nil
                             ? "Turn on location to see stops near you."
                             : "No stops in range right now.")
                            .font(t.sans(13))
                            .foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(nearbyStops.prefix(12)) { stop in
                            card(stop)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial,
                    in: UnevenRoundedRectangle(cornerRadii:
                        .init(topLeading: 22, topTrailing: 22), style: .continuous))
        .overlay(
            UnevenRoundedRectangle(cornerRadii:
                .init(topLeading: 22, topTrailing: 22), style: .continuous)
                .stroke(t.line, lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: panelExpanded)
    }

    private var grabber: some View {
        Capsule()
            .fill(t.faint)
            .frame(width: 40, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { fb.select(); panelExpanded.toggle() }
            .accessibilityLabel(panelExpanded ? "Collapse list" : "Expand list")
    }

    private var panelHeader: some View {
        let located = loc.location != nil
        return HStack(spacing: 6) {
            Image(systemName: located ? "location.fill" : "location.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(located ? t.meBlue : t.dim)
            Text("Leaving near you")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
            if located {
                Text("·").font(t.sans(13)).foregroundStyle(t.faint)
                Circle().fill(Color(hex: "22C55E")).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(t.mono(10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Color(hex: "22C55E"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func card(_ stop: NearbyStop) -> some View {
        let code = stop.stopCode
        let name = stop.stopName.isEmpty ? code : stop.stopName
        return SoftNearbyStopCard(
            t: t,
            name: name,
            code: code,
            road: ds.roadName(code),
            walkMin: stop.walkMin,
            arrivals: rankedArrivals(code),
            feed: feed(code),
            highlight: false,
            tick: m.tick,
            onTap: { fb.select(); m.addRecent(name); onOpenStop(code) },
            isSaved: m.isPinned(code)
        )
    }

    // MARK: Toolbar

    private var searchButton: some View {
        Button {
            fb.select(); onOpenSearch()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search stops, buses, stations")
    }

    private var alertsBell: some View {
        Button {
            fb.select(); onOpenAlerts()
        } label: {
            Image(systemName: m.unseenAlertCount > 0 ? "bell.badge.fill" : "bell.fill")
        }
        .accessibilityLabel(m.unseenAlertCount > 0
            ? "Alerts, \(m.unseenAlertCount) new" : "Alerts")
    }

    // MARK: Arrivals (mirrors SoftHomeView's helpers)

    private func rankedArrivals(_ code: String) -> [RankedArrival] {
        let services = m.liveServices(code: code, tracked: [])
        func isFav(_ s: Service) -> Bool {
            m.isFavService(no: s.no, stop: code) || m.isFavService(no: s.no, stop: nil)
        }
        let favs = services.filter(isFav)
        let rest = services.filter { !isFav($0) }
        return (favs + rest).prefix(3).map { RankedArrival(service: $0, fav: isFav($0)) }
    }

    private func feed(_ code: String) -> Freshness { Freshness.from(ds.lastRefresh(code)) }

    private func warmArrivals() {
        for stop in nearbyStops.prefix(12) { ds.ensureArrivals(stop: stop.stopCode) }
    }
}
