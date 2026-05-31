// SoftBusView — Leyne 3.0 immersive bus tracking. A full-bleed live map
// with a draggable bottom sheet on top. The sheet's PEEK answers the only
// question that matters at a glance — "when's my bus" — with a
// confidence-aware hero ETA, a LIVE/ESTIMATED/SCHEDULED status pill, which
// stop it's for, and the crowd. PULLING THE SHEET UP reveals the alerts and
// the full route timeline inline (no separate screen).
//
// The map ALWAYS shows the bus, connected to your stop by a dashed tether,
// in one of three honesty tiers — and the tier is never disguised as more
// certain than it is:
//   • live      — LTA gave a real GPS fix this poll       → solid dark pin
//   • recent    — had a fix, dropped this poll            → dimmed pin, "last seen"
//   • estimated — no fix / ghost bus, position derived    → hollow dashed pin, "≈"
//                 from the route geometry + ETA
// The pin glides between fixes and creeps along the route as the ETA counts
// down, so the bus reads as "en route" even when LTA shares no position.

import SwiftUI
import MapKit
import ActivityKit

/// How confident we are about the bus's *position* on the map (distinct from
/// the arrival-time confidence, which the status pill carries).
enum BusTier { case live, recent, estimated }

/// A resolved bus position to plot, with its tier and (for `recent`) how long
/// ago the underlying GPS fix was seen.
struct BusPlot: Equatable {
    var coord: CLLocationCoordinate2D
    var tier: BusTier
    var ageSec: Int

    static func == (a: BusPlot, b: BusPlot) -> Bool {
        a.tier == b.tier && a.ageSec == b.ageSec
            && a.coord.latitude == b.coord.latitude
            && a.coord.longitude == b.coord.longitude
    }
}

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

    // Bus-position plotting state.
    @State private var plot: BusPlot?                      // current tier + target
    @State private var displayCoord: CLLocationCoordinate2D?  // where the pin is drawn
    @State private var lastFix: (coord: CLLocationCoordinate2D, at: Date)?
    @State private var didAutoFrame = false

    /// Drives the glide/creep + recency aging. App code, so wall-clock Date()
    /// is fine here (the no-Date rule applies only to workflow scripts).
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var t: Theme { m.t }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    /// Stop-level feed freshness — feeds the per-arrival confidence below.
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }

    /// Confidence for the tracked service's *arrival time*: ghost when LTA
    /// isn't GPS-tracking it, stale when the feed has aged, live otherwise.
    /// Used internally for the whisper cue & accessibility — NOT surfaced as a
    /// loud label (see `pillConfidence` / `showWhisper`).
    private var confidence: ArrivalConfidence {
        guard let s = liveService() else { return .none }
        return ArrivalConfidence.of(monitored: s.monitored, feed: feed)
    }

    /// What the status pill shows. Timely-first: we present a confident "LIVE"
    /// whenever there's a bus with a current ETA — only a true no-service state
    /// drops to "—". The fact that a given arrival is estimated/aged is carried
    /// by the whisper cue, not advertised here.
    private var pillConfidence: ArrivalConfidence {
        confidence == .none ? .none : .live
    }

    /// Whether to show the near-invisible "~" whisper: true when the position
    /// is anything other than a fresh live GPS fix (estimated, last-known, or
    /// the feed has aged). Casual users won't notice; power users get a quiet
    /// tell that we're not on a verified fix — without a banner.
    private var showWhisper: Bool {
        guard confidence != .none else { return false }
        return confidence != .live || plot?.tier != .live
    }

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
            recomputePlot()
        }
        .onReceive(ticker) { _ in recomputePlot() }
        .onChange(of: route) { _, _ in recomputePlot() }
        .onChange(of: ds.arrivals[stopCode]) { _, _ in recomputePlot() }
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
                didAutoFrame = true   // user took over framing; don't auto-fit again
                withAnimation(.easeInOut(duration: 0.3)) {
                    camera = .userLocation(fallback: .automatic)
                    didCenterOnStop = false
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
                    .font(t.sans(24, weight: .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            ConfidenceStatusPill(confidence: pillConfidence, t: t)
        }
    }

    // MARK: Sheet body (peek shows the hero; pull-up reveals the rest)

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(t.line)
            heroETA
            alertsSection
            routeSection
            Color.clear.frame(height: 8)
        }
        .padding(.top, 12)
    }

    /// The hero answer: ARRIVING AT <stop> → big confidence-treated numeral,
    /// the next two arrivals to its side, then a quiet stop + crowd line.
    private var heroETA: some View {
        let service = liveService()
        let eta = service.map { fmtETA($0.etaSec) }
        let arriving = (eta?.big == "Arr")
        let imminent = confidence == .live && (eta?.live ?? false)

        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Arriving at \(ds.stopName(stopCode))", t: t)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Always a confident, full-ink number — never dimmed or
                // "~"-prefixed. Timeliness is the promise; the estimate tell is
                // the whisper below, not the hero.
                Text(arriving ? "Now" : (eta?.big ?? "—"))
                    .font(t.mono(64))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(confidence == .none ? t.faint : (imminent ? t.accent : t.fg))
                if !arriving {
                    Text(eta?.small ?? "")
                        .font(t.mono(20))
                        .foregroundStyle(imminent ? t.accent : t.dim)
                }
                // Whisper-quiet estimate tell: a faint "~" only a careful eye
                // catches. No banner, no recolour — just enough to be honest.
                if showWhisper {
                    Text("~")
                        .font(t.mono(15))
                        .foregroundStyle(t.faint)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                if let next = nextTwoLabel {
                    Text(next)
                        .font(t.mono(14, weight: .semibold))
                        .foregroundStyle(t.dim)
                        .padding(.bottom, 6)
                }
            }

            // Stop + distance · crowd.
            HStack(spacing: 10) {
                (Text("Stop ")
                    .font(t.sans(13)).foregroundStyle(t.dim)
                 + Text(stopCode)
                    .font(t.mono(13, weight: .bold)).foregroundStyle(t.fg)
                 + Text(stopDistanceSuffix)
                    .font(t.sans(13)).foregroundStyle(t.dim))
                Spacer(minLength: 8)
                CrowdMeter(load: service?.load, t: t, showLabel: true)
            }
            .lineLimit(1)
        }
    }

    /// "then 18 · 24 min" — the next two real arrivals after the hero.
    private var nextTwoLabel: String? {
        guard let s = liveService() else { return nil }
        let next = fmtETA(s.followingSec)
        guard next.big != "Arr", !next.big.isEmpty else { return nil }
        if let d = s.thirdDate {
            let third = fmtETA(max(0, Int(d.timeIntervalSinceNow)))
            if third.big != "Arr", !third.big.isEmpty {
                return "then \(next.big) · \(third.big) min"
            }
        }
        return "then \(next.big) min"
    }

    /// " · 60 m away" appended after the stop code, or empty when location
    /// is unknown.
    private var stopDistanceSuffix: String {
        guard let here = loc.location, let stop = ds.stopByCode[stopCode] else { return "" }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return " · \(fmtDistance(Int(d.rounded()))) away"
    }

    // MARK: Alerts (notify + Live Activity)

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
            HStack(spacing: 10) {
                Image(systemName: on ? "bell.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(on ? "Alert on — tap to cancel" : "Notify me before it arrives")
                    .font(t.sans(15, weight: .bold))
            }
            .foregroundStyle(on ? t.onAccent : t.contrastFg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.contrast), in: Capsule())
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
                    Image(systemName: liveOn ? "stop.fill" : "clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(liveOn ? t.onAccent : t.dim)
                        .frame(width: 40, height: 40)
                        .background(liveOn ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.surface),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(liveOn ? "Stop Live Activity" : "Start Live Activity")
                            .font(t.sans(14, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(liveOn ? "Bus \(svc) is on your lock screen"
                                    : "Follow on your lock screen")
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

            if !timelineStops.isEmpty {
                Text("Tap a stop to set an arrival alert.")
                    .font(t.sans(13)).foregroundStyle(t.dim)
                RouteTimeline(t: t, svc: svc, stops: timelineStops, alightId: $alightId)
                    .onChange(of: alightId) { _, new in scheduleAlight(stopCode: new) }
            }
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
            // Other stops on the journey — faint dots, so the primary markers
            // stay the focus.
            if let r = route {
                ForEach(journeySegment(r).filter { $0.code != stopCode }, id: \.code) { rs in
                    Annotation(rs.name,
                               coordinate: CLLocationCoordinate2D(
                                latitude: rs.lat, longitude: rs.lon)) {
                        Circle().fill(t.dim.opacity(0.5)).frame(width: 6, height: 6)
                    }
                }
            }
            // The bus — always shown, always a confident solid pin (the map
            // never advertises that a position is estimated). The tier only
            // survives in the accessibility label, for screen-reader honesty.
            if let p = plot, let d = displayCoord {
                Annotation("Bus \(svc)", coordinate: d, anchor: .center) {
                    MapBusMarker(t: t, svc: svc)
                        .accessibilityLabel("Bus \(svc), \(positionA11y(p.tier))")
                }
            }
            // You — a blue person marker, unmistakably distinct from the green
            // stop pin.
            if let here = loc.location {
                Annotation("You", coordinate: here.coordinate, anchor: .center) {
                    MapUserMarker().accessibilityLabel("Your location")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: ds.stopByCode[stopCode]) { _, stop in
            guard let s = stop, !didCenterOnStop else { return }
            centerOnStop(s)
        }
    }

    private func positionA11y(_ tier: BusTier) -> String {
        switch tier {
        case .live:      return "live position"
        case .recent:    return "last-known position"
        case .estimated: return "estimated position, en route"
        }
    }

    // MARK: Bus-position resolution (live → recent → estimated) + glide

    /// Recompute the bus's plotted position. Called on appear, on data
    /// changes, and on every ticker beat (so the estimate creeps toward the
    /// stop and the recency age advances).
    private func recomputePlot() {
        let now = Date()

        // 1) Real GPS fix this poll → live. Remember it for the recent tier.
        if let s = liveService(), let lat = s.busLat, let lon = s.busLon {
            let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            lastFix = (c, now)
            setTarget(BusPlot(coord: c, tier: .live, ageSec: 0))
            return
        }

        // 2) Had a fix recently (< 150s) → keep it, dimmed, labelled "last seen".
        if let f = lastFix, now.timeIntervalSince(f.at) < 150 {
            setTarget(BusPlot(coord: f.coord, tier: .recent,
                              ageSec: Int(now.timeIntervalSince(f.at))))
            return
        }

        // 3) No usable fix → estimate the position from route geometry + ETA.
        if let c = estimatedCoord() {
            setTarget(BusPlot(coord: c, tier: .estimated, ageSec: 0))
            return
        }

        // 4) Nothing to go on (route not loaded / no arrival).
        setTarget(nil)
    }

    /// Estimate where the bus is by walking back up the route from your stop
    /// by ETA-worth of travel (≈90s/stop), interpolating between the two
    /// bracketing stops. Decrements the ETA by time since the last refresh so
    /// the pin creeps forward smoothly between LTA polls.
    private func estimatedCoord() -> CLLocationCoordinate2D? {
        guard let r = route, !r.stops.isEmpty, let s = liveService() else { return nil }
        let you = min(max(r.youIndex, 0), r.stops.count - 1)
        guard you > 0 else {
            return CLLocationCoordinate2D(latitude: r.stops[you].lat, longitude: r.stops[you].lon)
        }
        let elapsed = ds.lastRefresh(stopCode).map { Date().timeIntervalSince($0) } ?? 0
        let eta = max(0, Double(s.etaSec) - elapsed)
        let perStop = 90.0
        let back = min(Double(you), eta / perStop)   // stops upstream of you
        let idxF = Double(you) - back                 // fractional index along the route
        let lo = max(0, Int(floor(idxF)))
        let hi = min(lo + 1, you)
        let frac = idxF - Double(lo)
        let a = r.stops[lo], b = r.stops[hi]
        return CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * frac,
            longitude: a.lon + (b.lon - a.lon) * frac)
    }

    /// Move the plotted pin toward a new target. Glides (animates) when the
    /// pin is already on-screen; the first placement snaps. Skips no-op
    /// updates so we don't animate a stationary pin every tick.
    private func setTarget(_ p: BusPlot?) {
        guard let p else {
            if plot != nil { plot = nil; displayCoord = nil }
            return
        }
        let moved = displayCoord.map {
            abs($0.latitude - p.coord.latitude) > 1e-7 ||
            abs($0.longitude - p.coord.longitude) > 1e-7
        } ?? true
        plot = p
        if displayCoord == nil {
            displayCoord = p.coord
            frameSceneIfNeeded()
        } else if moved {
            withAnimation(.linear(duration: 1.5)) { displayCoord = p.coord }
        }
    }

    // MARK: Camera

    /// On first plot, frame the camera to fit both the bus and the stop (with
    /// padding) so the tether is fully visible. Runs once; the user's
    /// recenter button opts out of further auto-framing.
    private func frameSceneIfNeeded() {
        guard !didAutoFrame,
              let stop = ds.stopByCode[stopCode],
              let d = displayCoord else { return }
        didAutoFrame = true
        let lats = [stop.Latitude, d.latitude]
        let lons = [stop.Longitude, d.longitude]
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (lats.max()! - lats.min()!) * 1.8),
            longitudeDelta: max(0.005, (lons.max()! - lons.min()!) * 1.8))
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
        didCenterOnStop = true
    }

    // MARK: Data helpers

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
            await MainActor.run { self.route = r; recomputePlot() }
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

/// Stop marker — a green teardrop pin carrying a mappin glyph.
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
/// confused with the green stop pin.
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

/// The bus — a capsule carrying a bus glyph + service number, styled by
/// position tier so its certainty reads at a glance and is never disguised:
///   • live      — solid dark capsule (exact GPS)
///   • recent    — dark capsule dimmed (last-known, signal dropped)
///   • estimated — light capsule, dashed border, "≈" prefix (derived position)
struct MapBusMarker: View {
    let t: Theme
    let svc: String
    var tier: BusTier = .live

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bus.fill").font(.system(size: 12, weight: .bold))
            Text(tier == .estimated ? "≈ \(svc)" : svc)
                .font(t.mono(13, weight: .bold))
        }
        .foregroundStyle(tier == .estimated ? t.fg : t.contrastFg)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(capsuleFill, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                tier == .estimated ? t.fg.opacity(0.55) : .white,
                style: StrokeStyle(lineWidth: 2,
                                   dash: tier == .estimated ? [3, 3] : []))
        )
        .opacity(tier == .recent ? 0.6 : 1)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var capsuleFill: AnyShapeStyle {
        tier == .estimated ? AnyShapeStyle(t.surface) : AnyShapeStyle(t.contrast)
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
