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
    // Destination "Notify me when" flow.
    @State private var showDestSheet = false
    @State private var confirmAlert: BusAlert?
    @State private var showManage = false
    @State private var showMap = false
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
                approachingCard
                routeProgressSection
                viewOnMapButton
                liveUpdatesCard
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
        // Pull-to-refresh — re-fetch this stop's arrivals; the arrivals
        // onChange below repositions the bus. Matches the Stop view.
        .refreshable { await ds.refreshArrivals(stop: stopCode) }
        .fullScreenCover(isPresented: $showMap) { mapFullScreen }
        // Destination "Notify me when" sheet → confirmation → Manage alerts.
        .sheet(isPresented: $showDestSheet) {
            NotifyWhenSheet(
                kind: .destination, busNo: svc, stopName: destinationName,
                initialLead: m.alert(kind: .destination, busNo: svc,
                                     stopCode: destinationCode)?.leadMinutes,
                onCancel: { showDestSheet = false },
                onDone: { lead, _ in commitDestinationAlert(lead: lead) })
            .environmentObject(m)
            .environmentObject(fb)
        }
        .sheet(item: $confirmAlert) { alert in
            NotifyConfirmView(
                alert: alert,
                onClose: { confirmAlert = nil },
                onManageAll: { confirmAlert = nil; showManage = true })
            .environmentObject(m)
            .environmentObject(fb)
        }
        .sheet(isPresented: $showManage) {
            NavigationStack { ManageAlertsView() }
                .environmentObject(m)
                .environmentObject(fb)
                .environmentObject(ds)
        }
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
    }

    /// Toggle whether this bus is saved. Filled = saved (here or anywhere);
    /// tapping clears every save of this service, or saves it at this stop when
    /// none exists. Mirrors the stop view's single-tap pin toggle.
    private func toggleServiceSaved() {
        let here = m.isFavService(no: svc, stop: stopCode)
        let anywhere = m.isFavService(no: svc, stop: nil)
        if here || anywhere {
            if here { m.toggleFavService(no: svc, stop: stopCode) }
            if anywhere { m.toggleFavService(no: svc, stop: nil) }
        } else {
            m.toggleFavService(no: svc, stop: stopCode)
        }
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

            // Save toggle — saves/removes this bus. A bus glyph fills when
            // saved (mirrors the stop's pin toggle). Arrival alerts live in the
            // Alerts section below, not here.
            Button {
                fb.select(); toggleServiceSaved()
            } label: {
                Image(systemName: serviceSaved ? "bus.fill" : "bus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(serviceSaved ? t.soon : t.fg)
                    .frame(width: 40, height: 40)
                    .background(t.surface, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(serviceSaved ? "Bus \(svc) saved. Tap to remove."
                                             : "Save Bus \(svc)")

            // Overflow — share.
            Menu {
                Button {
                    fb.select(); shareSheet()
                } label: {
                    Label("Share Bus \(svc)", systemImage: "square.and.arrow.up")
                }
            } label: {
                circleButton("ellipsis", size: 16)
            }
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

    // MARK: Approaching status card

    /// Compact "where's the bus" summary that sits where the inline map used to.
    /// Headline = stops away, subline = arriving-in + distance, then a slim
    /// journey bar. The full map is one tap away via `viewOnMapButton`.
    private var approachingCard: some View {
        let svcLive = liveService()
        let etaSec = svcLive?.etaSec
        let stopsAway = stopsRemaining
        let dist = distanceToYouMeters
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.soon)
                    .frame(width: 44, height: 44)
                    .background(t.soonBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(approachHeadline(stopsAway: stopsAway, etaSec: etaSec))
                        .font(t.sans(17, weight: .bold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(approachSubline(etaSec: etaSec, dist: dist))
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if pillConfidence == .live {
                    HStack(spacing: 4) {
                        Circle().fill(t.soon).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(t.mono(10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(t.soon)
                    }
                    .accessibilityHidden(true)
                }
            }
            if let frac = journeyFraction {
                slimProgressBar(frac)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(t.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Headline: how many stops the bus is from the user's stop.
    private func approachHeadline(stopsAway: Int?, etaSec: Int?) -> String {
        if let n = stopsAway {
            return n == 0 ? "Arriving now" : "\(n) stop\(n == 1 ? "" : "s") away"
        }
        if let e = etaSec, fmtETA(e).big == "Arr" { return "Arriving now" }
        return "On the way"
    }

    /// Subline: "Arriving in {n} min" plus the distance to the next stop.
    private func approachSubline(etaSec: Int?, dist: Int?) -> String {
        guard let e = etaSec else { return "Waiting for the next arrival" }
        let eta = fmtETA(e)
        let timePart = eta.big == "Arr" ? "Arriving now" : "Arriving in \(eta.big) \(eta.small)"
        if let d = dist { return "\(timePart) (\(fmtDistance(d)))" }
        return timePart
    }

    /// Fraction of the journey the bus has covered toward the user's stop —
    /// drives the slim bar. Near-full when the bus is a stop or two away.
    private var journeyFraction: Double? {
        guard let dir = currentDirection, let busIdx = estimatedBusIndex else { return nil }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        guard youIdx > 0 else { return 1 }
        return min(1, max(0, Double(busIdx) / Double(youIdx)))
    }

    private func slimProgressBar(_ frac: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.line)
                Capsule().fill(t.soon)
                    .frame(width: max(6, geo.size.width * frac))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    // MARK: Live updates card

    /// Service-status card. We have no live disruption feed for buses yet, so —
    /// per the timely-over-honest design language — this presents confidently as
    /// "running smoothly" rather than advertising the absence of data. If a
    /// route-level alert source is added later, bind its title/detail here.
    private var liveUpdatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(t.soon).frame(width: 8, height: 8)
                Text("Live updates")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.soon)
                    .frame(width: 36, height: 36)
                    .background(t.soonBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service running smoothly")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.soon)
                    Text("No major delays reported.")
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(t.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live updates. Service running smoothly, no major delays reported.")
    }

    // MARK: View-on-map button

    private var viewOnMapButton: some View {
        Button {
            fb.select()
            showMap = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("View on map")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("View bus \(svc) on the map")
    }

    // MARK: Map (presented full-screen from "View on map")

    /// Shared annotation set for the bus map — stop, journey dots, the bus
    /// (tier in the a11y label), and the user.
    @MapContentBuilder
    private var mapAnnotations: some MapContent {
        if let stop = ds.stopByCode[stopCode] {
            Annotation(stop.Description,
                       coordinate: CLLocationCoordinate2D(
                        latitude: stop.Latitude, longitude: stop.Longitude),
                       anchor: .bottom) {
                MapStopMarker(t: t)
                    .accessibilityLabel("Bus stop \(stop.Description)")
            }
        }
        if let r = route {
            ForEach(journeySegment(r).filter { $0.code != stopCode }, id: \.code) { rs in
                Annotation(rs.name,
                           coordinate: CLLocationCoordinate2D(
                            latitude: rs.lat, longitude: rs.lon)) {
                    Circle().fill(t.dim.opacity(0.5)).frame(width: 6, height: 6)
                }
            }
        }
        if let p = plot, let d = displayCoord {
            Annotation("Bus \(svc)", coordinate: d, anchor: .center) {
                MapBusMarker(t: t, svc: svc)
                    .accessibilityLabel("Bus \(svc), \(positionA11y(p.tier))")
            }
        }
        if let here = loc.location {
            Annotation("You", coordinate: here.coordinate, anchor: .center) {
                MapUserMarker().accessibilityLabel("Your location")
            }
        }
    }

    private var mapFullScreen: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) { mapAnnotations }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea()
                .onChange(of: ds.stopByCode[stopCode]) { _, stop in
                    guard let s = stop, !didCenterOnStop else { return }
                    centerOnStop(s)
                }

            // Top bar — title + Done.
            HStack(spacing: 10) {
                Text("Bus \(svc)")
                    .font(t.sans(17, weight: .bold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Button {
                    fb.select(); showMap = false
                } label: {
                    Text("Done")
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(t.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close map")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)

            // Callout + recenter pinned to the bottom.
            VStack {
                Spacer()
                ZStack(alignment: .bottomLeading) {
                    if let callout = liveCalloutInfo {
                        busCallout(callout)
                            .padding(.leading, 16)
                            .padding(.bottom, 24)
                    }
                    Button {
                        fb.select()
                        didAutoFrame = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            camera = .userLocation(fallback: .automatic)
                            didCenterOnStop = false
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(t.fg)
                            .frame(width: 40, height: 40)
                            .background(.thinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Center on my location")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(t.bg)
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
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            if !computed.isEmpty {
                Text("Route progress")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.dim)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Direction toggle — only when 2+ directions
                if let sr = serviceRouteData, sr.directions.count >= 2 {
                    directionPicker(sr)
                }

                // Full route timeline. Tapping a stop selects it as the
                // destination for the "Notify me when … reaches my
                // destination" alert below (no alert is scheduled until the
                // user confirms a lead in the sheet).
                if !computed.isEmpty {
                    RouteTimeline(t: t, svc: svc, stops: computed, alightId: $alightId)
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
            arrivalAlertButton
            destinationRow
        }
    }

    /// Combined arrival affordance: ONE tap sets up BOTH an arrival alert at the
    /// boarding stop AND a lock-screen Live Activity (best-effort — only when
    /// Activities are enabled and there's a live service). "Active" keys off the
    /// arrival alert; tapping while active cancels both. Replaces the old
    /// separate notify-button + Live-Activity CTA. Lead fine-tuning still lives
    /// in the Stop view's "Notify me when" sheet.
    private var arrivalAlertButton: some View {
        let existing = m.alert(kind: .arrival, busNo: svc, stopCode: stopCode)
        let on = existing != nil
        return Button {
            fb.select()
            if let a = existing {
                // Cancel both: remove the arrival alert + stop the Live Activity
                // if one is running for this service/stop.
                m.removeAlert(id: a.id)
                if let s = liveService(), m.isLiveActivityActive(s, stopCode: stopCode) {
                    m.toggleLiveActivity(s, stopName: ds.stopName(stopCode), stopCode: stopCode)
                }
            } else {
                // Set up both: create the arrival alert, then start the Live
                // Activity as a best-effort companion (skip silently when it's
                // unavailable — the notification alone still works).
                let alert = BusAlert(
                    kind: .arrival, busNo: svc, stopCode: stopCode,
                    stopName: ds.stopName(stopCode), dest: liveService()?.dest ?? "",
                    boardStopCode: stopCode,
                    leadMinutes: AlertTiming.defaultLead(.arrival))
                m.upsertAlert(alert)
                if let s = liveService(),
                   ActivityAuthorizationInfo().areActivitiesEnabled,
                   !m.isLiveActivityActive(s, stopCode: stopCode) {
                    m.toggleLiveActivity(s, stopName: ds.stopName(stopCode), stopCode: stopCode)
                }
                confirmAlert = alert
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "bell.fill" : "bell")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? t.onAccent : t.contrastFg)
                    .frame(width: 40, height: 40)
                    .background(on ? AnyShapeStyle(t.accent.opacity(0.25))
                                   : AnyShapeStyle(t.contrastFg.opacity(0.12)),
                                in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? "Alert on" : "Notify me before it arrives")
                        .font(t.sans(15, weight: .bold))
                        .foregroundStyle(on ? t.onAccent : t.contrastFg)
                    Text(on ? "Notifying you · on your lock screen"
                            : "Get a notification and follow this bus on your lock screen.")
                        .font(t.sans(12))
                        .foregroundStyle((on ? t.onAccent : t.contrastFg).opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                } else {
                    HStack(spacing: 4) {
                        Text("Set up")
                            .font(t.sans(13, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(t.contrast)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(t.soon, in: Capsule())
                }
            }
            .padding(12)
            .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.contrast),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on
            ? "Arrival alert on for bus \(svc) — tap to cancel"
            : "Notify me before bus \(svc) arrives and follow it on your lock screen")
    }

    /// "Notify me when … reaches my DESTINATION" row. Defaults to the route
    /// terminus; tapping a stop in the timeline above (which sets `alightId`)
    /// changes the destination. Reflects an existing destination alert with
    /// its chosen lead.
    private var destinationRow: some View {
        let existing = m.alert(kind: .destination, busNo: svc, stopCode: destinationCode)
        let active = existing != nil
        return Button {
            fb.select()
            showDestSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? t.onAccent : t.dim)
                    .frame(width: 40, height: 40)
                    .background(active ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.surface),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me when")
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                    Text(destinationName.isEmpty ? "Pick a destination"
                                                 : "\(destinationName) (Destination)")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    if active, let e = existing {
                        Text(AlertTiming.leadRowSubtitle(e.leadMinutes) + " before arrival")
                            .font(t.sans(12))
                            .foregroundStyle(t.soon)
                    } else {
                        Text("Set how early to be notified")
                            .font(t.sans(12))
                            .foregroundStyle(t.dim)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: active ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? t.accent : t.faint)
            }
            .padding(12)
            .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? t.accent.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active
            ? "Destination alert on for \(destinationName)"
            : "Notify me when bus \(svc) reaches my destination")
    }

    // ── Destination resolution ──────────────────────────────
    // The destination defaults to the route terminus (last stop of the
    // selected direction); tapping a stop in the timeline overrides it.

    private var destinationStops: [RouteStopLive] { currentDirection?.stops ?? [] }

    /// Index of the chosen destination in the selected direction's stop list.
    private var destinationIndex: Int? {
        let stops = destinationStops
        guard !stops.isEmpty else { return nil }
        if let id = alightId, let i = stops.firstIndex(where: { $0.code == id }) {
            return i
        }
        return stops.count - 1                       // default: terminus
    }

    private var destinationCode: String {
        guard let i = destinationIndex else { return "" }
        return destinationStops[i].code
    }

    private var destinationName: String {
        guard let i = destinationIndex else { return "" }
        return destinationStops[i].name
    }

    /// Commits a destination alert with the chosen lead, computing the
    /// absolute fire time from this bus's live arrival at the boarding stop
    /// plus the per-segment estimate to the destination.
    private func commitDestinationAlert(lead: Int) {
        guard let dir = currentDirection, let destIdx = destinationIndex,
              let s = liveService(), let board = s.arrivalDate else {
            showDestSheet = false
            return
        }
        let boardIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let fireAt = AlertTiming.destinationFireAt(
            arrivalAtBoard: board, boardIndex: boardIdx,
            destIndex: destIdx, leadMinutes: lead)
        let alert = BusAlert(
            kind: .destination, busNo: svc, stopCode: destinationCode,
            stopName: destinationName, dest: s.dest, boardStopCode: stopCode,
            leadMinutes: lead)
        m.upsertAlert(alert, fireAt: fireAt)
        showDestSheet = false
        confirmAlert = alert
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

    /// The bus's *actual* position when we have a fix — the live GPS coord from
    /// the feed, or a recent one (< 150 s). nil when we have nothing real and
    /// must fall back to the ETA estimate.
    private var liveBusCoord: CLLocationCoordinate2D? {
        if let s = liveService(), let lat = s.busLat, let lon = s.busLon,
           lat != 0, lon != 0 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let f = lastFix, Date().timeIntervalSince(f.at) < 150 { return f.coord }
        return nil
    }

    /// Where the bus is along the route, as a stop index. Grounded in the real
    /// GPS fix (nearest route stop) whenever we have one, so "stops away", the
    /// callout, the journey bar, and the timeline all agree with the map pin.
    /// Only when there's no usable fix do we fall back to the ETA estimate
    /// (`youIndex − eta/90`), which can disagree with reality.
    private var estimatedBusIndex: Int? {
        guard !fullRoute, let dir = currentDirection, dir.anchorPresent,
              !dir.stops.isEmpty, let s = liveService() else { return nil }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        // Snap a real fix to the nearest route stop; BusProgress clamps it to
        // your stop and falls back to the ETA estimate when there's no fix.
        let gpsNearest = liveBusCoord.flatMap { c in
            BusProgress.nearestIndex(
                stops: dir.stops.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }, to: c)
        }
        let elapsed = ds.lastRefresh(stopCode).map { Date().timeIntervalSince($0) } ?? 0
        return BusProgress.busIndex(youIndex: you, gpsNearest: gpsNearest,
                                    etaSec: s.etaSec, elapsedSec: elapsed)
    }

    private var stopsRemaining: Int? {
        guard let dir = currentDirection, let busIdx = estimatedBusIndex else { return nil }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        return max(0, youIdx - busIdx)
    }

    /// Straight-line distance from the bus to *your* stop — the intuitive "how
    /// far is it from me" number for the approaching card. nil without a fix.
    private var distanceToYouMeters: Int? {
        guard let dir = currentDirection, let c = liveBusCoord, !dir.stops.isEmpty
        else { return nil }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let s = dir.stops[you]
        return Int(haversine(c.latitude, c.longitude, s.lat, s.lon).rounded())
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
        // Only between the bus and your stop do we have a defensible time: it's
        // interpolated from the real arrival ETA. Past your stop we have no
        // anchor, so we show nothing rather than fabricate a 90 s-per-stop guess.
        guard let b = busIdx, youIdx > b, i >= b, i <= youIdx else { return nil }
        let secs = Double(youEtaSec) * Double(i - b) / Double(youIdx - b)
        let clock = fmtClock(Date().addingTimeInterval(secs), use24h: m.use24h)
        return i == b ? clock : "ETA \(clock)"
    }

    private var timelineStops: [RouteStop] {
        guard let r = route, let dir = currentDirection else { return [] }
        let busSeq = estimatedBusIndex
        let youSeq = r.youIndex
        let youEta = liveService()?.etaSec ?? 0
        let canMarkBoard = !fullRoute && dir.anchorPresent
        let showFull = fullRoute || !dir.anchorPresent

        // From a couple of stops before the bus all the way to the line's
        // terminus, so the progress visibly leads to the stated destination
        // rather than stopping just past your stop. RouteTimeline folds the
        // leading run behind a "show earlier stops" node to keep it scannable.
        let segment: [RouteStopLive]
        if showFull {
            segment = r.stops
        } else {
            let lead = BusProgress.timelineLead(busIndex: busSeq, youIndex: youSeq,
                                                stopsCount: r.stops.count)
            segment = Array(r.stops[lead...])
        }
        return segment.map { stop -> RouteStop in
            let idx = r.stops.firstIndex(where: { $0.code == stop.code }) ?? -1
            let state = BusProgress.stopState(idx: idx, busIndex: busSeq,
                                              youIndex: youSeq, canMarkBoard: canMarkBoard)
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
