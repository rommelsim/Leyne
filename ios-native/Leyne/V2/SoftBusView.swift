// SoftBusView — Leyne 2.0 Bus tracking: large arrival numeral,
// Live Activity CTA, live map, tappable route timeline.

import SwiftUI
import MapKit

struct SoftBusView: View {
    let stopCode: String
    let svc: String
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void

    @State private var alightId: String? = nil
    @State private var route: RouteInfo?
    @State private var camera: MapCameraPosition = .automatic
    @State private var didCenterOnStop = false

    private var t: Theme { m.t }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topActionRow
                    compactStopHeader
                    arrivalCard
                    liveActivityCTA
                    liveMapSection
                    if !timelineStops.isEmpty {
                        RouteTimeline(t: t,
                                      svc: svc,
                                      stops: timelineStops,
                                      alightId: $alightId)
                            .onChange(of: alightId) { _, new in
                                scheduleAlight(stopCode: new)
                            }
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .onAppear {
            ds.ensureArrivals(stop: stopCode)
            loadRoute()
        }
    }

    private var topActionRow: some View {
        HStack {
            GlassPillButton(t: t, icon: "chevron.left", label: "Stop",
                            action: { fb.select(); onBack() })
            Spacer()
            GlassPillButton(t: t,
                            icon: isPinned ? "pin.fill" : "pin",
                            label: isPinned ? "Pinned" : "Pin",
                            filled: isPinned,
                            action: { fb.select(); togglePin() })
        }
    }

    private var compactStopHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "STOP \(stopCode)", t: t)
            Text(ds.stopName(stopCode))
                .font(t.sans(24, weight: .semibold))
                .foregroundStyle(t.fg)
            HStack(spacing: 6) {
                Image(systemName: "figure.walk").font(.system(size: 12))
                Text(ds.roadName(stopCode).isEmpty ? "Live · LTA" : ds.roadName(stopCode))
                    .font(t.mono(11))
            }
            .foregroundStyle(t.dim)
        }
    }

    private var arrivalCard: some View {
        let service = liveService()
        let eta = service.map { fmtETA($0.etaSec) }
        let next = service.map { fmtETA($0.followingSec) }
        let third = service?.thirdDate.map { d -> ETA in
            let s = max(0, Int(d.timeIntervalSinceNow))
            return fmtETA(s)
        }

        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ServiceBadge(svc: svc, t: t, size: .sm)
                    Text("→ \(service?.dest ?? "—")")
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                }
                Eyebrow(text: "Next arrival", t: t)
                Spacer()
                Eyebrow(text: "Following", t: t)
                HStack(spacing: 8) {
                    Text(next.map { $0.big + $0.small } ?? "—")
                        .font(t.mono(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                    if let th = third {
                        Text("·").foregroundStyle(t.faint)
                        Text(th.big + th.small)
                            .font(t.mono(14, weight: .semibold))
                            .foregroundStyle(t.fg)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(eta?.big ?? "—")
                    .font(.system(size: 56, weight: .regular, design: .monospaced))
                    .tracking(-2)
                    .foregroundStyle(t.accent)
                Text(eta?.small ?? "")
                    .font(t.mono(12))
                    .foregroundStyle(t.dim)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var liveActivityCTA: some View {
        Button {
            fb.select()
            // ActivityKit wiring tracked in parity.md Task #12
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 40, height: 40)
                    .background(t.liveBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Live Activity")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text("Follow Bus \(svc) from your lock screen")
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var liveMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Live map", t: t)
            mapLegend
            Map(position: $camera) {
                // The user's bus stop — a pin so the map has at least
                // one annotation while the route loads.
                if let stop = ds.stopByCode[stopCode] {
                    Annotation(stop.Description,
                               coordinate: CLLocationCoordinate2D(
                                latitude: stop.Latitude,
                                longitude: stop.Longitude)) {
                        MapStopMarker(t: t)
                    }
                }
                if let r = route {
                    // Other stops on this journey — small dots so the
                    // primary stop pin stays the visual focus.
                    ForEach(journeySegment(r).filter { $0.code != stopCode },
                            id: \.code) { rs in
                        Annotation(rs.name,
                                   coordinate: CLLocationCoordinate2D(
                                    latitude: rs.lat, longitude: rs.lon)) {
                            Circle().fill(t.dim).frame(width: 6, height: 6)
                        }
                    }
                    if let coord = r.busCoord {
                        Annotation("Bus \(svc)", coordinate: coord) {
                            MapBusMarker(t: t, svc: svc)
                        }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Recenter the camera once the user's bus stop is known. The
            // initial value is `.automatic` so the map fits its
            // annotations; this explicit region pull is here so the map
            // also re-centres if the stop data lands after the view did.
            .onChange(of: ds.stopByCode[stopCode]) { _, stop in
                guard let s = stop, !didCenterOnStop else { return }
                centerOnStop(s)
            }
            .onAppear {
                if let s = ds.stopByCode[stopCode] { centerOnStop(s) }
            }
        }
    }

    private var timelineStops: [RouteStop] {
        guard let r = route else { return [] }
        let segment = journeySegment(r)
        let busSeq = r.busIndex
        let youSeq = r.youIndex
        return segment.map { stop -> RouteStop in
            let idx = r.stops.firstIndex(where: { $0.code == stop.code }) ?? -1
            let state: RouteStopState
            if let b = busSeq, idx == b { state = .here }
            else if idx == youSeq { state = .board }
            else if idx < (busSeq ?? -1) { state = .past }
            else { state = .next }
            let etaMin: Int? = state == .next
                ? estimatedMinutes(fromIndex: idx, route: r)
                : nil
            return RouteStop(id: stop.code, name: stop.name, state: state, etaMin: etaMin)
        }
    }

    private func estimatedMinutes(fromIndex idx: Int, route r: RouteInfo) -> Int? {
        guard let svc = liveService() else { return nil }
        let baseMin = max(0, svc.etaSec / 60)
        let yIdx = max(0, r.youIndex)
        let delta = idx - yIdx
        return max(0, baseMin + delta * 2)   // rough 2 min/stop heuristic
    }

    private func liveService() -> Service? {
        if case .loaded(let s) = ds.arrivals[stopCode] {
            return s.first { $0.no == svc }
        }
        return nil
    }

    private func loadRoute() {
        Task {
            let r = await ds.route(service: svc, stopCode: stopCode)
            await MainActor.run { self.route = r }
        }
    }

    private func centerOnStop(_ stop: LTABusStop) {
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: stop.Latitude, longitude: stop.Longitude),
            span: MKCoordinateSpan(
                latitudeDelta: 0.006, longitudeDelta: 0.006)))
        didCenterOnStop = true
    }

    private func togglePin() {
        if isPinned {
            m.pins.removeAll { $0.code == stopCode }
        } else {
            m.pins.append(Pin(code: stopCode, nickname: ""))
        }
    }

    private func scheduleAlight(stopCode code: String?) {
        // Phase 3 wires this to NotificationsManager.scheduleAlight(_:)
        // For now just store via AppModel UserDefaults keys directly.
        guard let code else { return }
        UserDefaults.standard.set(svc, forKey: "lyne.alight.busNo")
        UserDefaults.standard.set(code, forKey: "lyne.alight.stopCode")
        UserDefaults.standard.set(ds.stopName(code), forKey: "lyne.alight.stopName")
        UserDefaults.standard.set(
            Date().addingTimeInterval(TimeInterval(15 * 60)).timeIntervalSince1970,
            forKey: "lyne.alight.fireAt")
    }

    private var mapLegend: some View {
        HStack(spacing: 12) {
            MapLegendItem(t: t, system: "mappin.and.ellipse",
                          fill: t.accent, label: "STOP")
            MapLegendItem(t: t, system: "bus.fill",
                          fill: t.accent, label: "BUS \(svc)")
            MapLegendItem(t: t, system: "location.fill",
                          fill: t.meBlue, label: "YOU")
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Map markers (shared icon language with the Android map)

/// Stop marker — accent-coloured pin SF Symbol with a soft shadow so it
/// stays legible over varied map tiles.
struct MapStopMarker: View {
    let t: Theme
    var body: some View {
        Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(t.accent)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// Bus marker — accent pill with bus icon + service number. Matches the
/// Android marker pixel-for-pixel in spirit.
struct MapBusMarker: View {
    let t: Theme
    let svc: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(svc)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(t.onAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.accent, in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
        .shadow(color: t.accent.opacity(0.6), radius: 4)
    }
}

/// Map legend pill — same iconography as the on-map markers so the
/// reader can match the legend to what they see on the map at a glance.
struct MapLegendItem: View {
    let t: Theme
    let system: String
    let fill: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(fill)
            Text(label)
                .font(t.mono(9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(t.dim)
        }
    }
}
