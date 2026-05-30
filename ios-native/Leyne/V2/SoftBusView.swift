// SoftBusView — Leyne 2.0 Bus tracking: large arrival numeral,
// Live Activity CTA (Lock Screen / Dynamic Island), live map,
// tappable route timeline.

import SwiftUI
import MapKit
import ActivityKit

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

            VStack(spacing: 0) {
                // Pinned action row — Back / Pin stay reachable while the
                // route timeline scrolls. Mirrors DetailView's
                // [topBar, ScrollView] structure rather than letting the
                // controls scroll off the top of a long route.
                topActionRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        arrivalCard
                        alertsSection
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
                .refreshable {
                    await ds.refreshArrivals(stop: stopCode)
                    loadRoute()
                }
            }
        }
        .onAppear {
            ds.ensureArrivals(stop: stopCode)
            loadRoute()
        }
    }

    private var topActionRow: some View {
        HStack {
            // Back pill carries the stop's own name (the place the user is
            // looking at / came from) instead of the literal word "Stop", so
            // the affordance reads "‹ Beauty World". Truncate by tail so a
            // long name stays a single line and never wraps the pill.
            GlassPillButton(t: t, icon: "chevron.left",
                            label: ds.stopName(stopCode),
                            action: { fb.select(); onBack() })
                // Let the pin pill keep its full width; the back pill's long
                // stop name truncates (tail) rather than crowding it.
                .layoutPriority(0)
                .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 8)
            GlassPillButton(t: t,
                            icon: isPinned ? "pin.fill" : "pin",
                            label: isPinned ? "Unpin" : "Pin",
                            filled: isPinned,
                            action: { fb.select(); togglePin() })
        }
    }

    // v3 header: the SERVICE NUMBER is the hero. A small dim context line
    // (walk time · stop name) sits above the headline; the stop name is
    // demoted out of the title role it held in v2.
    private var headerSection: some View {
        let service = liveService()
        return VStack(alignment: .leading, spacing: 6) {
            // Context line: a location pin + "<road> · <stop name>". We have no
            // walk-time source, so a `figure.walk` icon here read as a broken
            // "walk N min" with the minutes missing. A mappin states plainly
            // that this is *where* the bus is being tracked from.
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                Text(contextLine)
                    .font(t.mono(11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(t.dim)

            Eyebrow(text: "Bus", t: t)
            Text(svc)
                .font(t.sans(40, weight: .bold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Towards \(service?.dest ?? "—")")
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// "<stop name>" or, when a road name exists, "<road> · <stop name>".
    /// No walk-time minute is shown because we have no routing source for it
    /// — fabricating "4 min" would be a precision the app can't back up.
    private var contextLine: String {
        let name = ds.stopName(stopCode)
        let road = ds.roadName(stopCode)
        return road.isEmpty ? name : "\(road) · \(name)"
    }

    private var arrivalCard: some View {
        let service = liveService()
        let eta = service.map { fmtETA($0.etaSec) }
        let next = service.map { fmtETA($0.followingSec) }
        let third = service?.thirdDate.map { d -> ETA in
            let s = max(0, Int(d.timeIntervalSinceNow))
            return fmtETA(s)
        }

        return VStack(alignment: .leading, spacing: 14) {
            // ETA-led row: "ARRIVES IN" + big numeral on the left, the
            // live-vs-scheduled provenance chip on the right. The redundant
            // route/destination pill that used to sit here is gone — the
            // header already states the bus number and direction.
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    // When the bus is arriving, fmtETA returns big "Arr" /
                    // small "now". At mono(56) "Arr" clipped — the numeral
                    // slot is sized for two digits, and Dynamic Type made it
                    // worse. So render the arriving state as eyebrow
                    // "Arriving" + hero "Now" (no redundant "ARRIVES IN: Arr
                    // now"), and reserve the big slot for real minute counts.
                    // lineLimit + minimumScaleFactor are the scale safety net.
                    let arriving = (eta?.big == "Arr")
                    Eyebrow(text: arriving ? "Arriving" : "Arrives in", t: t)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(arriving ? "Now" : (eta?.big ?? "—"))
                            .font(t.mono(56))
                            .tracking(-2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(t.accent)
                        if !arriving {
                            Text(eta?.small ?? "")
                                .font(t.mono(13))
                                .foregroundStyle(t.dim)
                        }
                    }
                }
                Spacer()
                if let service {
                    liveStatusChip(service.monitored)
                }
            }

            Divider().overlay(t.line)

            // THEN: the next two real arrivals (following + third). "Then"
            // reads as a time sequence ("then 20min · 35min"), matching the
            // vocabulary in DetailView/PinnedCardView; "Following" was
            // ambiguous — it can mean "the bus you're following".
            HStack {
                Eyebrow(text: "Then", t: t)
                Spacer()
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
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Right-aligned provenance chip beside the ETA. Live (GPS-monitored)
    /// shows a green dot + "Live · GPS"; scheduled shows a clock + dim
    /// "~ Scheduled". Mirrors the `Service.monitored` flag used elsewhere.
    @ViewBuilder
    private func liveStatusChip(_ monitored: Bool) -> some View {
        HStack(spacing: 5) {
            if monitored {
                Circle().fill(t.accent).frame(width: 7, height: 7)
                Text("Live · GPS")
            } else {
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text("~ Scheduled")
            }
        }
        .font(t.mono(11, weight: .medium))
        .foregroundStyle(monitored ? t.accent : t.dim)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            (monitored ? t.liveBg : t.surfaceHi),
            in: Capsule()
        )
        .overlay(Capsule().stroke(monitored ? t.accent.opacity(0.4) : t.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monitored
            ? "Live arrival, tracked by GPS"
            : "Scheduled estimate, not GPS tracked")
    }

    /// Full-width subtle-green capsule that toggles an arrival alert for
    /// THIS bus at THIS stop. The mockup label ("Notify me when it's 1 stop
    /// away") implies live bus-position data we don't have, so we wire the
    /// real mechanism instead — `m.toggleTracked`, which makes the bus
    /// eligible for the arrival-alert that AppModel fires ~1 min before
    /// arrival — and relabel honestly to match what actually happens.
    private var notifyButton: some View {
        let on = m.isTracked(code: stopCode, busNo: svc)
        return Button {
            fb.select()
            m.toggleTracked(code: stopCode, busNo: svc, allNos: allServiceNos)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                Text(on ? "Alert on — tap to cancel" : "Notify me before it arrives")
                    .font(t.sans(14, weight: .semibold))
            }
            .foregroundStyle(on ? t.onAccent : t.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.liveBg),
                in: Capsule()
            )
            .overlay(Capsule().stroke(on ? Color.clear : t.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on
            ? "Arrival alert on for bus \(svc)"
            : "Notify me before bus \(svc) arrives")
    }

    /// All service numbers currently arriving at this stop — passed to
    /// `toggleTracked` so untracking the last one collapses to "no buses"
    /// correctly and tracking everything maps back to the "all" state.
    private var allServiceNos: [String] {
        if case .loaded(let s) = ds.arrivals[stopCode] {
            return s.map(\.no)
        }
        return [svc]
    }

    // MARK: Alerts
    // Groups the two ways to be alerted under one "ALERTS" header so they
    // read as two flavors of one intent, not duplicate buttons:
    //  • notifyButton    — a single heads-up ~1 min before arrival.
    //  • liveActivityCTA — a persistent Lock Screen / Dynamic Island feed.
    // The arrival card above is now pure info (ETA + next two); the
    // actions live here. When Live Activities are unavailable the CTA
    // collapses and only the notify capsule shows under the header.
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Alerts", t: t)
            notifyButton
            liveActivityCTA
        }
    }

    // MARK: Live Activity CTA
    // Starts/stops the real ActivityKit Live Activity for this bus on the
    // Lock Screen + Dynamic Island. The whole engine — request, 15 s LTA
    // polling, stops-away, auto-end on arrival, relaunch restore — lives in
    // AppModel (toggleLiveActivity / startLivePolling). This is just the V2
    // entry point; the label reflects the live on/off state like the bell.
    //
    // Shown only when (a) we have a real arriving service to attach to and
    // (b) the user hasn't disabled Live Activities system-wide — otherwise
    // the tap would silently no-op, which is the dead-button trust bug.
    @ViewBuilder
    private var liveActivityCTA: some View {
        if let service = liveService(),
           ActivityAuthorizationInfo().areActivitiesEnabled {
            let liveOn = m.isLiveActivityActive(service, stopCode: stopCode)
            Button {
                fb.select()
                m.toggleLiveActivity(service,
                                     stopName: ds.stopName(stopCode),
                                     stopCode: stopCode)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: liveOn ? "stop.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(liveOn ? t.onAccent : t.accent)
                        .frame(width: 40, height: 40)
                        .background(liveOn ? AnyShapeStyle(t.accent)
                                           : AnyShapeStyle(t.liveBg),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(liveOn ? "Stop Live Activity" : "Start Live Activity")
                            .font(t.sans(14, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(liveOn ? "Bus \(svc) is on your lock screen"
                                    : "Follow Bus \(svc) from your lock screen")
                            .font(t.sans(12))
                            .foregroundStyle(t.dim)
                    }
                    Spacer()
                    Image(systemName: liveOn ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(liveOn ? t.accent : t.dim)
                }
                .padding(12)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(liveOn ? t.accent.opacity(0.4) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveOn
                ? "Stop Live Activity for bus \(svc)"
                : "Start Live Activity for bus \(svc) on your lock screen")
        }
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
                                longitude: stop.Longitude),
                               // Anchor at the teardrop's tip so the marker body
                               // floats *above* the coordinate. When the user is
                               // standing at the stop this lifts the stop pin off
                               // the system blue user-location dot instead of
                               // covering it.
                               anchor: .bottom) {
                        MapStopMarker(t: t)
                            .accessibilityLabel("Bus stop \(stop.Description)")
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
                    // No live bus annotation: r.busCoord is always nil today
                    // (DataStore.route hard-codes it). Restore a bus marker
                    // here once real bus-coordinate data exists.
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Honest bus-absent state: we never receive a live bus location
            // from LTA, so say so plainly instead of implying a missing dot.
            HStack(spacing: 6) {
                Image(systemName: "bus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Bus \(svc)’s live position isn’t shared yet — tracking by arrival time.")
                    .font(t.mono(10))
            }
            .foregroundStyle(t.dim)
            .fixedSize(horizontal: false, vertical: true)
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
            return RouteStop(id: stop.code, name: stop.name, state: state)
        }
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
        // Arm (or clear) the real alight alert through AppModel, which
        // schedules the actual notification. fireAt mirrors DetailView:
        // 90 s × (stopsToAlight − 2) from now, so the heads-up lands about
        // two stops before the drop-off.
        guard let code, let r = route,
              let alightIdx = r.stops.firstIndex(where: { $0.code == code }) else {
            m.clearActiveAlight()
            return
        }
        let base = r.busIndex ?? r.youIndex
        let stopsToWait = max(0, (alightIdx - base) - 2)
        let fireAt = Date().addingTimeInterval(TimeInterval(stopsToWait) * 90)
        m.setActiveAlight(busNo: svc, stopCode: code,
                          stopName: r.stops[alightIdx].name, fireAt: fireAt)
    }

    private var mapLegend: some View {
        // No BUS entry: LTA gives us no live bus coordinate (DataStore.route
        // hard-codes busCoord: nil), so a "BUS" key would promise a marker
        // that can never appear. STOP (accent pin) and YOU (system blue dot)
        // are the only two things actually drawn — keep the legend honest.
        HStack(spacing: 12) {
            MapLegendItem(t: t, system: "mappin.fill",
                          fill: t.accent, label: "STOP")
            MapLegendItem(t: t, system: "location.fill",
                          fill: t.meBlue, label: "YOU")
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Map markers (shared icon language with the Android map)

/// Stop marker — a green teardrop pin carrying a mappin glyph. A *bus*
/// glyph here read as the bus's live location, directly contradicting the
/// "live position isn't shared yet" caption below the map; a mappin states
/// plainly that this marks *where the stop is*. The teardrop silhouette +
/// white ring keep it distinct from the smaller system-blue user-location
/// dot (YOU). There is exactly one of these on the map.
struct MapStopMarker: View {
    let t: Theme
    var body: some View {
        Image(systemName: "mappin.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(t.onAccent)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(t.accent)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            )
            .background(
                // Teardrop tail so the marker reads as a pin, not a dot.
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(t.accent)
                    .offset(y: 12)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
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
