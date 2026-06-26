// SoftMapHomeView — map-first Home (redesign, branch `redesign-main-view`).
//
// Layout (Apple-Maps idiom):
//   • Full-screen map: you + nearby bus stops (indigo markers) + MRT stations
//     (per-line colours). Tap a marker → preview in the sheet; tap the empty map
//     → collapse the sheet.
//   • Draggable bottom sheet: search field, "Leaving near you" header, then rich
//     stop rows (name · walk · the next few buses as urgency-coloured chips). One
//     native ad lives inside the sheet.
//   • Top bar carries only the bell; recenter is the lone floating map control.
//
// Sheet smoothness: the sheet is rendered at a FIXED height and positioned with
// `.offset` (cheap, no per-frame re-layout / blur recompute) on a solid surface —
// so dragging stays smooth.

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

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Sheet height, dragged between snap detents (peek / half / full).
    @State private var panelHeight: CGFloat = 290
    @State private var dragStartHeight: CGFloat? = nil
    /// One-shot: centre on the user the first time we get a fix, without yanking
    /// the map afterwards if they've panned.
    @State private var didInitialCenter = false
    /// A tapped marker shows a preview in the sheet (at most one non-nil).
    @State private var selectedStop: String? = nil
    @State private var selectedStation: MrtGeoStation? = nil

    private var t: Theme { m.t }

    // Eye-friendly map accent — a calm indigo, gentler than the bright blue and
    // distinct from the green/amber/red status palette. Per appearance.
    private var mapAccent: Color { t.isDark ? Color(hex: "7E7BFF") : Color(hex: "5856D6") }
    private var meGreen: Color { t.isDark ? Color(hex: "22C55E") : Color(hex: "16A34A") }
    private var meAmber: Color { t.isDark ? Color(hex: "F59E0B") : Color(hex: "D97706") }

    private var hasSelection: Bool { selectedStop != nil || selectedStation != nil }

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
                recenterButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16)
                    .padding(.top, 10)
                departuresPanel(maxHeight: geo.size.height)
            }
        }
        .navigationTitle("SG Transit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { alertsBell }
        }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l); centerOnUser() }
            ds.prefetchNearbyArrivals()
            warmArrivals()
        }
        .onChange(of: loc.location) { _, new in
            if let l = new {
                ds.updateNearby(l)
                ds.prefetchNearbyArrivals()
                if !didInitialCenter { centerOnUser() }
            }
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
        // Tap the empty map → collapse the sheet / clear a preview. (Marker
        // buttons consume their own taps, so this only fires off-marker.)
        .onTapGesture { collapseSheet() }
    }

    private func coord(_ code: String) -> CLLocationCoordinate2D? {
        guard let s = ds.stopByCode[code] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

    /// Centre the camera on the user at a comfortable zoom (≈900 m view) — not
    /// the wide auto-frame. Used on first fix and from the recenter button.
    private func centerOnUser() {
        guard let c = loc.location?.coordinate else { return }
        didInitialCenter = true
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)))
        }
    }

    private func stopMarker(_ stop: NearbyStop) -> some View {
        let isSel = selectedStop == stop.stopCode
        return Button { selectStop(stop) } label: {
            Image(systemName: "bus.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(mapAccent, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: isSel ? 3 : 2))
                .overlay(alignment: .topTrailing) {
                    if m.isPinned(stop.stopCode) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(meAmber, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }
                .scaleEffect(isSel ? 1.3 : 1)
                .shadow(color: .black.opacity(0.3), radius: isSel ? 5 : 2, y: 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSel)
        }
        .buttonStyle(.plain)
    }

    private func mrtMarker(_ st: MrtGeoStation) -> some View {
        let isSel = selectedStation?.id == st.id
        return Button { selectStation(st) } label: {
            Image(systemName: "tram.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(stationColor(st), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: isSel ? 3 : 2))
                .scaleEffect(isSel ? 1.3 : 1)
                .shadow(color: .black.opacity(0.3), radius: isSel ? 5 : 2, y: 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSel)
        }
        .buttonStyle(.plain)
    }

    private func stationColor(_ st: MrtGeoStation) -> Color {
        for code in st.codes {
            let prefix = String(code.prefix { $0.isLetter })
            if let line = MRTLine(rawValue: prefix) { return line.color }
        }
        return Color(hex: "E22319")
    }

    private var recenterButton: some View {
        Button {
            fb.select(); centerOnUser()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mapAccent)
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

            searchField
                .padding(.horizontal, 16).padding(.bottom, 10)

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
                    } else if nearbyStops.isEmpty {
                        Text(loc.location == nil
                             ? "Turn on location to see stops near you."
                             : "No stops in range right now.")
                            .font(t.sans(13)).foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        ForEach(Array(nearbyStops.prefix(12).enumerated()),
                                id: \.element.id) { idx, stop in
                            stopRow(stop)
                            if idx == 2 { NativeAdCard() }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        // Fixed height → only the OFFSET moves while dragging, so the content
        // and the (solid) background never re-lay-out per frame = smooth.
        .frame(height: maxDetent)
        .frame(maxWidth: .infinity)
        .background(t.surface,
                    in: UnevenRoundedRectangle(cornerRadii:
                        .init(topLeading: 22, topTrailing: 22), style: .continuous))
        .overlay(
            UnevenRoundedRectangle(cornerRadii:
                .init(topLeading: 22, topTrailing: 22), style: .continuous)
                .stroke(t.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .offset(y: maxDetent - panelHeight)
    }

    private var grabber: some View {
        Capsule().fill(t.faint).frame(width: 40, height: 5)
    }

    private var searchField: some View {
        Button { fb.select(); onOpenSearch() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.dim)
                Text("Search stops, buses, stations")
                    .font(t.sans(15)).foregroundStyle(t.dim)
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
                    }
                    .foregroundStyle(mapAccent)
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

    // MARK: Stop row (taller, with next-bus chips)

    private func stopRow(_ stop: NearbyStop) -> some View {
        let code = stop.stopCode
        let name = stop.stopName.isEmpty ? code : stop.stopName
        let arrivals = rankedArrivals(code)
        return Button { fb.select(); m.addRecent(name); onOpenStop(code) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    pinTile(saved: m.isPinned(code))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(t.sans(16, weight: .semibold))
                            .foregroundStyle(t.fg).lineLimit(1)
                        Text("\(code) · \(ds.roadName(code))")
                            .font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if stop.walkMin > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.walk").font(.system(size: 11, weight: .semibold))
                            Text("\(stop.walkMin) min").font(t.sans(12, weight: .medium))
                        }
                        .foregroundStyle(t.dim)
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
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    /// One upcoming bus: number + ETA (ETA tinted by urgency).
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
                Image(systemName: "star.fill")
                    .font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                    .frame(width: 14, height: 14).background(meAmber, in: Circle())
                    .overlay(Circle().stroke(t.surface, lineWidth: 1.5)).offset(x: 4, y: -4)
            }
        }
    }

    // MARK: Selection (marker → preview)

    private func selectStop(_ stop: NearbyStop) {
        fb.select()
        selectedStation = nil
        selectedStop = stop.stopCode
        recenter(coord(stop.stopCode))
        setSheet(max(panelHeight, 460))
    }

    private func selectStation(_ st: MrtGeoStation) {
        fb.select()
        selectedStop = nil
        selectedStation = st
        recenter(CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon))
        setSheet(max(panelHeight, 380))
    }

    private func clearSelection() {
        fb.select()
        selectedStop = nil
        selectedStation = nil
        setSheet(290)
    }

    /// Tap on the empty map → collapse to peek and drop any preview.
    private func collapseSheet() {
        if !hasSelection && panelHeight <= 320 { return }
        fb.select()
        selectedStop = nil
        selectedStation = nil
        setSheet(290)
    }

    private func setSheet(_ height: CGFloat) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            panelHeight = height
        }
    }

    private func recenter(_ c: CLLocationCoordinate2D?) {
        guard let c else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
    }

    // MARK: Preview cards

    @ViewBuilder
    private func stopPreview(_ code: String) -> some View {
        let stop = nearbyStops.first { $0.stopCode == code }
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
                        let col: Color = s.etaSec <= 120 ? meGreen
                            : (s.etaSec <= 420 ? meAmber : t.fg)
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
                    Text(code)
                        .font(t.mono(11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(codeColor(code), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Text(st.name).font(t.sans(20, weight: .bold)).foregroundStyle(t.fg)
            Text("MRT station").font(t.sans(13)).foregroundStyle(t.dim)
            openButton("Open station") { onOpenMrtStation(st) }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func codeColor(_ code: String) -> Color {
        let prefix = String(code.prefix { $0.isLetter })
        return MRTLine(rawValue: prefix)?.color ?? Color(hex: "E22319")
    }

    private func openButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { fb.select(); action() } label: {
            Text(title)
                .font(t.sans(15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(mapAccent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Drag

    private func detents(_ maxHeight: CGFloat) -> [CGFloat] {
        [290, maxHeight * 0.55, maxHeight * 0.88]
    }

    private func panelDrag(maxHeight: CGFloat) -> some Gesture {
        let maxH = maxHeight * 0.88
        let minH: CGFloat = 230
        return DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStartHeight == nil { dragStartHeight = panelHeight }
                let proposed = (dragStartHeight ?? panelHeight) - v.translation.height
                if proposed > maxH {
                    panelHeight = maxH + (proposed - maxH) * 0.22
                } else if proposed < minH {
                    panelHeight = minH - (minH - proposed) * 0.22
                } else {
                    panelHeight = proposed
                }
            }
            .onEnded { v in
                dragStartHeight = nil
                let velocity = v.predictedEndTranslation.height - v.translation.height
                let projected = panelHeight - velocity * 0.5
                let target = detents(maxHeight)
                    .min(by: { abs($0 - projected) < abs($1 - projected) }) ?? minH
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    panelHeight = target
                }
            }
    }

    // MARK: Toolbar

    private var alertsBell: some View {
        Button { fb.select(); onOpenAlerts() } label: {
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

    private func warmArrivals() {
        for stop in nearbyStops.prefix(12) { ds.ensureArrivals(stop: stop.stopCode) }
    }
}
