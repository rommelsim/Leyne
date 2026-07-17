// WhereSia — Nearby Map (iOS-only feature).
//
// A full-bleed MapKit browse surface pushed from Home: every bus stop and
// MRT/LRT station around the visible region, tappable into a floating glass
// card with live arrivals (or station crowd) and a push into the existing
// Stop / Station screens. iOS-exclusive by owner call (2026-07-04) — Android
// deliberately ships without a map, so this has no parity obligation.
//
// Design contract: the board's ONE HARD RULE holds on the map too. Bus stop
// markers are greyscale panel dots; the only colour is MRT line identity on
// the station bullets, plus the sanctioned blue accent for the selected
// marker, the live-bus capsules and the user dot (system). Chrome (card,
// recenter, hint chip) is wsGlassChrome — content inside stays flat panels.

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
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

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
    /// Above this span, station bullets collapse to small colour dots.
    private static let bulletSpan: Double = 0.12

    private var stopsVisible: Bool { region.span.latitudeDelta < Self.stopVisibleSpan }

    var body: some View {
        map
            .ignoresSafeArea(edges: .top)   // full bleed under the translucent bar
            .overlay(alignment: .top) { zoomHint }
            .overlay(alignment: .bottom) { bottomStack }
            .sensoryFeedback(.selection, trigger: selection)
            .wsHeaderBar(eyebrow: "Around you", title: "Map", onBack: onBack)
            .onAppear(perform: bootstrap)
            // The freshness window inside ensureArrivals turns the per-second
            // tick into an actual refetch ~every 25s for the open card.
            .onChange(of: m.tick) { _, _ in
                if case .stop(let code) = selection {
                    store.ensureArrivals(stop: code, silent: true)
                }
            }
    }

    // MARK: map + annotations

    private var map: some View {
        let stops = visibleStops
        let compact = region.span.latitudeDelta >= Self.bulletSpan
        return Map(position: $camera) {
            UserAnnotation()

            ForEach(MrtGeo.all) { st in
                Annotation(st.name, coordinate: st.coordinate, anchor: .center) {
                    Button { select(.mrt(st)) } label: {
                        MrtMarker(station: st, compact: compact,
                                  selected: selection == .mrt(st))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(st.name) MRT station")
                }
                .annotationTitles(.hidden)
            }

            ForEach(stops, id: \.BusStopCode) { stop in
                Annotation(stop.Description, coordinate: stop.coordinate, anchor: .center) {
                    Button { select(.stop(stop.BusStopCode)) } label: {
                        StopMarker(selected: selectedStopCode == stop.BusStopCode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bus stop \(stop.Description)")
                }
                .annotationTitles(.hidden)
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
        .onMapCameraChange(frequency: .onEnd) { ctx in region = ctx.region }
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

    private var liveBuses: [(no: String, coord: CLLocationCoordinate2D)] {
        guard let code = selectedStopCode else { return [] }
        return store.servicesFor(code).compactMap { s in
            guard let lat = s.busLat, let lon = s.busLon,
                  abs(lat) > 0.01, abs(lon) > 0.01 else { return nil }  // LTA sends 0,0 for no telemetry
            return (s.no, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

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
        withAnimation(.snappy(duration: 0.25)) { selection = sel }
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

    private func recenter() {
        guard let here = location.location?.coordinate else {
            if location.status == .notDetermined { location.requestPermission() }
            withAnimation(.easeInOut(duration: 0.5)) { camera = .region(Self.islandRegion) }
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(MKCoordinateRegion(center: here,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }

    // MARK: overlays

    @ViewBuilder private var zoomHint: some View {
        if !stopsVisible {
            Text("ZOOM IN FOR BUS STOPS")
                .font(ws.mono(10, weight: .bold)).tracking(1.2)
                .foregroundStyle(ws.dim)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .wsGlassChrome(cornerRadius: 10, tint: ws.tabbar)
                .padding(.top, 6)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Button(action: recenter) {
                WSIcon(glyph: .location, size: 18)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .wsGlassChrome(cornerRadius: 23, tint: ws.tabbar, interactive: true)
            .shadow(color: .black.opacity(ws.isDark ? 0.35 : 0.12), radius: 14, x: 0, y: 6)
            .accessibilityLabel("Recenter on my location")

            switch selection {
            case .stop(let code):
                WSMapStopCard(code: code,
                              onOpen: { push(.busStop(code: code)) },
                              onClose: { withAnimation(.snappy(duration: 0.25)) { selection = nil } })
            case .mrt(let st):
                WSMapMrtCard(station: st,
                             onOpen: { push(.mrtStation(st)) },
                             onClose: { withAnimation(.snappy(duration: 0.25)) { selection = nil } })
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

// MARK: - Markers

/// Greyscale panel dot with the bus glyph — neutral by contract; the blue
/// accent ring + ping is reserved for the selected stop.
private struct StopMarker: View {
    var selected: Bool
    @Environment(\.ws) private var ws
    var body: some View {
        WSIcon(glyph: .busSingle, size: selected ? 12 : 9,
               weight: .regular, color: selected ? ws.text : ws.dim)
            .frame(width: selected ? 28 : 20, height: selected ? 28 : 20)
            .background(Circle().fill(ws.panel))
            .overlay(Circle().stroke(selected ? ws.accent : ws.rule,
                                     lineWidth: selected ? 2 : 1))
            .background { if selected { WSPing() } }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .contentShape(Circle())
    }
}

/// Line-coloured station mark: a small colour dot when zoomed out, the code
/// bullet(s) when close — the map's only colour, and it is data.
private struct MrtMarker: View {
    let station: MrtGeoStation
    var compact: Bool
    var selected: Bool
    @Environment(\.ws) private var ws

    var body: some View {
        Group {
            if compact && !selected {
                Circle()
                    .fill(WSLine.color(forStationCode: station.codes.first ?? ""))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            } else {
                HStack(spacing: 2) {
                    ForEach(station.codes.prefix(2), id: \.self) { LineBullet(code: $0) }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(ws.panel))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? ws.accent : ws.rule, lineWidth: selected ? 2 : 1))
                .background { if selected { WSPing(cornerRadius: 8) } }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .contentShape(Rectangle())
    }
}

/// A bus that is actually on the road right now — accentSoft is the
/// sanctioned "live" colour, same as the LIVE badge.
private struct LiveBusMarker: View {
    let no: String
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 4) {
            WSIcon(glyph: .busSingle, size: 10, weight: .regular, color: ws.accentSoft)
            Text(no).font(ws.mono(11, weight: .bold)).foregroundStyle(ws.text)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(ws.panel))
        .overlay(Capsule().stroke(ws.accentSoft, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
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
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    Text(subline)
                        .font(ws.sans(12.5, weight: .medium))
                        .foregroundStyle(ws.dim)
                }
                Spacer(minLength: 8)
                Button(action: togglePin) {
                    WSIcon(glyph: isPinned ? .bookmarkFilled : .bookmark, size: 17)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "Remove from Saved" : "Save stop")
                Button(action: onClose) {
                    WSIcon(glyph: .close, size: 15, color: ws.dim)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.top, 14).padding(.horizontal, 16)

            Group {
                if soonest.isEmpty {
                    Text(store.newestRefresh(amongst: [code]) == nil
                         ? "Fetching live arrivals…"
                         : "No buses due right now.")
                        .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                        .padding(.vertical, 14)
                } else {
                    // Mini departure rows in the board grammar (green plate +
                    // white number while arriving, seat dot, "Now"/"N min") —
                    // the old RouteTile + ArrivalPill row was the pre-2026-07-08
                    // design and read as a different app (owner 2026-07-09).
                    VStack(spacing: 0) {
                        ForEach(Array(soonest)) { s in
                            let sec = wsLiveETASec(s)
                            let now = sec < 60
                            HStack(spacing: 10) {
                                Text(s.no)
                                    .font(ws.mono(s.no.count > 3 ? 12 : 14, weight: .bold))
                                    .foregroundStyle(now ? .white : ws.text)
                                    .frame(width: 46, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(now ? ws.now : ws.panel2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.dest)
                                        .font(ws.sans(13.5, weight: .semibold))
                                        .foregroundStyle(ws.text).lineLimit(1)
                                    HStack(spacing: 5) {
                                        Circle().fill(s.load.wsDotColor)
                                            .frame(width: 6, height: 6)
                                        Text(s.load.wsSeatPhrase)
                                            .font(ws.sans(11.5, weight: .medium))
                                            .foregroundStyle(ws.dim)
                                            .lineLimit(1).allowsTightening(true)
                                    }
                                }
                                Spacer(minLength: 8)
                                Group {
                                    if now {
                                        Text("Now")
                                            .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
                                    } else {
                                        (Text(s.monitored ? "" : "~")
                                            .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim)
                                         + Text("\(max(1, sec / 60))")
                                            .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
                                         + Text(" min")
                                            .font(ws.sans(11, weight: .semibold)).foregroundStyle(ws.dim))
                                    }
                                }
                                .contentTransition(.numericText(countsDown: true))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16)

            Button(action: onOpen) {
                Text("Open stop")
                    .font(ws.sans(14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(ws.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .wsGlassChrome(cornerRadius: 20, tint: ws.tabbar)
        .shadow(color: .black.opacity(ws.isDark ? 0.35 : 0.12), radius: 18, x: 0, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var subline: String {
        var parts = [code]
        let road = store.roadName(code)
        if !road.isEmpty { parts.append(road) }
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
                        if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                            CrowdGauge(fraction: crowd.wsFraction, width: 22)
                            Text(crowd.wsWord)
                                .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                        }
                    }
                    Text(station.name)
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    Text(subline)
                        .font(ws.sans(12.5, weight: .medium))
                        .foregroundStyle(ws.dim)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    WSIcon(glyph: .close, size: 15, color: ws.dim)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.top, 14).padding(.horizontal, 16)

            Button(action: onOpen) {
                Text("Open station")
                    .font(ws.sans(14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(ws.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .onAppear { store.wsWarmCrowd(for: [station]) }
        .wsGlassChrome(cornerRadius: 20, tint: ws.tabbar)
        .shadow(color: .black.opacity(ws.isDark ? 0.35 : 0.12), radius: 18, x: 0, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var subline: String {
        var parts = [wsLineNames(from: station.codes)]
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
