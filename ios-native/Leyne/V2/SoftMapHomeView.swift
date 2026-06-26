// SoftMapHomeView — map-first Home (redesign, branch `redesign-main-view`).
//
// Differentiator: LIVE buses on the map (each Service's LTA GPS position),
// colour-coded by ETA. Arrivals are the hero; the map is live context.
//
// Smoothness is engineered in two layers:
//   1. Nearby data (stops/stations/buses/arrivals) is cached in @State and
//      refreshed only on data/location/tick — never per drag frame.
//   2. The map is an Equatable subview (`MapContentView`) so SwiftUI SKIPS
//      re-rendering it while the sheet is dragged (the heavy per-frame cost was
//      the Map re-diffing ~30 annotations). A `cameraVersion` token lets real
//      camera moves (recenter / select) still get through.
// So a drag only slides the sheet's `.offset` — no Map work, no re-layout.

import SwiftUI
import MapKit

private struct LiveBus: Identifiable, Equatable {
    let id: String
    let lat: Double
    let lon: Double
    let no: String
    let etaSec: Int
    var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

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

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Bumped whenever we deliberately move the camera, so the Equatable map view
    /// re-renders for real camera moves but is skipped during a drag.
    @State private var cameraVersion = 0
    @State private var panelHeight: CGFloat = 290
    @State private var dragStartHeight: CGFloat? = nil
    @State private var didInitialCenter = false
    @State private var selectedStop: String? = nil
    @State private var selectedStation: MrtGeoStation? = nil

    // Cached nearby data — recomputed only on data/location/tick, never on a drag.
    @State private var stops: [NearbyStop] = []
    @State private var stations: [MrtGeoStation] = []
    @State private var buses: [LiveBus] = []
    @State private var arrivalsByStop: [String: [RankedArrival]] = [:]

    private var t: Theme { m.t }
    private var mapAccent: Color { t.isDark ? Color(hex: "7E7BFF") : Color(hex: "5856D6") }
    private var meGreen: Color { t.isDark ? Color(hex: "22C55E") : Color(hex: "16A34A") }
    private var meAmber: Color { t.isDark ? Color(hex: "F59E0B") : Color(hex: "D97706") }
    private var hasSelection: Bool { selectedStop != nil || selectedStation != nil }

    // MARK: - Data refresh (off the drag path)

    private func computeStops() -> [NearbyStop] {
        let hidden = m.hiddenNearby
        return ds.nearby.filter { !hidden.contains($0.stopCode) }
            .sorted { $0.distanceM < $1.distanceM }
    }

    private func computeStations() -> [MrtGeoStation] {
        guard let here = loc.location else { return [] }
        return MrtGeo.nearestStations(to: here.coordinate, limit: 6,
                                      withinMeters: max(m.searchRadiusM, 1200)).map { $0.station }
    }

    private func computeBuses() -> [LiveBus] {
        var seen = Set<String>(); var out: [LiveBus] = []
        for stop in stops.prefix(10) {
            for s in m.liveServices(code: stop.stopCode, tracked: []) {
                guard let lat = s.busLat, let lon = s.busLon,
                      abs(lat) > 0.0001, abs(lon) > 0.0001 else { continue }
                let posKey = "\(s.no)@\(Int(lat * 10000)),\(Int(lon * 10000))"
                if seen.contains(posKey) { continue }
                seen.insert(posKey)
                out.append(LiveBus(id: "\(stop.stopCode)-\(s.no)", lat: lat, lon: lon,
                                   no: s.no, etaSec: s.etaSec))
                if out.count >= 14 { return out }
            }
        }
        return out
    }

    private func computeArrivals() -> [String: [RankedArrival]] {
        var map: [String: [RankedArrival]] = [:]
        for stop in stops.prefix(12) { map[stop.stopCode] = rankedArrivals(stop.stopCode) }
        return map
    }

    private func refreshAll() {
        stops = computeStops()
        stations = computeStations()
        buses = computeBuses()
        arrivalsByStop = computeArrivals()
        for stop in stops.prefix(12) { ds.ensureArrivals(stop: stop.stopCode) }
    }

    /// Lighter per-second refresh: buses + arrival ETAs, not the station query.
    private func refreshLive() {
        buses = computeBuses()
        arrivalsByStop = computeArrivals()
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                MapContentView(
                    camera: $camera,
                    cameraVersion: cameraVersion,
                    stops: stops, stations: stations, buses: buses,
                    selectedStop: selectedStop, selectedStationID: selectedStation?.id,
                    pinned: Set(m.pins.map { $0.code }),
                    accent: mapAccent, green: meGreen, amber: meAmber,
                    coordFor: { coord($0) },
                    lineColorFor: { stationColor($0) },
                    onSelectStop: { selectStop($0) },
                    onSelectStation: { selectStation($0) },
                    onTapMap: { collapseSheet() }
                )
                .equatable()
                .ignoresSafeArea()

                recenterButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16).padding(.top, 10)
                departuresPanel(maxHeight: geo.size.height)
            }
        }
        .navigationTitle("SG Transit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { alertsBell } }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l); centerOnUser() }
            ds.prefetchNearbyArrivals()
            refreshAll()
        }
        .onChange(of: loc.location) { _, new in
            if let l = new {
                ds.updateNearby(l); ds.prefetchNearbyArrivals(); refreshAll()
                if !didInitialCenter { centerOnUser() }
            }
        }
        .onChange(of: ds.nearby) { _, _ in refreshAll() }
        .onChange(of: m.tick) { _, _ in refreshLive() }
    }

    private func coord(_ code: String) -> CLLocationCoordinate2D? {
        guard let s = ds.stopByCode[code] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

    private func stationColor(_ st: MrtGeoStation) -> Color {
        for code in st.codes {
            let prefix = String(code.prefix { $0.isLetter })
            if let line = MRTLine(rawValue: prefix) { return line.color }
        }
        return Color(hex: "E22319")
    }

    private func centerOnUser() {
        loc.startIfAuthorized()
        guard let c = loc.location?.coordinate else { return }
        didInitialCenter = true
        cameraVersion += 1
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(
                center: c, span: MKCoordinateSpan(latitudeDelta: 0.007, longitudeDelta: 0.007)))
        }
    }

    private func recenter(_ c: CLLocationCoordinate2D?) {
        guard let c else { return }
        cameraVersion += 1
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: c, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
    }

    private var recenterButton: some View {
        Button { fb.select(); centerOnUser() } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(mapAccent)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter on my location")
    }

    // MARK: Bottom sheet

    private func departuresPanel(maxHeight: CGFloat) -> some View {
        let maxDetent = maxHeight * 0.88
        return VStack(spacing: 0) {
            grabber
                .frame(maxWidth: .infinity).frame(height: 22).padding(.top, 8)
                .contentShape(Rectangle())
                .gesture(panelDrag(maxHeight: maxHeight))
            searchField.padding(.horizontal, 16).padding(.bottom, 10)
            sheetHeader
                .padding(.horizontal, 16).padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(panelDrag(maxHeight: maxHeight))
            ScrollView {
                LazyVStack(spacing: 9) {
                    if let code = selectedStop {
                        stopPreview(code)
                    } else if let st = selectedStation {
                        stationPreview(st)
                    } else if stops.isEmpty {
                        Text(loc.location == nil
                             ? "Turn on location to see stops near you."
                             : "No stops in range right now.")
                            .font(t.sans(13)).foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        ForEach(Array(stops.prefix(12).enumerated()),
                                id: \.element.id) { idx, stop in
                            stopRow(stop)
                            if idx == 2 { NativeAdCard() }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .frame(height: maxDetent).frame(maxWidth: .infinity)
        .background(t.surface,
                    in: UnevenRoundedRectangle(cornerRadii:
                        .init(topLeading: 22, topTrailing: 22), style: .continuous))
        .overlay(UnevenRoundedRectangle(cornerRadii:
            .init(topLeading: 22, topTrailing: 22), style: .continuous).stroke(t.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .offset(y: maxDetent - panelHeight)
    }

    private var grabber: some View { Capsule().fill(t.faint).frame(width: 40, height: 5) }

    private var searchField: some View {
        Button { fb.select(); onOpenSearch() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(t.dim)
                Text("Search stops, buses, stations").font(t.sans(15)).foregroundStyle(t.dim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(t.surfaceHi, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sheetHeader: some View {
        let located = loc.location != nil
        HStack(spacing: 6) {
            if hasSelection {
                Button { clearSelection() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        Text("Nearby").font(t.sans(14, weight: .semibold))
                    }.foregroundStyle(mapAccent)
                }
                Spacer(minLength: 0)
            } else {
                Image(systemName: located ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(located ? mapAccent : t.dim)
                Text("Leaving near you").font(t.sans(14, weight: .bold)).foregroundStyle(t.fg)
                if located {
                    Text("·").foregroundStyle(t.faint)
                    Circle().fill(meGreen).frame(width: 6, height: 6)
                    Text("LIVE").font(t.mono(10, weight: .bold)).tracking(0.8).foregroundStyle(meGreen)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Stop row

    private func stopRow(_ stop: NearbyStop) -> some View {
        let code = stop.stopCode
        let name = stop.stopName.isEmpty ? code : stop.stopName
        let arrivals = arrivalsByStop[code] ?? []
        return Button { fb.select(); m.addRecent(name); onOpenStop(code) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    pinTile(saved: m.isPinned(code))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg).lineLimit(1)
                        Text("\(code) · \(ds.roadName(code))")
                            .font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if stop.walkMin > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.walk").font(.system(size: 11, weight: .semibold))
                            Text("\(stop.walkMin) min").font(t.sans(12, weight: .medium))
                        }.foregroundStyle(t.dim)
                    }
                }
                if arrivals.isEmpty {
                    Text("No live arrivals").font(t.sans(12)).foregroundStyle(t.faint)
                } else {
                    HStack(spacing: 7) {
                        ForEach(arrivals) { a in busChip(a) }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(t.faint)
                    }
                }
            }
            .padding(13)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(t.line, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func busChip(_ a: RankedArrival) -> some View {
        let eta = fmtETA(a.service.etaSec)
        let col: Color = a.service.etaSec <= 120 ? meGreen
            : (a.service.etaSec <= 420 ? meAmber : t.fg)
        return HStack(spacing: 5) {
            Text(a.service.no).font(t.mono(13, weight: .bold)).foregroundStyle(t.fg)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(eta.big).font(t.mono(13, weight: .bold)).foregroundStyle(col)
                Text(eta.small).font(t.sans(9)).foregroundStyle(t.dim)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(t.surfaceHi, in: Capsule())
    }

    private func pinTile(saved: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mapAccent)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
        .overlay(alignment: .topTrailing) {
            if saved {
                Image(systemName: "star.fill").font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                    .frame(width: 14, height: 14).background(meAmber, in: Circle())
                    .overlay(Circle().stroke(t.surface, lineWidth: 1.5)).offset(x: 4, y: -4)
            }
        }
    }

    // MARK: Selection

    private func selectStop(_ stop: NearbyStop) {
        fb.select(); selectedStation = nil; selectedStop = stop.stopCode
        recenter(coord(stop.stopCode)); setSheet(max(panelHeight, 460))
    }
    private func selectStation(_ st: MrtGeoStation) {
        fb.select(); selectedStop = nil; selectedStation = st
        recenter(CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon))
        setSheet(max(panelHeight, 380))
    }
    private func clearSelection() {
        fb.select(); selectedStop = nil; selectedStation = nil; setSheet(290)
    }
    private func collapseSheet() {
        if !hasSelection && panelHeight <= 320 { return }
        fb.select(); selectedStop = nil; selectedStation = nil; setSheet(290)
    }
    private func setSheet(_ height: CGFloat) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { panelHeight = height }
    }

    // MARK: Preview cards

    @ViewBuilder
    private func stopPreview(_ code: String) -> some View {
        let stop = stops.first { $0.stopCode == code }
        let name = (stop?.stopName).flatMap { $0.isEmpty ? nil : $0 } ?? code
        let arrivals = Array(m.liveServices(code: code, tracked: []).prefix(6))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                pinTile(saved: m.isPinned(code))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(t.sans(17, weight: .bold)).foregroundStyle(t.fg).lineLimit(1)
                    Text("\(code) · \(ds.roadName(code))")
                        .font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if arrivals.isEmpty {
                Text("No live arrivals right now").font(t.sans(13)).foregroundStyle(t.dim)
            } else {
                VStack(spacing: 9) {
                    ForEach(arrivals, id: \.no) { s in
                        let eta = fmtETA(s.etaSec)
                        let col: Color = s.etaSec <= 120 ? meGreen : (s.etaSec <= 420 ? meAmber : t.fg)
                        HStack {
                            Text(s.no).font(t.mono(14, weight: .bold))
                                .foregroundStyle(t.fg).frame(minWidth: 46, alignment: .leading)
                            Spacer(minLength: 8)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(eta.big).font(t.mono(14, weight: .bold)).foregroundStyle(col)
                                Text(eta.small).font(t.sans(10)).foregroundStyle(t.dim)
                            }
                        }
                    }
                }
            }
            openButton("Open stop") { onOpenStop(code) }
        }
        .padding(14)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func stationPreview(_ st: MrtGeoStation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(st.codes, id: \.self) { code in
                    Text(code).font(t.mono(11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(codeColor(code), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Text(st.name).font(t.sans(20, weight: .bold)).foregroundStyle(t.fg)
            Text("MRT station").font(t.sans(13)).foregroundStyle(t.dim)
            openButton("Open station") { onOpenMrtStation(st) }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func codeColor(_ code: String) -> Color {
        let prefix = String(code.prefix { $0.isLetter })
        return MRTLine(rawValue: prefix)?.color ?? Color(hex: "E22319")
    }

    private func openButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { fb.select(); action() } label: {
            Text(title).font(t.sans(15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(mapAccent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Drag

    private func detents(_ maxHeight: CGFloat) -> [CGFloat] { [290, maxHeight * 0.55, maxHeight * 0.88] }

    private func panelDrag(maxHeight: CGFloat) -> some Gesture {
        let maxH = maxHeight * 0.88
        let minH: CGFloat = 230
        return DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStartHeight == nil { dragStartHeight = panelHeight }
                let proposed = (dragStartHeight ?? panelHeight) - v.translation.height
                if proposed > maxH { panelHeight = maxH + (proposed - maxH) * 0.22 }
                else if proposed < minH { panelHeight = minH - (minH - proposed) * 0.22 }
                else { panelHeight = proposed }
            }
            .onEnded { v in
                dragStartHeight = nil
                let velocity = v.predictedEndTranslation.height - v.translation.height
                let projected = panelHeight - velocity * 0.5
                let target = detents(maxHeight).min(by: { abs($0 - projected) < abs($1 - projected) }) ?? minH
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { panelHeight = target }
            }
    }

    private var alertsBell: some View {
        Button { fb.select(); onOpenAlerts() } label: {
            Image(systemName: m.unseenAlertCount > 0 ? "bell.badge.fill" : "bell.fill")
        }
        .accessibilityLabel(m.unseenAlertCount > 0 ? "Alerts, \(m.unseenAlertCount) new" : "Alerts")
    }

    private func rankedArrivals(_ code: String) -> [RankedArrival] {
        let services = m.liveServices(code: code, tracked: [])
        func isFav(_ s: Service) -> Bool {
            m.isFavService(no: s.no, stop: code) || m.isFavService(no: s.no, stop: nil)
        }
        let favs = services.filter(isFav)
        let rest = services.filter { !isFav($0) }
        return (favs + rest).prefix(3).map { RankedArrival(service: $0, fav: isFav($0)) }
    }
}

// MARK: - Map content (Equatable → skipped while the sheet is dragged)

private struct MapContentView: View, Equatable {
    @Binding var camera: MapCameraPosition
    let cameraVersion: Int
    let stops: [NearbyStop]
    let stations: [MrtGeoStation]
    let buses: [LiveBus]
    let selectedStop: String?
    let selectedStationID: String?
    let pinned: Set<String>
    let accent: Color
    let green: Color
    let amber: Color
    let coordFor: (String) -> CLLocationCoordinate2D?
    let lineColorFor: (MrtGeoStation) -> Color
    let onSelectStop: (NearbyStop) -> Void
    let onSelectStation: (MrtGeoStation) -> Void
    let onTapMap: () -> Void

    // Only the data + selection + camera token drive a re-render. Closures are
    // intentionally excluded — they dispatch to live parent state.
    static func == (a: MapContentView, b: MapContentView) -> Bool {
        a.cameraVersion == b.cameraVersion
            && a.selectedStop == b.selectedStop
            && a.selectedStationID == b.selectedStationID
            && a.pinned == b.pinned
            && a.stops == b.stops
            && a.stations == b.stations
            && a.buses == b.buses
    }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(stops) { stop in
                if let c = coordFor(stop.stopCode) {
                    Annotation(stop.stopName.isEmpty ? stop.stopCode : stop.stopName,
                               coordinate: c, anchor: .center) { stopMarker(stop) }
                }
            }
            ForEach(stations) { st in
                Annotation(st.name,
                           coordinate: CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon),
                           anchor: .center) { mrtMarker(st) }
            }
            ForEach(buses) { bus in
                Annotation("Bus \(bus.no)", coordinate: bus.coord, anchor: .center) { busMarker(bus) }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onTapGesture { onTapMap() }
    }

    private func stopMarker(_ stop: NearbyStop) -> some View {
        let isSel = selectedStop == stop.stopCode
        return Button { onSelectStop(stop) } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(accent, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: isSel ? 3 : 2))
                .overlay(alignment: .topTrailing) {
                    if pinned.contains(stop.stopCode) {
                        Image(systemName: "star.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                            .frame(width: 14, height: 14).background(amber, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5)).offset(x: 5, y: -5)
                    }
                }
                .scaleEffect(isSel ? 1.3 : 1)
                .shadow(color: .black.opacity(0.3), radius: isSel ? 5 : 2, y: 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSel)
        }.buttonStyle(.plain)
    }

    private func mrtMarker(_ st: MrtGeoStation) -> some View {
        let isSel = selectedStationID == st.id
        return Button { onSelectStation(st) } label: {
            Image(systemName: "tram.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(lineColorFor(st), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: isSel ? 3 : 2))
                .scaleEffect(isSel ? 1.3 : 1)
                .shadow(color: .black.opacity(0.3), radius: isSel ? 5 : 2, y: 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSel)
        }.buttonStyle(.plain)
    }

    private func busMarker(_ bus: LiveBus) -> some View {
        let col = bus.etaSec <= 120 ? green : (bus.etaSec <= 420 ? amber : accent)
        return Image(systemName: "bus.fill")
            .font(.system(size: 9, weight: .black)).foregroundStyle(.white)
            .frame(width: 21, height: 21).background(col, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }
}
