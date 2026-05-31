// SoftBusView — Leyne 3.0 immersive bus tracking. A full-bleed live map
// with a draggable bottom sheet on top. The sheet's PEEK answers the only
// question that matters at a glance — "when's my bus" — with a
// confidence-aware hero ETA, a LIVE/ESTIMATED/SCHEDULED status pill, which
// stop it's for, and the crowd. PULLING THE SHEET UP reveals the alerts and
// the full route timeline inline (no separate screen).
//
// Honest throughout, exactly as the design's thesis demands: we never draw
// a fake bus position (LTA shares none), never invent per-stop times, and
// the confidence treatment softens/dashes anything we're unsure about.

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
    @StateObject private var loc = LocationManager.shared

    private var t: Theme { m.t }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    /// Stop-level feed freshness — feeds the per-arrival confidence below.
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }

    /// Confidence for the tracked service: ghost when LTA isn't GPS-tracking
    /// it, stale when the feed has aged, live otherwise.
    private var confidence: ArrivalConfidence {
        guard let s = liveService() else { return .none }
        return ArrivalConfidence.of(monitored: s.monitored, feed: feed)
    }

    /// True when the tracked bus is monitored and LTA gave us a GPS position,
    /// so it can be plotted on the map.
    private var busHasLivePosition: Bool { liveService()?.busLat != nil }

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed live map — the immersive backdrop.
            mapBackground
                .ignoresSafeArea()

            // Floating controls over the map (back · route badge · pin).
            floatingTopControls
                .padding(.horizontal, 16)
                .padding(.top, 6)

            // Draggable sheet pinned to the bottom. Peek = the answer;
            // pull up = alerts + full route.
            DraggableSheet(t: t, peek: 322) {
                sheetHeader
            } content: {
                sheetBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            ds.ensureArrivals(stop: stopCode)
            loadRoute()
            if let s = ds.stopByCode[stopCode] { centerOnStop(s) }
        }
    }

    // MARK: Floating controls

    private var floatingTopControls: some View {
        HStack(spacing: 10) {
            // Back — a solid circle so it stays legible over any map tile.
            Button {
                fb.select(); onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 40, height: 40)
                    .background(t.surface, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(ds.stopName(stopCode))")

            // Route badge — the bus identity, self-labeling over the map.
            HStack(spacing: 7) {
                Image(systemName: "bus.fill").font(.system(size: 15, weight: .bold))
                Text(svc).font(t.sans(19, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(t.contrastFg)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(t.contrast, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 5, y: 1)

            Spacer(minLength: 0)

            // Recenter on the user's location — a custom control so it stays
            // within the safe area (MapKit's own button bled into the status
            // bar on the full-bleed map).
            Button {
                fb.select()
                withAnimation(.easeInOut(duration: 0.3)) {
                    camera = .userLocation(fallback: .automatic)
                    didCenterOnStop = false   // allow re-centering on the stop later
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 40, height: 40)
                    .background(t.surface, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center on my location")

            // Pin — preserves the existing pin-to-Home affordance.
            Button {
                fb.select(); togglePin()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isPinned ? "Pinned" : "Pin")
                        .font(t.sans(13, weight: .semibold))
                }
                .foregroundStyle(isPinned ? t.onAccent : t.fg)
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(isPinned ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.surface),
                            in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Unpin this stop" : "Pin this stop to Home")
        }
    }

    // MARK: Sheet header (always visible in the peek)

    private var sheetHeader: some View {
        let service = liveService()
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Bus service", t: t)
                Text("Towards \(service?.dest ?? "—")")
                    .font(t.sans(15.5, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            ConfidenceStatusPill(confidence: confidence, t: t)
        }
    }

    // MARK: Sheet body (peek shows the hero; pull-up reveals the rest)

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(t.line)
            heroETA
            if confidence == .stale || confidence == .unconfirmed {
                honestNote
            }
            alertsSection
            routeSection
            Color.clear.frame(height: 8)
        }
        .padding(.top, 12)
    }

    /// The hero answer: ARRIVES IN → big confidence-treated numeral, then a
    /// single quiet line tying it to the stop + crowd. No "N stops away" —
    /// that needs a live bus position LTA doesn't give us.
    private var heroETA: some View {
        let service = liveService()
        let eta = service.map { fmtETA($0.etaSec) }
        let next = service.map { fmtETA($0.followingSec) }
        let third = service?.thirdDate.map { d -> ETA in
            fmtETA(max(0, Int(d.timeIntervalSinceNow)))
        }
        let arriving = (eta?.big == "Arr")
        let imminent = confidence == .live && (eta?.live ?? false)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: arriving ? "Arriving" : "Arrives in", t: t)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(arriving
                         ? "Now"
                         : "\(confidence.etaPrefix)\(eta?.big ?? "—")")
                        .font(t.mono(56))
                        .tracking(-2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(confidence.numeralColor(imminent: imminent, t: t))
                        .opacity(confidence.numeralOpacity())
                    if !arriving {
                        Text(eta?.small ?? "")
                            .font(t.mono(18))
                            .foregroundStyle(imminent ? t.accent : t.dim)
                    }
                    Spacer()
                    // The next two real arrivals, kept small to the side.
                    if let next {
                        VStack(alignment: .trailing, spacing: 2) {
                            Eyebrow(text: "Then", t: t)
                            HStack(spacing: 6) {
                                Text(next.big + next.small)
                                    .font(t.mono(13, weight: .semibold))
                                    .foregroundStyle(t.fg)
                                if let third {
                                    Text("·").foregroundStyle(t.faint)
                                    Text(third.big + third.small)
                                        .font(t.mono(13, weight: .semibold))
                                        .foregroundStyle(t.fg)
                                }
                            }
                        }
                    }
                }
            }

            // Stop + crowd: "to <stop> (<code>)"  ·  crowd glyph.
            HStack(spacing: 10) {
                Text("to ")
                    .font(t.sans(13)).foregroundStyle(t.dim)
                + Text(ds.stopName(stopCode))
                    .font(t.sans(13, weight: .semibold)).foregroundStyle(t.fg)
                + Text(" (\(stopCode))")
                    .font(t.mono(12)).foregroundStyle(t.dim)
                Spacer(minLength: 8)
                if let load = service?.load {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11)).foregroundStyle(t.dim)
                        CrowdMeter(load: load, t: t, showLabel: false)
                    }
                }
            }
            .lineLimit(1)
        }
    }

    /// One honest sentence explaining a softened/dashed hero, so the rider
    /// understands the dimming is a truth signal, not a glitch.
    private var honestNote: some View {
        HStack(alignment: .top, spacing: 8) {
            ConfidenceDot(confidence: confidence, t: t, size: 7)
                .padding(.top, 3)
            Group {
                if confidence == .stale {
                    Text("Estimated. ").font(t.sans(12, weight: .semibold)).foregroundStyle(t.fg)
                    + Text("The live signal has aged — shown, not faked.")
                        .font(t.sans(12)).foregroundStyle(t.dim)
                } else {
                    Text("Ghost bus. ").font(t.sans(12, weight: .semibold)).foregroundStyle(t.fg)
                    + Text("Timetabled but not transmitting GPS right now.")
                        .font(t.sans(12)).foregroundStyle(t.dim)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Route (revealed on pull-up)

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
                Eyebrow(text: timelineStops.isEmpty
                        ? "Full route"
                        : "Full route · \(timelineStops.count) stops", t: t)
                Rectangle().fill(t.line).frame(height: 1)
            }

            // Honest about the map: monitored buses are plotted at their real
            // LTA GPS position; ghost/scheduled buses have none, so we say so
            // rather than faking a marker.
            HStack(spacing: 7) {
                ConfidenceDot(confidence: busHasLivePosition ? .live : .unconfirmed, t: t, size: 6)
                Text(busHasLivePosition
                     ? "Bus \(svc) is plotted live above (dark pin); your stop is the green pin."
                     : "This bus isn’t transmitting GPS — no live position to map; your stop is the green pin.")
                    .font(t.mono(10)).foregroundStyle(t.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if !timelineStops.isEmpty {
                RouteTimeline(t: t, svc: svc, stops: timelineStops, alightId: $alightId)
                    .onChange(of: alightId) { _, new in scheduleAlight(stopCode: new) }
            }
        }
    }

    // MARK: Alerts (notify + Live Activity) — unchanged wiring

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Alerts", t: t)
            notifyButton
            liveActivityCTA
        }
    }

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
            .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.liveBg), in: Capsule())
            .overlay(Capsule().stroke(on ? Color.clear : t.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on
            ? "Arrival alert on for bus \(svc)"
            : "Notify me before bus \(svc) arrives")
    }

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
                        .background(liveOn ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.liveBg),
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
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(liveOn ? t.accent.opacity(0.4) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveOn
                ? "Stop Live Activity for bus \(svc)"
                : "Start Live Activity for bus \(svc) on your lock screen")
        }
    }

    // MARK: Map background

    private var mapBackground: some View {
        Map(position: $camera) {
            // Bus stop — green accent pin.
            if let stop = ds.stopByCode[stopCode] {
                Annotation(stop.Description,
                           coordinate: CLLocationCoordinate2D(
                            latitude: stop.Latitude, longitude: stop.Longitude),
                           anchor: .bottom) {
                    MapStopMarker(t: t)
                        .accessibilityLabel("Bus stop \(stop.Description)")
                }
            }
            // Other stops on the journey — faint dots, so the three primary
            // markers stay the focus.
            if let r = route {
                ForEach(journeySegment(r).filter { $0.code != stopCode }, id: \.code) { rs in
                    Annotation(rs.name,
                               coordinate: CLLocationCoordinate2D(
                                latitude: rs.lat, longitude: rs.lon)) {
                        Circle().fill(t.dim.opacity(0.5)).frame(width: 6, height: 6)
                    }
                }
            }
            // Live bus — dark pill + bus glyph + number, at its real GPS
            // position. Only for monitored arrivals (ghost buses have no
            // coordinate, so none is drawn rather than faking one).
            if let s = liveService(), let lat = s.busLat, let lon = s.busLon {
                Annotation("Bus \(svc)",
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                           anchor: .center) {
                    MapBusMarker(t: t, svc: svc)
                        .accessibilityLabel("Bus \(svc), live position")
                }
            }
            // You — a blue person marker, unmistakably distinct from the green
            // stop pin (the system dot inherited the green accent tint and
            // looked identical to the stop).
            if let here = loc.location {
                Annotation("You", coordinate: here.coordinate, anchor: .center) {
                    MapUserMarker().accessibilityLabel("Your location")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        // No `.mapControls { MapUserLocationButton() }`: on a full-bleed map
        // MapKit anchors its controls to the map's edges, so the location
        // button rode up under the status bar / battery. We provide our own
        // recenter button in `floatingTopControls`, which sits in the safe area.
        .onChange(of: ds.stopByCode[stopCode]) { _, stop in
            guard let s = stop, !didCenterOnStop else { return }
            centerOnStop(s)
        }
    }

    // MARK: Data helpers (unchanged)

    private var allServiceNos: [String] {
        if case .loaded(let s) = ds.arrivals[stopCode] { return s.map(\.no) }
        return [svc]
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
            center: CLLocationCoordinate2D(latitude: stop.Latitude, longitude: stop.Longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
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
}

// MARK: - Draggable bottom sheet

/// A bottom sheet that snaps between a `peek` height and (near) full height.
/// Drag the handle to move it, release to snap to the nearest state, or tap
/// the handle to toggle. It lives in a ZStack over the map — no modal
/// presentation — so it composes cleanly inside a NavigationStack push and
/// leaves the upper map interactive while collapsed.
struct DraggableSheet<Handle: View, Content: View>: View {
    let t: Theme
    var peek: CGFloat
    @ViewBuilder var handle: () -> Handle
    @ViewBuilder var content: () -> Content

    @State private var expanded = false
    @State private var drag: CGFloat = 0

    private let snap = Animation.spring(response: 0.36, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            let sheetH = max(peek, geo.size.height * 0.92)
            let collapsedY = sheetH - peek
            let baseY = expanded ? 0 : collapsedY
            let y = min(max(baseY + drag, 0), collapsedY)

            VStack(spacing: 0) {
                handleBar
                ScrollView {
                    content()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                }
                .scrollDisabled(!expanded)
            }
            .frame(width: geo.size.width, height: sheetH, alignment: .top)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: -6)
            .offset(y: y)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var handleBar: some View {
        VStack(spacing: 0) {
            Capsule().fill(t.faint)
                .frame(width: 40, height: 5)
                .padding(.top, 10).padding(.bottom, 8)
            handle()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(t.surface)
        .contentShape(Rectangle())
        .gesture(
            // `.global` space is essential: the sheet is offset *by* this
            // drag, so measuring in `.local` makes the view move under the
            // finger and halves the reported translation — which is why it
            // felt like you had to drag past mid-screen. Global = screen
            // coordinates, so 1pt of finger = 1pt of sheet.
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { v in drag = v.translation.height }
                .onEnded { v in
                    // predictedEndTranslation carries the flick's momentum, so
                    // a quick upward flick expands without a long drag.
                    let p = v.predictedEndTranslation.height
                    withAnimation(snap) {
                        if p < -50 { expanded = true }
                        else if p > 50 { expanded = false }
                        // else: barely moved — settle back to current state.
                        drag = 0
                    }
                }
        )
        .onTapGesture {
            withAnimation(snap) { expanded.toggle() }
        }
        .accessibilityElement()
        .accessibilityLabel(expanded ? "Collapse details" : "Expand for alerts and full route")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { withAnimation(snap) { expanded.toggle() } }
    }
}

// MARK: - Map markers (shared icon language with the Android map)

/// Stop marker — a green teardrop pin carrying a mappin glyph. A *bus* glyph
/// here read as the bus's live location, contradicting the "position isn't
/// shared yet" honesty; a mappin states plainly that this marks the stop.
struct MapStopMarker: View {
    let t: Theme
    var body: some View {
        Image(systemName: "mappin.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(t.onAccent)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(t.accent).overlay(Circle().stroke(.white, lineWidth: 2))
            )
            .background(
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(t.accent)
                    .offset(y: 12)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// "You" — the user's live position. Blue + person glyph so it can never be
/// confused with the green stop pin (the system location dot inherited the
/// app's green accent tint and looked identical to the stop).
struct MapUserMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.16)).frame(width: 34, height: 34)
            Image(systemName: "person.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.blue))
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Live bus — a dark capsule carrying a bus glyph + the service number, so a
/// moving vehicle reads distinctly from the stationary stop pin and the
/// blue "you" marker.
struct MapBusMarker: View {
    let t: Theme
    let svc: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bus.fill").font(.system(size: 12, weight: .bold))
            Text(svc).font(t.mono(13, weight: .bold))
        }
        .foregroundStyle(t.contrastFg)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(t.contrast, in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

/// Map legend pill — same iconography as the on-map markers.
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
