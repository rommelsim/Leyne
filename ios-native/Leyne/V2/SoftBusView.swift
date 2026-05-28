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
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 1.3083, longitude: 103.8617),
        span:   MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    ))

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
            HStack(spacing: 12) {
                Eyebrow(text: "Live map", t: t)
                Spacer()
                HStack(spacing: 10) {
                    LegendDot(label: "BUS \(svc)", color: t.accent, t: t)
                    LegendDot(label: "STOP", color: t.accent, t: t)
                    LegendDot(label: "ME", color: t.meBlue, t: t)
                }
            }
            Map(position: $camera) {
                if let r = route {
                    ForEach(journeySegment(r), id: \.code) { rs in
                        Annotation(rs.name, coordinate: CLLocationCoordinate2D(latitude: rs.lat, longitude: rs.lon)) {
                            Circle()
                                .fill(rs.code == stopCode ? t.accent : t.dim)
                                .frame(width: 8, height: 8)
                        }
                    }
                    if let coord = r.busCoord {
                        Annotation("Bus \(svc)", coordinate: coord) {
                            ServiceBadge(svc: svc, t: t, size: .sm)
                        }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
}
