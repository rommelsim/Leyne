// WhereSia — Nearby Map (iOS-only feature).
//
// A full-bleed MapKit browse surface pushed from Home: every bus stop and
// MRT/LRT station around the visible region, tappable into a floating glass
// card with live arrivals (or station crowd) and a push into the existing
// Stop / Station screens. iOS-exclusive by owner call (2026-07-04) — Android
// deliberately ships without a map, so this has no parity obligation.
//
// Soft-blue "4b" restyle (owner call, 2026-07-25): the screen now matches the
// rest of the app's tinted-ground / white-card language instead of the old
// forced-dark "greendark" cartography — the map renders MapKit's standard
// light style, chrome is white floating cards/capsules (SoftIconButton,
// softCard), and stop dots use SoftBlue.blue as the one accent. MRT/LRT
// stations keep their official line colours (identity, never restyled). The
// header stays a bespoke floating overlay rather than the system nav bar, so
// the map can still bleed full-screen under it.

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Selection

enum WSMapSelection: Equatable {
    case stop(String)          // bus stop code
    case mrt(MrtGeoStation)
}

// MARK: - Screen

struct WSMapView: View {

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    /// Ties the map to controls hosted OUTSIDE it. MapKit lays `.mapControls`
    /// out inside the map's own frame, and this map deliberately ignores the
    /// top safe area so it bleeds behind the nav bar — which parked the
    /// location button on top of the battery icon (owner 2026-07-25). A map
    /// scope lets the same native control live in the safe-area-respecting
    /// overlay instead, next to the other floating chips.
    @Namespace private var mapScope

    @State private var camera: MapCameraPosition = .region(Self.islandRegion)
    @State private var region: MKCoordinateRegion = Self.islandRegion
    @State private var selection: WSMapSelection? = nil

    /// Whole-island fallback when location is off — the map is still a
    /// browse surface without a blue dot.
    private static let islandRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 1.3421, longitude: 103.8198),
        span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.42))

    /// Above this span, per-stop markers would be confetti — bus stops hide
    /// behind a "zoom in" hint and only the rail network stays visible.
    private static let stopVisibleSpan: Double = 0.09
    /// Between this span and `stopVisibleSpan`, stops render as clustered
    /// count badges ("6 stops") instead of individual dots — equal-weight dot
    /// confetti at mid-zoom read as noise (owner field test 2026-07-24).
    private static let clusterSpan: Double = 0.030
    /// Above this span, station bullets collapse to small colour dots.
    private static let bulletSpan: Double = 0.12

    private var stopsVisible: Bool { region.span.latitudeDelta < Self.stopVisibleSpan }
    private var clusteringActive: Bool {
        stopsVisible && region.span.latitudeDelta >= Self.clusterSpan
    }

    var body: some View {
        // The Map itself ignores the top safe area so it bleeds fully behind
        // the status bar / Dynamic Island; the ZStack around it does NOT, so
        // the floating back button + title stay clear of the notch instead
        // of inheriting the Map's ignored inset.
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 8) {
                zoomHint
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) { bottomStack }
        .mapScope(mapScope)   // lets the overlay's MapUserLocationButton drive this map
        .sensoryFeedback(.selection, trigger: selection)
        // NATIVE nav bar (owner 2026-07-25) — the floating white back circle
        // and the "Around <area>" capsule that used to sit over the map are
        // gone; the system bar carries both, and with a real back button the
        // edge-swipe pop works without `enableSwipeBack()`.
        .navigationTitle(areaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: bootstrap)
        // The freshness window inside ensureArrivals turns the per-second
        // tick into an actual refetch ~every 25s for the open card.
        .onChange(of: m.tick) { _, _ in
            if case .stop(let code) = selection {
                store.ensureArrivals(stop: code, silent: true)
            }
        }
    }

    // MARK: top chrome

    /// "Around <area>" — nearest bus stop's road, falling back to the
    /// nearest MRT station, then a plain "Around you". Same fallback chain
    /// as Home's header caption (`WSHomeView.headerCaption`), minus the
    /// "updated Ns ago" clause which doesn't apply to a map title.
    private var areaTitle: String {
        let roadArea = store.nearby.first
            .map { store.roadName($0.stopCode) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if let roadArea { return "Around \(roadArea)" }
        if let c = location.location?.coordinate,
           let nearest = MrtGeo.nearestStations(to: c, limit: 1).first {
            return "Around \(nearest.station.name)"
        }
        return "Around you"
    }

    // MARK: map + annotations

    private var map: some View {
        let stops = visibleStops
        let compact = region.span.latitudeDelta >= Self.bulletSpan
        return Map(position: $camera, scope: mapScope) {
            UserAnnotation()

            ForEach(MrtGeo.all) { st in
                Annotation(st.name, coordinate: st.coordinate, anchor: .center) {
                    Button { select(.mrt(st)) } label: {
                        MrtMarker(station: st, compact: compact,
                                  selected: selection == .mrt(st))
                    }
                    .buttonStyle(SoftPressStyle())
                    .accessibilityLabel("\(st.name) MRT station")
                }
                .annotationTitles(.hidden)
            }

            if clusteringActive {
                // Mid-zoom: count badges instead of dot confetti. Tapping a
                // badge zooms into its patch, where individual dots take over.
                ForEach(stopClusters) { cluster in
                    Annotation("\(cluster.count) stops", coordinate: cluster.center,
                               anchor: .center) {
                        Button { zoomInto(cluster) } label: {
                            ClusterBadge(count: cluster.count)
                        }
                        .buttonStyle(SoftPressStyle())
                        .accessibilityLabel("\(cluster.count) bus stops — zoom in")
                    }
                    .annotationTitles(.hidden)
                }
            } else {
                let labeled = labeledStopCodes(stops)
                let nearest = store.nearby.first?.stopCode
                ForEach(stops, id: \.BusStopCode) { stop in
                    Annotation(stop.Description, coordinate: stop.coordinate, anchor: .center) {
                        // First tap selects (card appears); tapping the SAME
                        // pin again goes into the stop — the gesture people
                        // reach for when the card is already open.
                        Button {
                            if selectedStopCode == stop.BusStopCode {
                                push(.busStop(code: stop.BusStopCode, service: nil))
                            } else {
                                select(.stop(stop.BusStopCode))
                            }
                        } label: {
                            StopMarker(selected: selectedStopCode == stop.BusStopCode,
                                       nearest: nearest == stop.BusStopCode,
                                       label: labeled.contains(stop.BusStopCode)
                                           ? stop.Description : nil)
                        }
                        .buttonStyle(SoftPressStyle())
                        .accessibilityLabel("Bus stop \(stop.Description)")
                    }
                    .annotationTitles(.hidden)
                }
            }

            // Live GPS of buses approaching the selected stop (LTA NextBus).
            ForEach(liveBuses, id: \.no) { bus in
                Annotation("Bus \(bus.no)", coordinate: bus.coord, anchor: .center) {
                    LiveBusMarker(no: bus.no)
                }
                .annotationTitles(.hidden)
            }

        }
        .mapStyle(.standard(elevation: .flat,
                            pointsOfInterest: .excludingAll,
                            showsTraffic: false))
        // Default in-map placement is off: the controls are hosted in the
        // bottom overlay via `mapScope` (see the property's note).
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { ctx in
            region = ctx.region
        }
    }

    /// Bus stops inside the visible region (padded), capped to the nearest 80
    /// so a dense CBD viewport doesn't drown MapKit in annotation views.
    private var visibleStops: [LTABusStop] {
        guard stopsVisible, !store.stopByCode.isEmpty else { return [] }
        let c = region.center
        let dLat = region.span.latitudeDelta * 0.6
        let dLon = region.span.longitudeDelta * 0.6
        var inBox = store.stopByCode.values.filter {
            abs($0.Latitude - c.latitude) < dLat && abs($0.Longitude - c.longitude) < dLon
        }
        if inBox.count > 80 {
            inBox = inBox
                .map { ($0, haversine(c.latitude, c.longitude, $0.Latitude, $0.Longitude)) }
                .sorted { $0.1 < $1.1 }
                .prefix(80)
                .map(\.0)
        }
        return inBox
    }

    private var selectedStopCode: String? {
        if case .stop(let code) = selection { return code }
        return nil
    }

    // MARK: clustering + labels

    struct StopCluster: Identifiable {
        let id: String            // grid-cell key
        let count: Int
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
    }

    /// Grid-cluster every stop in the (padded) viewport: ~6 cells across,
    /// each cell one badge at its members' centroid. Cheap enough to run per
    /// camera settle — it's arithmetic over the in-box subset only.
    private var stopClusters: [StopCluster] {
        guard !store.stopByCode.isEmpty else { return [] }
        let c = region.center
        let dLat = region.span.latitudeDelta * 0.6
        let dLon = region.span.longitudeDelta * 0.6
        let cellLat = region.span.latitudeDelta / 6
        let cellLon = region.span.longitudeDelta / 6
        var cells: [String: (count: Int, sumLat: Double, sumLon: Double)] = [:]
        for s in store.stopByCode.values
        where abs(s.Latitude - c.latitude) < dLat && abs(s.Longitude - c.longitude) < dLon {
            let key = "\(Int((s.Latitude / cellLat).rounded(.down)))|\(Int((s.Longitude / cellLon).rounded(.down)))"
            var cell = cells[key] ?? (0, 0, 0)
            cell.count += 1
            cell.sumLat += s.Latitude
            cell.sumLon += s.Longitude
            cells[key] = cell
        }
        return cells.map { key, cell in
            StopCluster(id: key, count: cell.count,
                        center: CLLocationCoordinate2D(
                            latitude: cell.sumLat / Double(cell.count),
                            longitude: cell.sumLon / Double(cell.count)),
                        span: MKCoordinateSpan(latitudeDelta: cellLat,
                                               longitudeDelta: cellLon))
        }
    }

    /// Tap on a cluster badge → zoom into its patch, landing below
    /// `clusterSpan` so the badges expand into individual dots.
    private func zoomInto(_ cluster: StopCluster) {
        let span = MKCoordinateSpan(
            latitudeDelta: max(cluster.span.latitudeDelta * 1.6, Self.clusterSpan * 0.65),
            longitudeDelta: max(cluster.span.longitudeDelta * 1.6, Self.clusterSpan * 0.9))
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(center: cluster.center, span: span))
        }
    }

    /// Only the few stops nearest the viewport centre carry a name label —
    /// labelling all ~80 dots turns the map into a word cloud.
    private func labeledStopCodes(_ stops: [LTABusStop]) -> Set<String> {
        let c = region.center
        return Set(stops
            .map { ($0.BusStopCode, haversine(c.latitude, c.longitude, $0.Latitude, $0.Longitude)) }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map(\.0))
    }

    private var liveBuses: [(no: String, coord: CLLocationCoordinate2D)] {
        guard let code = selectedStopCode else { return [] }
        return store.servicesFor(code).compactMap { s in
            guard let lat = s.busLat, let lon = s.busLon,
                  abs(lat) > 0.01, abs(lon) > 0.01 else { return nil }  // LTA sends 0,0 for no telemetry
            return (s.no, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    // Follow-bus (camera lock onto the soonest approaching bus, its "Following"
    // toggle and the dashed bus→stop approach line) was DELETED 2026-07-25 —
    // owner: "What is Follow Bus? remove that". The live bus dots stay; they
    // answer "where is it" without hijacking the camera.

    // MARK: actions

    private func bootstrap() {
        location.start()
        if let here = location.location?.coordinate {
            let r = MKCoordinateRegion(center: here,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))
            camera = .region(r)
            region = r
        }
    }

    private func select(_ sel: WSMapSelection) {
        withAnimation(SoftMotion.flow) { selection = sel }
        if case .stop(let code) = sel {
            store.ensureArrivals(stop: code)
        }
        // Ease the marker into the upper half so the card never covers it.
        let target: CLLocationCoordinate2D
        switch sel {
        case .stop(let code):
            guard let s = store.stopByCode[code] else { return }
            target = s.coordinate
        case .mrt(let st):
            target = st.coordinate
        }
        let span = MKCoordinateSpan(
            latitudeDelta: min(region.span.latitudeDelta, 0.012),
            longitudeDelta: min(region.span.longitudeDelta, 0.012))
        let center = CLLocationCoordinate2D(
            latitude: target.latitude - span.latitudeDelta * 0.18,
            longitude: target.longitude)
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // `recenter()` was deleted with the custom floating location button —
    // MapUserLocationButton in `.mapControls` does this natively now.

    // MARK: overlays

    @ViewBuilder private var zoomHint: some View {
        if !stopsVisible {
            Text("ZOOM IN FOR BUS STOPS")
                .font(ws.sans(11, weight: .bold)).tracking(0.6)
                .foregroundStyle(SoftBlue.sub)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(SoftBlue.card, in: Capsule())
                .shadow(color: SoftBlue.shadow, radius: 6, y: 3)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            // MapKit's own recentre control — native button, but placed here
            // so it clears the status bar and sits with the map's other
            // floating chrome. It can't ASK for permission, so while we don't
            // have it the ask takes its place.
            HStack {
                Spacer(minLength: 0)
                if location.authorized {
                    MapUserLocationButton(scope: mapScope)
                } else {
                    Button("Show my location", systemImage: "location") {
                        location.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(SoftBlue.blue)
                }
            }

            switch selection {
            case .stop(let code):
                WSMapStopCard(code: code,
                              onOpen: { push(.busStop(code: code, service: nil)) },
                              onClose: { withAnimation(SoftMotion.flow) { selection = nil } })
            case .mrt(let st):
                WSMapMrtCard(station: st,
                             onOpen: { push(.mrtStation(st)) },
                             onClose: { withAnimation(SoftMotion.flow) { selection = nil } })
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(SoftMotion.flow, value: selection)
    }
}

// MARK: - Markers

/// Bus-stop dot with a deliberate weight hierarchy (field test 2026-07-24 —
/// equal-weight dots read as noise): the SELECTED or NEAREST stop is larger
/// and fully SoftBlue.blue; every other stop is a small, muted dot. The few
/// stops nearest the viewport centre also carry a name label.
private struct StopMarker: View {
    var selected: Bool
    var nearest: Bool = false
    var label: String? = nil
    @Environment(\.ws) private var ws

    private var emphasized: Bool { selected || nearest }
    /// Bus stops are INK, never blue (owner 2026-07-25): MapKit's user-location
    /// dot is system blue, and a map full of blue dots made "where I am" and
    /// "a bus stop" the same mark. Blue on this screen now means you.
    private var dotColor: Color { SoftBlue.ink }

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(dotColor.opacity(emphasized ? 1 : 0.55))
                .frame(width: emphasized ? 17 : 9, height: emphasized ? 17 : 9)
                .overlay(Circle().stroke(.white.opacity(emphasized ? 0.9 : 0.6),
                                          lineWidth: emphasized ? 2 : 1))
                .shadow(color: SoftBlue.shadow, radius: emphasized ? 6 : 2)
                .background { if selected { WSPing(color: SoftBlue.ink) } }
            if let label {
                Text(label)
                    .font(ws.sans(9.5, weight: .semibold))
                    .foregroundStyle(SoftBlue.ink.opacity(emphasized ? 0.95 : 0.75))
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(SoftBlue.card))
                    .shadow(color: SoftBlue.shadow, radius: 3, y: 1)
                    .fixedSize()
            }
        }
        // Visual dot stays tiny per the mock; the tap target doesn't.
        .frame(minWidth: 34, minHeight: 34)
        .contentShape(Rectangle())
    }
}

/// Mid-zoom cluster badge — "6 stops" in a white soft-blue capsule. A count
/// is data, so the numeral carries the accent; the unit word stays quiet.
private struct ClusterBadge: View {
    let count: Int
    @Environment(\.ws) private var ws

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(ws.sans(12, weight: .bold)).monospacedDigit()
                .foregroundStyle(SoftBlue.blue)
            Text(count == 1 ? "stop" : "stops")
                .font(ws.sans(10.5, weight: .semibold)).foregroundStyle(SoftBlue.sub)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(SoftBlue.card, in: Capsule())
        .shadow(color: SoftBlue.shadow, radius: 5, y: 2)
        .contentShape(Capsule())
    }
}

/// Line-coloured station mark: a small colour dot when zoomed out (keeps a
/// dense CBD viewport from turning into confetti), a rounded-square "M"
/// badge in the line's brand colour once close enough to read.
private struct MrtMarker: View {
    let station: MrtGeoStation
    var compact: Bool
    var selected: Bool
    @Environment(\.ws) private var ws

    private var lineColor: Color { WSLine.color(forStationCode: station.codes.first ?? "") }

    var body: some View {
        Group {
            if compact && !selected {
                Circle()
                    .fill(lineColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: SoftBlue.shadow, radius: 3, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(lineColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("M")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(selected ? 0.95 : 0.6), lineWidth: selected ? 2 : 1))
                    .background { if selected { WSPing(cornerRadius: 6, color: lineColor) } }
                    .shadow(color: SoftBlue.shadow, radius: 4, y: 1)
            }
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
}

/// A bus that is actually on the road right now — SoftBlue.blue is the
/// screen's one accent, so it doubles as the "live" tell here.
private struct LiveBusMarker: View {
    let no: String
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 4) {
            WSIcon(glyph: .busSingle, size: 10, weight: .regular, color: SoftBlue.blue)
            Text(no).font(ws.sans(11, weight: .bold)).monospacedDigit()
                .foregroundStyle(SoftBlue.ink)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(SoftBlue.card, in: Capsule())
        .overlay(Capsule().stroke(SoftBlue.blue, lineWidth: 1.5))
        .shadow(color: SoftBlue.shadow, radius: 4, y: 2)
        .accessibilityLabel("Bus \(no), live position")
    }
}

// MARK: - Bus stop card

private struct WSMapStopCard: View {
    let code: String
    var onOpen: () -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws

    var body: some View {
        let _ = m.tick   // live per-second countdowns
        let services = store.servicesFor(code)
        let soonest = services
            .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
            .prefix(3)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.stopName(code))
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                        .lineLimit(1)
                    Text(subline)
                        .font(ws.sans(11.5)).monospacedDigit()
                        .foregroundStyle(SoftBlue.sub)
                }
                Spacer(minLength: 8)
                Button(action: togglePin) {
                    WSIcon(glyph: isPinned ? .bookmarkFilled : .bookmark, size: 17,
                           color: isPinned ? SoftBlue.blue : SoftBlue.ink.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)   // 44pt hit area overhangs the 36pt tile
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .frame(width: 36, height: 36)   // layout stays tile-sized
                .accessibilityLabel(isPinned ? "Remove from Saved" : "Save stop")
                Button(action: onClose) {
                    WSIcon(glyph: .close, size: 15, color: SoftBlue.sub)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)   // 44pt hit area overhangs the 36pt tile
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .frame(width: 36, height: 36)   // layout stays tile-sized
                .accessibilityLabel("Close")
            }
            .padding(.top, 14).padding(.horizontal, 16)

            Group {
                if soonest.isEmpty {
                    Text(store.newestRefresh(amongst: [code]) == nil
                         ? "Fetching live arrivals…"
                         : "No buses due right now.")
                        .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(soonest)) { s in
                            HStack(spacing: 10) {
                                Text(s.dest)
                                    .font(ws.sans(13, weight: .semibold))
                                    .foregroundStyle(SoftBlue.sub).lineLimit(1)
                                Spacer(minLength: 8)
                                SoftBusTimePill(no: s.no, etaBig: fmtETA(wsLiveETASec(s)).big)
                            }
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                // Walking directions in Apple Maps (owner 2026-07-25) — the
                // one thing this app deliberately doesn't do itself.
                Button(action: openDirections) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(ws.sans(13.5, weight: .bold)).foregroundStyle(SoftBlue.blue)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(SoftBlue.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("Walking directions in Apple Maps")

                Button(action: onOpen) {
                    Text("Open stop")
                        .font(ws.sans(14, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(SoftBlue.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .softCard()
        // The whole card opens the stop, not just the button (owner
        // 2026-07-25: "unable to click into bus stop … when the card shows
        // up"). The pin/close/Directions buttons still take their own taps —
        // this only catches everything else.
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Hand the stop to Apple Maps as a walking destination.
    private func openDirections() {
        guard let stop = store.stopByCode[code] else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = store.stopName(code)
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private var subline: String {
        var parts = [code]
        let road = store.roadName(code)
        if !road.isEmpty { parts.append(road.uppercased()) }
        if let here = location.location?.coordinate, let s = store.stopByCode[code] {
            let d = haversine(here.latitude, here.longitude, s.Latitude, s.Longitude)
            parts.append(fmtDistance(Int(d.rounded())))
        }
        return parts.joined(separator: " · ")
    }

    private var isPinned: Bool { m.pins.contains { $0.code == code } }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }
}

// MARK: - MRT station card

private struct WSMapMrtCard: View {
    let station: MrtGeoStation
    var onOpen: () -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                        // Soft-blue drops the crowd gauge bar app-wide
                        // (SoftMrtTile precedent) — the word alone is enough.
                        if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                            Text(crowd.wsWord)
                                .font(ws.sans(10.5, weight: .bold))
                                .foregroundStyle(SoftBlue.sub)
                        }
                    }
                    Text(station.name)
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                        .lineLimit(1)
                    Text(subline)
                        .font(ws.sans(11.5)).monospacedDigit()
                        .foregroundStyle(SoftBlue.sub)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    WSIcon(glyph: .close, size: 15, color: SoftBlue.sub)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)   // 44pt hit area overhangs the 36pt tile
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .frame(width: 36, height: 36)   // layout stays tile-sized
                .accessibilityLabel("Close")
            }
            .padding(.top, 14).padding(.horizontal, 16)

            Button(action: onOpen) {
                Text("Open station")
                    .font(ws.sans(14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(SoftBlue.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
            .padding(16)
        }
        .onAppear { store.wsWarmCrowd(for: [station]) }
        .softCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var subline: String {
        var parts = [wsLineNames(from: station.codes).uppercased()]
        if let here = location.location?.coordinate {
            let d = haversine(here.latitude, here.longitude, station.lat, station.lon)
            parts.append(fmtDistance(Int(d.rounded())))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Coordinate sugar

private extension LTABusStop {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Latitude, longitude: Longitude)
    }
}
private extension MrtGeoStation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
