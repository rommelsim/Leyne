// SoftBusView — Leyne 3.0 bus tracking view.
// A normal vertical scroll page: top bar → title block → contained map card
// with a live-position callout → route progress → alerts (notify + Live Activity).
//
// The map is a contained card (~300 pt tall), not a full-bleed backdrop.
// The live-position callout on the card shows the bus's prev/next stop and
// stops-remaining + distance, replacing the old approachingCard.
//
// Honesty tiers (position confidence) are preserved; the "~" whisper cue
// surfaces on the title when the fix is estimated or aged.

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
    /// When true the route timeline shows the ENTIRE route (opened from a bus
    /// search — no "your stop" context). Matches Android's `fullRoute` flag.
    var fullRoute: Bool = false
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void

    @State private var alightId: String? = nil
    @State private var showSave = false
    @State private var saveSel = 1
    @State private var serviceRouteData: ServiceRoute?
    @State private var selectedDirIndex: Int = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var didCenterOnStop = false
    @StateObject private var loc = LocationManager.shared

    // Bus-position plotting state.
    @State private var plot: BusPlot?                       // current tier + target
    @State private var displayCoord: CLLocationCoordinate2D?  // where the pin is drawn
    @State private var lastFix: (coord: CLLocationCoordinate2D, at: Date)?
    @State private var didAutoFrame = false

    /// Drives the glide/creep + recency aging.
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// The currently-selected direction, or nil while the route is loading.
    private var currentDirection: RouteDirection? {
        guard let sr = serviceRouteData,
              selectedDirIndex < sr.directions.count else { return nil }
        return sr.directions[selectedDirIndex]
    }

    /// A `RouteInfo` view over the selected direction, for map + estimation helpers.
    private var route: RouteInfo? {
        guard let dir = currentDirection else { return nil }
        return RouteInfo(stops: dir.stops, youIndex: dir.youIndex,
                         busIndex: nil, busCoord: nil)
    }

    private var t: Theme { m.t }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    /// This service is a favourite — either anywhere or at this stop.
    private var serviceSaved: Bool {
        m.isFavService(no: svc, stop: nil) || m.isFavService(no: svc, stop: stopCode)
    }

    /// Stop-level feed freshness.
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }

    /// Confidence for the tracked service's *arrival time*.
    private var confidence: ArrivalConfidence {
        guard let s = liveService() else { return .none }
        return ArrivalConfidence.of(monitored: s.monitored, feed: feed)
    }

    /// What the status pill shows. Timely-first.
    private var pillConfidence: ArrivalConfidence {
        confidence == .none ? .none : .live
    }

    /// Whether to show the "~" whisper cue.
    private var showWhisper: Bool {
        guard confidence != .none else { return false }
        return confidence != .live || plot?.tier != .live
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                titleBlock
                mapCard
                routeProgressSection
                alertsSection
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            ds.ensureArrivals(stop: stopCode)
            loadRoute()
            if let s = ds.stopByCode[stopCode] { centerOnStop(s) }
            recomputePlot()
        }
        .onReceive(ticker) { _ in recomputePlot() }
        .onChange(of: serviceRouteData) { _, _ in recomputePlot() }
        .onChange(of: selectedDirIndex) { _, _ in recomputePlot() }
        .onChange(of: ds.arrivals[stopCode]) { _, _ in recomputePlot() }
        .sheet(isPresented: $showSave) {
            SaveSheet(
                t: t,
                title: "Save this service",
                subtitle: "Choose how you want to save it.",
                options: [
                    SaveOption(icon: "bus", title: "Save service",
                               subtitle: "See next arrival for Bus \(svc) anywhere"),
                    SaveOption(icon: "mappin.and.ellipse", title: "Save Bus \(svc) at this stop",
                               subtitle: "Quick access from Favourites here"),
                ],
                selection: $saveSel
            ) { applyServiceSave() }
            .presentationDetents([.height(400)])
        }
    }

    private func applyServiceSave() {
        showSave = false
        let stop: String? = saveSel == 0 ? nil : stopCode
        if !m.isFavService(no: svc, stop: stop) { m.toggleFavService(no: svc, stop: stop) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Back
            Button {
                fb.select(); onBack()
            } label: {
                circleButton("chevron.left", size: 17)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(ds.stopName(stopCode))")

            Spacer(minLength: 0)

            // Share
            Button {
                fb.select()
                shareSheet()
            } label: {
                circleButton("square.and.arrow.up", size: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share Bus \(svc)")

            // More (star / save — "..." menu)
            Menu {
                Button {
                    saveSel = m.isFavService(no: svc, stop: nil) ? 0 : 1
                    showSave = true
                } label: {
                    Label(serviceSaved ? "Edit favourite" : "Save Bus \(svc)",
                          systemImage: serviceSaved ? "star.fill" : "star")
                }
            } label: {
                circleButton("ellipsis", size: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
        }
    }

    /// Share the bus service as a deep link / plain text.
    private func shareSheet() {
        let text = "Bus \(svc) from Stop \(stopCode) — tracked on Leyne"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    /// Uniform circular button label.
    private func circleButton(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 40, height: 40)
            .background(t.surface, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }

    // MARK: Title block

    private var titleBlock: some View {
        let service = liveService()
        let dest = service?.dest ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            // "Bus 186" — large bold
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Bus \(svc)")
                    .font(t.sans(28, weight: .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showWhisper {
                    Text("~")
                        .font(t.mono(14))
                        .foregroundStyle(t.faint)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
            }
            // "Towards …" + LIVE pill
            HStack(spacing: 6) {
                Text(dest.isEmpty ? "Loading route…" : "Towards \(dest)")
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if pillConfidence == .live {
                    HStack(spacing: 4) {
                        Circle().fill(t.soon).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(t.mono(10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(t.soon)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live tracking")
                }
            }
        }
    }

    // MARK: Map card

    private var mapCard: some View {
        ZStack(alignment: .bottomLeading) {
            // The map itself — clipped to card bounds.
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
                // Other stops on the journey — faint dots.
                if let r = route {
                    ForEach(journeySegment(r).filter { $0.code != stopCode }, id: \.code) { rs in
                        Annotation(rs.name,
                                   coordinate: CLLocationCoordinate2D(
                                    latitude: rs.lat, longitude: rs.lon)) {
                            Circle().fill(t.dim.opacity(0.5)).frame(width: 6, height: 6)
                        }
                    }
                }
                // The bus — solid pin; tier in accessibility label only.
                if let p = plot, let d = displayCoord {
                    Annotation("Bus \(svc)", coordinate: d, anchor: .center) {
                        MapBusMarker(t: t, svc: svc)
                            .accessibilityLabel("Bus \(svc), \(positionA11y(p.tier))")
                    }
                }
                // You — blue person marker.
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
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Live-position callout — bottom-leading, only when we have data.
            if let callout = liveCalloutInfo {
                busCallout(callout)
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
            }

            // Recenter button — bottom-trailing.
            Button {
                fb.select()
                didAutoFrame = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    camera = .userLocation(fallback: .automatic)
                    didCenterOnStop = false
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center on my location")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    // MARK: Live-position callout

    /// Everything the callout needs, or nil when we can't show it meaningfully.
    private struct CalloutInfo {
        let prevStopName: String
        let nextStopName: String
        let stopsAway: Int
        let distanceMeters: Int?   // nil when bus coord is unavailable
    }

    private var liveCalloutInfo: CalloutInfo? {
        guard let dir = currentDirection, !dir.stops.isEmpty,
              let busIdx = estimatedBusIndex else { return nil }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        guard busIdx <= youIdx else { return nil }

        // prev = the stop the bus is at / just passed
        let prevStop = dir.stops[busIdx]
        // next = the following stop, preferring the user's stop when adjacent
        let nextIdx = min(busIdx + 1, dir.stops.count - 1)
        let nextStop = dir.stops[nextIdx]
        let stopsAway = max(0, youIdx - busIdx)

        // Distance from the bus's display coord to the next stop's coord.
        var distMeters: Int? = nil
        if let busCoord = displayCoord {
            let d = haversine(busCoord.latitude, busCoord.longitude,
                              nextStop.lat, nextStop.lon)
            distMeters = Int(d.rounded())
        }
        return CalloutInfo(prevStopName: prevStop.name,
                           nextStopName: nextStop.name,
                           stopsAway: stopsAway,
                           distanceMeters: distMeters)
    }

    @ViewBuilder
    private func busCallout(_ info: CalloutInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: between X and Y
            Text("Between \(info.prevStopName) and \(info.nextStopName)")
                .font(t.sans(12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Line 2: N stops away · dist m
            HStack(spacing: 4) {
                Text("\(info.stopsAway)")
                    .font(t.mono(12, weight: .bold))
                    .foregroundStyle(t.soon)
                + Text(" stop\(info.stopsAway == 1 ? "" : "s") away")
                    .font(t.sans(12))
                    .foregroundStyle(.white.opacity(0.8))
                if let dist = info.distanceMeters {
                    Text("·")
                        .font(t.sans(12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(fmtDistance(dist))")
                        .font(t.mono(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Bus between \(info.prevStopName) and \(info.nextStopName), " +
            "\(info.stopsAway) stop\(info.stopsAway == 1 ? "" : "s") away" +
            (info.distanceMeters.map { ", \(fmtDistance($0))" } ?? "")
        )
    }

    // MARK: Route progress section

    private var routeProgressSection: some View {
        let computed = timelineStops
        let progress = progressNodes
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            if !computed.isEmpty || !progress.isEmpty {
                Text("Route progress")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.dim)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Compact horizontal progress bar
                if !progress.isEmpty {
                    RouteProgressBar(t: t, nodes: progress, remaining: stopsRemaining)
                        .padding(.top, 2)
                }

                // Direction toggle — only when 2+ directions
                if let sr = serviceRouteData, sr.directions.count >= 2 {
                    directionPicker(sr)
                }

                // Full route timeline
                if !computed.isEmpty {
                    RouteTimeline(t: t, svc: svc, stops: computed, alightId: $alightId)
                        .onChange(of: alightId) { _, new in scheduleAlight(stopCode: new) }
                }

                // Freshness line
                HStack(spacing: 5) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(feed == .live ? t.soon : t.dim)
                        .accessibilityHidden(true)
                    Text(feedFreshnessLabel)
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
        }
    }

    /// Segmented direction picker.
    @ViewBuilder
    private func directionPicker(_ sr: ServiceRoute) -> some View {
        Picker("Direction", selection: $selectedDirIndex) {
            ForEach(sr.directions.indices, id: \.self) { i in
                let dest = sr.directions[i].destinationName
                Text("To \(dest.isEmpty ? "Direction \(i + 1)" : dest)")
                    .tag(i)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Route direction")
    }

    /// Short freshness label.
    private var feedFreshnessLabel: String {
        guard let last = ds.lastRefresh(stopCode) else { return "Waiting for data" }
        let age = Int(Date().timeIntervalSince(last))
        if age < 5  { return "Updated now" }
        if age < 60 { return "Updated \(age)s ago" }
        let m = age / 60
        return "Updated \(m) min ago"
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

    // MARK: Bus-position resolution (live → recent → estimated) + glide

    private func recomputePlot() {
        let now = Date()

        // 1) Real GPS fix this poll → live.
        if let s = liveService(), let lat = s.busLat, let lon = s.busLon {
            let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            lastFix = (c, now)
            setTarget(BusPlot(coord: c, tier: .live, ageSec: 0))
            return
        }

        // 2) Had a fix recently (< 150s) → keep it, dimmed.
        if let f = lastFix, now.timeIntervalSince(f.at) < 150 {
            setTarget(BusPlot(coord: f.coord, tier: .recent,
                              ageSec: Int(now.timeIntervalSince(f.at))))
            return
        }

        // 3) No usable fix → estimate from route geometry + ETA.
        if let c = estimatedCoord() {
            setTarget(BusPlot(coord: c, tier: .estimated, ageSec: 0))
            return
        }

        // 4) Nothing to go on.
        setTarget(nil)
    }

    private func estimatedCoord() -> CLLocationCoordinate2D? {
        guard let r = route, !r.stops.isEmpty, let s = liveService() else { return nil }
        let you = min(max(r.youIndex, 0), r.stops.count - 1)
        guard you > 0 else {
            return CLLocationCoordinate2D(latitude: r.stops[you].lat, longitude: r.stops[you].lon)
        }
        let elapsed = ds.lastRefresh(stopCode).map { Date().timeIntervalSince($0) } ?? 0
        let eta = max(0, Double(s.etaSec) - elapsed)
        let perStop = 90.0
        let back = min(Double(you), eta / perStop)
        let idxF = Double(you) - back
        let lo = max(0, Int(floor(idxF)))
        let hi = min(lo + 1, you)
        let frac = idxF - Double(lo)
        let a = r.stops[lo], b = r.stops[hi]
        return CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * frac,
            longitude: a.lon + (b.lon - a.lon) * frac)
    }

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

    private var estimatedBusIndex: Int? {
        guard !fullRoute, let dir = currentDirection, dir.anchorPresent,
              !dir.stops.isEmpty, let s = liveService() else { return nil }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        guard you > 0 else { return 0 }
        let elapsed = ds.lastRefresh(stopCode).map { Date().timeIntervalSince($0) } ?? 0
        let eta = max(0, Double(s.etaSec) - elapsed)
        let back = min(Double(you), eta / 90.0)
        return min(max(0, Int((Double(you) - back).rounded())), you)
    }

    private var stopsRemaining: Int? {
        guard let dir = currentDirection, let busIdx = estimatedBusIndex else { return nil }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        return max(0, youIdx - busIdx)
    }

    private var progressNodes: [RouteStop] {
        guard let dir = currentDirection, let busIdx = estimatedBusIndex else { return [] }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        guard youIdx >= busIdx, youIdx < dir.stops.count else { return [] }
        let lo = max(0, busIdx - 2)
        var idxs = Array(lo...youIdx)
        if idxs.count > 5 { idxs = Array(lo...busIdx) + [youIdx] }
        return idxs.map { i in
            let st: RouteStopState = i < busIdx ? .past
                : (i == busIdx ? .here : (i == youIdx ? .board : .next))
            return RouteStop(id: dir.stops[i].code, name: dir.stops[i].name, state: st)
        }
    }

    private func etaClock(forIndex i: Int, busIdx: Int?, youIdx: Int, youEtaSec: Int) -> String? {
        guard let b = busIdx, youIdx > b, i >= b else { return nil }
        let secs: Double = i <= youIdx
            ? Double(youEtaSec) * Double(i - b) / Double(youIdx - b)
            : Double(youEtaSec) + Double(i - youIdx) * 90
        let clock = fmtClock(Date().addingTimeInterval(secs), use24h: m.use24h)
        return i == b ? clock : "ETA \(clock)"
    }

    private var timelineStops: [RouteStop] {
        guard let r = route, let dir = currentDirection else { return [] }
        let showFull = fullRoute || !dir.anchorPresent
        let segment = showFull ? r.stops : journeySegment(r)
        let busSeq = estimatedBusIndex
        let youSeq = r.youIndex
        let youEta = liveService()?.etaSec ?? 0
        let canMarkBoard = !fullRoute && dir.anchorPresent
        return segment.map { stop -> RouteStop in
            let idx = r.stops.firstIndex(where: { $0.code == stop.code }) ?? -1
            let state: RouteStopState
            if let b = busSeq, idx == b { state = .here }
            else if canMarkBoard && idx == youSeq { state = .board }
            else if idx < (busSeq ?? -1) { state = .past }
            else { state = .next }
            let time = etaClock(forIndex: idx, busIdx: busSeq, youIdx: youSeq, youEtaSec: youEta)
            return RouteStop(id: stop.code, name: stop.name, state: state, time: time)
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
            let sr = await ds.serviceRoute(service: svc, stopCode: stopCode)
            await MainActor.run {
                self.serviceRouteData = sr
                self.selectedDirIndex = sr?.initialIndex ?? 0
                recomputePlot()
            }
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

    private func positionA11y(_ tier: BusTier) -> String {
        switch tier {
        case .live:      return "live position"
        case .recent:    return "last-known position"
        case .estimated: return "estimated position, en route"
        }
    }
}

// MARK: - Map markers (shared icon language with the Android map)

/// Stop marker — a green teardrop pin carrying a mappin glyph.
struct MapStopMarker: View {
    let t: Theme
    var body: some View {
        Image(systemName: "mappin")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(t.contrastFg)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(t.soon).overlay(Circle().stroke(.white, lineWidth: 2))
            )
            .background(
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(t.soon)
                    .offset(y: 12)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// "You" — the user's live position.
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

/// The bus marker — styled by position tier for honesty at a glance.
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

/// Map legend pill.
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
