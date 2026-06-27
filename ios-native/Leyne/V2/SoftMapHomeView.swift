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
    let onOpenSettings: () -> Void

    /// The sheet shows either nearby departures or the user's Saved list
    /// (Model B — Saved folded into the map sheet instead of a tab).
    enum SheetMode: Hashable { case nearby, saved }
    @State private var sheetMode: SheetMode = .nearby

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Bumped whenever we deliberately move the camera, so the Equatable map view
    /// re-renders for real camera moves but is skipped during a drag.
    @State private var cameraVersion = 0
    @State private var panelHeight: CGFloat = SoftMapHomeView.peekHeight
    @State private var dragStartHeight: CGFloat? = nil
    /// True only while a drag that STARTED on the list area (at the peek) is
    /// driving the sheet up. Captured once at the gesture's start so crossing a
    /// detent mid-pull never hands the gesture back and forth between the sheet
    /// and the inner ScrollView (the old jitter when "pulling up the list").
    @State private var listDragActive = false
    @State private var didInitialCenter = false
    @State private var selectedStop: String? = nil
    @State private var selectedStation: MrtGeoStation? = nil

    // Cached nearby data — recomputed only on data/location/tick, never on a drag.
    @State private var stops: [NearbyStop] = []
    @State private var stations: [MrtGeoStation] = []
    @State private var buses: [LiveBus] = []
    @State private var arrivalsByStop: [String: [RankedArrival]] = [:]

    /// Collapsed "peek" height — small, so the map is the hero. Shows the
    /// search field, the live header and a glimpse of the nearest stop; pull up
    /// for the full list.
    static let peekHeight: CGFloat = 244

    private var t: Theme { m.t }
    private var mapAccent: Color { t.meBlue }   // one shared accent (indigo)
    private var meGreen: Color { t.isDark ? Color(hex: "22C55E") : Color(hex: "16A34A") }
    private var meAmber: Color { t.isDark ? Color(hex: "F59E0B") : Color(hex: "D97706") }
    private var hasSelection: Bool { selectedStop != nil || selectedStation != nil }

    /// MRT lines currently disrupted (from LTA train alerts) — drives the
    /// map-home disruption banner. Surfacing this on the home screen (not just
    /// the Lines tab) is the redesign's "own MRT disruptions where the user
    /// already is" hook.
    private var disruptedLines: [MRTLine] {
        var seen = Set<MRTLine>()
        for alert in ds.trainAlerts { if let l = alert.line { seen.insert(l) } }
        return seen.sorted { $0.rawValue < $1.rawValue }
    }

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
        // Saved stops may be far from here (not in `stops`); rank their arrivals
        // too so the Saved list shows live chips.
        for pin in m.pins where map[pin.code] == nil { map[pin.code] = rankedArrivals(pin.code) }
        return map
    }

    private func refreshAll() {
        stops = computeStops()
        stations = computeStations()
        buses = computeBuses()
        arrivalsByStop = computeArrivals()
        for stop in stops.prefix(12) { ds.ensureArrivals(stop: stop.stopCode) }
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
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
                    userCoord: loc.location?.coordinate,
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { settingsGear }
            ToolbarItem(placement: .topBarTrailing) { alertsBell }
        }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l); centerOnUser() }
            ds.prefetchNearbyArrivals()
            ds.refreshTrainAlertsIfStale(force: false)   // drives the disruption banner
            refreshAll()
        }
        .onChange(of: loc.location) { _, new in
            if let l = new {
                ds.updateNearby(l); ds.prefetchNearbyArrivals(); refreshAll()
                if !didInitialCenter { centerOnUser() }
            }
        }
        .onChange(of: ds.nearby) { _, _ in if !isDragging { refreshAll() } }
        // Pause the per-second live refresh WHILE the sheet is being dragged —
        // recomputing buses/arrivals mid-drag re-diffs the list and hitches the
        // pull. A pending tick is picked up the instant the drag ends.
        .onChange(of: m.tick) { _, _ in if !isDragging { refreshLive() } }
        .onChange(of: isDragging) { _, dragging in if !dragging { refreshLive() } }
    }

    /// True while a sheet drag is in flight (either the handle or a list pull).
    private var isDragging: Bool { dragStartHeight != nil }

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
        // Bias the centre south of the user so the blue dot sits in the upper,
        // un-covered part of the map (the peek sheet eats the bottom). Slightly
        // wider span than before so a handful of nearby stops + stations frame
        // around you at launch.
        let span = 0.0085
        let shifted = CLLocationCoordinate2D(latitude: c.latitude - span * 0.26,
                                             longitude: c.longitude)
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: shifted, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
        }
    }

    private func recenter(_ c: CLLocationCoordinate2D?) {
        guard let c else { return }
        cameraVersion += 1
        // A taller sheet covers more here, so bias the focus a little higher too.
        let span = 0.006
        let shifted = CLLocationCoordinate2D(latitude: c.latitude - span * 0.34,
                                             longitude: c.longitude)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: shifted, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
        }
    }

    private var recenterButton: some View {
        let located = loc.location != nil
        return Button {
            fb.select()
            // Drop the sheet to its peek so YOU aren't hidden behind it, then
            // frame on your location.
            if panelHeight > Self.peekHeight + 30 { setSheet(Self.peekHeight) }
            centerOnUser()
        } label: {
            Image(systemName: located ? "location.fill" : "location.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(located ? mapAccent : t.dim)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter on my location")
    }

    // MARK: Bottom sheet

    private func departuresPanel(maxHeight: CGFloat) -> some View {
        let maxDetent = maxHeight * 0.9
        // The inner list only scrolls once the sheet is (near) fully open. While
        // it's collapsed/at-peek, scrolling is OFF so a pull-up cleanly EXPANDS
        // the sheet instead of nudging a short list — the smoothness fix. The
        // `listDragActive` flag keeps it disabled for the whole expanding pull so
        // scrolling never grabs the gesture half-way up.
        let scrollEnabled = panelHeight >= maxDetent - 24 && !listDragActive
        return VStack(spacing: 0) {
            grabber
                .frame(maxWidth: .infinity).frame(height: 22).padding(.top, 8)
                .contentShape(Rectangle())
                .gesture(panelDrag(maxHeight: maxHeight, fromHandle: true))
            searchField.padding(.horizontal, 16).padding(.bottom, 10)
            disruptionBanner
            sheetTopControls
                .padding(.horizontal, 16).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let code = selectedStop {
                        stopPreview(code)
                    } else if let st = selectedStation {
                        stationPreview(st)
                    } else if sheetMode == .saved {
                        savedContent
                    } else {
                        nearbyContent
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .scrollDisabled(!scrollEnabled)
            // List-area drag: only seizes control when the pull STARTS at the
            // peek (see panelDrag); otherwise it no-ops and the ScrollView owns
            // the vertical drag.
            .simultaneousGesture(panelDrag(maxHeight: maxHeight, fromHandle: false))
        }
        .frame(height: maxDetent).frame(maxWidth: .infinity)
        .background(t.surface,
                    in: UnevenRoundedRectangle(cornerRadii:
                        .init(topLeading: 22, topTrailing: 22), style: .continuous))
        .overlay(UnevenRoundedRectangle(cornerRadii:
            .init(topLeading: 22, topTrailing: 22), style: .continuous).stroke(t.line, lineWidth: 1))
        // Lighter shadow — a wide blur re-rasterises every frame as the panel
        // slides, which hitched the pull. A tight, low shadow lifts it off the
        // map without the per-frame cost.
        .shadow(color: .black.opacity(0.16), radius: 7, y: -1)
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

    /// Header row: a Nearby|Saved segmented toggle (the Saved tab now lives here),
    /// or a "back to list" control while a map pin is selected. No drag gesture
    /// attached — the segmented control needs its taps.
    @ViewBuilder
    private var sheetTopControls: some View {
        if hasSelection {
            HStack(spacing: 6) {
                Button { clearSelection() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        Text("Back").font(t.sans(14, weight: .semibold))
                    }.foregroundStyle(mapAccent)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                Picker("View", selection: $sheetMode) {
                    Text("Nearby").tag(SheetMode.nearby)
                    Text("Saved").tag(SheetMode.saved)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: sheetMode) { _, mode in
                    fb.select()
                    if mode == .saved { for pin in m.pins { ds.ensureArrivals(stop: pin.code) } }
                }
                Spacer(minLength: 0)
                if sheetMode == .nearby, loc.location != nil {
                    HStack(spacing: 4) {
                        Circle().fill(meGreen).frame(width: 6, height: 6)
                        Text("LIVE").font(t.mono(10, weight: .bold)).tracking(0.8).foregroundStyle(meGreen)
                    }
                }
            }
        }
    }

    private var settingsGear: some View {
        Button { fb.select(); onOpenSettings() } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }

    /// Always-visible-at-peek MRT disruption banner. Renders nothing when all
    /// lines run normally (so no gap). Taps through to the Alerts detail.
    @ViewBuilder
    private var disruptionBanner: some View {
        let lines = disruptedLines
        if !lines.isEmpty {
            Button { fb.select(); onOpenAlerts() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(t.warn)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(lines.count) MRT line\(lines.count == 1 ? "" : "s") disrupted")
                            .font(t.sans(13.5, weight: .semibold)).foregroundStyle(t.fg)
                        Text("Tap for details").font(t.mono(10)).foregroundStyle(t.dim)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        ForEach(lines, id: \.self) { line in
                            Text(line.rawValue).font(t.mono(10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(line.color, in: Capsule())
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(t.faint)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(t.warnBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(t.warn.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.horizontal, 16).padding(.bottom, 9)
        }
    }

    // MARK: Sheet content — Nearby

    @ViewBuilder
    private var nearbyContent: some View {
        if stops.isEmpty {
            Text(loc.location == nil
                 ? "Turn on location to see stops near you."
                 : "No stops in range right now.")
                .font(t.sans(13)).foregroundStyle(t.dim)
                .frame(maxWidth: .infinity).padding(.vertical, 28)
        } else {
            ForEach(Array(stops.prefix(12).enumerated()), id: \.element.id) { idx, stop in
                stopRow(stop)
                if idx == 2 { NativeAdCard() }
            }
        }
    }

    // MARK: Sheet content — Saved

    @ViewBuilder
    private var savedContent: some View {
        let noneSaved = m.pins.isEmpty && m.favServices.isEmpty && m.savedMrtStations.isEmpty
        if noneSaved {
            savedEmptyState
        } else {
            if !m.pins.isEmpty {
                savedSectionHeader("Saved stops", icon: "mappin.and.ellipse")
                ForEach(m.pins, id: \.code) { pin in savedStopRow(pin.code) }
            }
            if !m.favServices.isEmpty {
                savedSectionHeader("Saved buses", icon: "bus.fill")
                ForEach(m.favServices) { fav in savedServiceRow(fav) }
            }
            if !m.savedMrtStations.isEmpty {
                savedSectionHeader("Saved stations", icon: "tram.fill")
                ForEach(m.savedMrtStations, id: \.id) { st in savedStationRow(st) }
            }
            NativeAdCard()
        }
    }

    private func savedSectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.meBlue)
            Text(title).font(t.sans(13, weight: .semibold)).foregroundStyle(t.dim)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2).padding(.top, 6)
    }

    private var savedEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 24)).foregroundStyle(t.meBlue)
                .frame(width: 56, height: 56)
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("No saved places yet").font(t.sans(17, weight: .semibold)).foregroundStyle(t.fg)
            Text("Tap the star on any stop, bus or station and it shows up here.")
                .font(t.sans(13)).foregroundStyle(t.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t.line, lineWidth: 1))
    }

    /// A saved stop reuses the nearby row visuals (arrivals are pre-ranked into
    /// `arrivalsByStop` for pins in computeArrivals).
    private func savedStopRow(_ code: String) -> some View {
        let stop = NearbyStop(id: code, stopName: ds.stopName(code), stopCode: code,
                              distanceM: savedDistanceM(code), walkMin: savedWalkMin(code),
                              services: ds.servicesFor(code))
        return stopRow(stop)
    }

    private func savedWalkMin(_ code: String) -> Int {
        guard let here = loc.location, let s = ds.stopByCode[code] else { return 0 }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude, s.Latitude, s.Longitude)
        return max(1, Int((d / 80).rounded()))
    }
    private func savedDistanceM(_ code: String) -> Int {
        guard let here = loc.location, let s = ds.stopByCode[code] else { return 0 }
        return Int(haversine(here.coordinate.latitude, here.coordinate.longitude,
                             s.Latitude, s.Longitude).rounded())
    }

    private func savedServiceRow(_ fav: FavService) -> some View {
        let code = fav.stop
        let svc = code.flatMap { c in ds.servicesFor(c).first { $0.no == fav.no } }
        return Button {
            fb.select()
            if let code { onOpenBus(code, fav.no) }
        } label: {
            HStack(spacing: 12) {
                ServiceBadge(svc: fav.no, t: t, size: .md)
                VStack(alignment: .leading, spacing: 2) {
                    Text(svc.map { "To \($0.dest)" } ?? "Bus \(fav.no)")
                        .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg).lineLimit(1)
                    Text(fav.isAnywhere ? "Near you" : (code.map { ds.stopName($0) } ?? ""))
                        .font(t.mono(11.5)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let svc {
                    let eta = fmtETA(svc.etaSec)
                    let col: Color = svc.etaSec <= 120 ? meGreen : (svc.etaSec <= 420 ? meAmber : t.fg)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(eta.big).font(t.mono(16, weight: .bold)).foregroundStyle(col)
                        Text(eta.small).font(t.sans(10)).foregroundStyle(t.dim)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(t.faint)
            }
            .padding(14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func savedStationRow(_ st: MrtGeoStation) -> some View {
        Button {
            fb.select(); onOpenMrtStation(st)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(st.codes, id: \.self) { code in
                        Text(code).font(t.mono(10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(codeColor(code), in: Capsule())
                    }
                }
                Text(st.name).font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(t.faint)
            }
            .padding(14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Stop row

    private func stopRow(_ stop: NearbyStop) -> some View {
        let code = stop.stopCode
        let name = stop.stopName.isEmpty ? code : stop.stopName
        let arrivals = arrivalsByStop[code] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            // Identity — opens the full stop.
            Button { fb.select(); m.addRecent(name); onOpenStop(code) } label: {
                HStack(spacing: 12) {
                    pinTile(saved: m.isPinned(code))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(t.sans(16.5, weight: .semibold))
                            .foregroundStyle(t.fg).lineLimit(1)
                        HStack(spacing: 5) {
                            if stop.walkMin > 0 {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(mapAccent)
                                Text("\(stop.walkMin) min")
                                    .font(t.mono(11.5, weight: .medium)).foregroundStyle(t.dim)
                                Text("·").foregroundStyle(t.faint)
                            }
                            Text(ds.roadName(code).isEmpty ? code : ds.roadName(code))
                                .font(t.mono(11.5)).foregroundStyle(t.dim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(t.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())

            // Arrivals — a horizontally-scrollable strip; each chip taps STRAIGHT
            // to that bus's route timeline (one tap from the list, any bus at the
            // stop, no stop-view detour). Vertical drags pass through to the sheet;
            // horizontal pans scroll the strip.
            if arrivals.isEmpty {
                Text("No live arrivals").font(t.sans(12)).foregroundStyle(t.faint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(arrivals) { a in
                            Button { fb.select(); onOpenBus(code, a.service.no) } label: { busChip(a) }
                                .buttonStyle(PressScaleButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t.line, lineWidth: 1))
    }

    /// A compact per-service chip. The soonest buses pop with a soft green/amber
    /// tint + ring so "arriving now" reads at a glance; later buses stay neutral.
    /// Tappable (wrapped in a Button by callers) to jump straight to the route.
    private func busChip(_ a: RankedArrival) -> some View {
        let sec = a.service.etaSec
        let eta = fmtETA(sec)
        let near = sec <= 120
        let soon = sec <= 420
        let col: Color = near ? meGreen : (soon ? meAmber : t.dim)
        let tint: Color = near ? meGreen : (soon ? meAmber : .clear)
        return HStack(spacing: 5) {
            Text(a.service.no).font(t.mono(13, weight: .bold)).foregroundStyle(t.fg)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(eta.big).font(t.mono(13, weight: .bold)).foregroundStyle(col)
                Text(eta.small).font(t.sans(9)).foregroundStyle(t.dim)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6.5)
        .background(near || soon ? tint.opacity(0.14) : t.surfaceHi, in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(near ? 0.45 : (soon ? 0.28 : 0)), lineWidth: 1))
    }

    private func pinTile(saved: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(mapAccent.gradient)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .shadow(color: mapAccent.opacity(0.35), radius: 3, y: 1)
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
        recenter(coord(stop.stopCode)); setSheet(max(panelHeight, 440))
    }
    private func selectStation(_ st: MrtGeoStation) {
        fb.select(); selectedStop = nil; selectedStation = st
        recenter(CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon))
        setSheet(max(panelHeight, 380))
    }
    private func clearSelection() {
        fb.select(); selectedStop = nil; selectedStation = nil; setSheet(Self.peekHeight)
    }
    private func collapseSheet() {
        if !hasSelection && panelHeight <= Self.peekHeight + 30 { return }
        fb.select(); selectedStop = nil; selectedStation = nil; setSheet(Self.peekHeight)
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
                VStack(spacing: 2) {
                    ForEach(arrivals, id: \.no) { s in
                        let eta = fmtETA(s.etaSec)
                        let col: Color = s.etaSec <= 120 ? meGreen : (s.etaSec <= 420 ? meAmber : t.fg)
                        // Each arrival taps straight to its route timeline.
                        Button { fb.select(); onOpenBus(code, s.no) } label: {
                            HStack(spacing: 8) {
                                Text(s.no).font(t.mono(14, weight: .bold))
                                    .foregroundStyle(t.fg).frame(minWidth: 46, alignment: .leading)
                                Spacer(minLength: 8)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(eta.big).font(t.mono(14, weight: .bold)).foregroundStyle(col)
                                    Text(eta.small).font(t.sans(10)).foregroundStyle(t.dim)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(t.faint)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                }
            }
            openButton("Open stop") { onOpenStop(code) }
        }
        .padding(14)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func detents(_ maxHeight: CGFloat) -> [CGFloat] {
        [Self.peekHeight, maxHeight * 0.52, maxHeight * 0.9]
    }

    /// One drag handler for both the handle (grabber/header) and the list area.
    ///   • `fromHandle == true`  → always drives the sheet, both directions.
    ///   • `fromHandle == false` → only seizes the gesture if the pull STARTS at
    ///     the peek; the decision is captured once so the sheet keeps moving for
    ///     the whole pull (no mid-pull handoff = no jitter). Otherwise it no-ops
    ///     and the inner ScrollView scrolls normally.
    private func panelDrag(maxHeight: CGFloat, fromHandle: Bool) -> some Gesture {
        let maxH = maxHeight * 0.9
        let minH = Self.peekHeight - 30
        let peekGrab = Self.peekHeight + 24
        return DragGesture(minimumDistance: fromHandle ? 0 : 6)
            .onChanged { v in
                if dragStartHeight == nil {
                    // First frame — decide ownership.
                    if !fromHandle {
                        guard panelHeight <= peekGrab else { return }  // scroll owns it
                        listDragActive = true
                    }
                    dragStartHeight = panelHeight
                }
                if !fromHandle && !listDragActive { return }
                let proposed = (dragStartHeight ?? panelHeight) - v.translation.height
                if proposed > maxH { panelHeight = maxH + (proposed - maxH) * 0.18 }
                else if proposed < minH { panelHeight = minH - (minH - proposed) * 0.18 }
                else { panelHeight = proposed }
            }
            .onEnded { v in
                let owned = dragStartHeight != nil && (fromHandle || listDragActive)
                dragStartHeight = nil
                listDragActive = false
                guard owned else { return }
                let velocity = v.predictedEndTranslation.height - v.translation.height
                let projected = panelHeight - velocity * 0.45
                let target = detents(maxHeight).min(by: { abs($0 - projected) < abs($1 - projected) }) ?? minH
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panelHeight = target }
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
        // Up to 8 — the row's chip strip scrolls horizontally, so every bus at
        // the stop is reachable (1 tap → its route) without opening the stop.
        return (favs + rest).prefix(8).map { RankedArrival(service: $0, fav: isFav($0)) }
    }
}

// MARK: - Map content (Equatable → skipped while the sheet is dragged)

private struct MapContentView: View, Equatable {
    @Binding var camera: MapCameraPosition
    let cameraVersion: Int
    let userCoord: CLLocationCoordinate2D?
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
            && Self.coordKey(a.userCoord) == Self.coordKey(b.userCoord)
            && a.stops == b.stops
            && a.stations == b.stations
            && a.buses == b.buses
    }

    /// Round to ~11 m so GPS jitter doesn't re-render the map every fix (which
    /// would defeat the drag-skip optimisation), but a real move still updates.
    private static func coordKey(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "nil" }
        return "\(Int(c.latitude * 10000)),\(Int(c.longitude * 10000))"
    }

    var body: some View {
        Map(position: $camera) {
            // Custom "you are here" dot — a pulsing halo + white-ringed blue
            // core, unmistakable against the indigo stop pins (the default
            // UserAnnotation's system-blue dot was too close to them).
            if let uc = userCoord {
                Annotation("Your location", coordinate: uc, anchor: .center) { UserDot() }
                    .annotationTitles(.hidden)
            }
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

/// The user's own location — a continuously pulsing halo around a white-ringed
/// blue core. Motion + the strong white ring make it pop out from the static
/// stop/station pins regardless of their colour.
private struct UserDot: View {
    @State private var pulse = false
    private let blue = Color(hex: "0A84FF")
    var body: some View {
        ZStack {
            Circle().fill(blue.opacity(0.28))
                .frame(width: 50, height: 50)
                .scaleEffect(pulse ? 1.0 : 0.45)
                .opacity(pulse ? 0 : 0.9)
            Circle().fill(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            Circle().fill(blue)
                .frame(width: 18, height: 18)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel("Your location")
    }
}
