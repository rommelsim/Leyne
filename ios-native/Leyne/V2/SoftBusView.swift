// SoftBusView — Leyne 3.0 bus tracking view.
// Vertical scroll page, ordered by what a commuter decides on first:
//   top bar → title → "when's it coming" hero → live tracking (compact route
//   strip "did I miss it?" + a small tap-to-expand map) → the next two buses →
//   route progress → first/last bus → alerts.
//
// The hero owns *this* arrival; the "If you miss this one" card owns the two
// after it (no 1st-bus duplication). The route strip surfaces the existing
// timeline data early so "is it coming toward me / how far" is answerable
// without scrolling; the geographic map is one tap away.
//
// Honesty tiers (position confidence) are preserved; the "~" whisper cue
// surfaces on the title when the fix is estimated or aged.

import SwiftUI
import MapKit

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
    @Environment(AppModel.self) var m: AppModel
    @EnvironmentObject var fb: Feedback
    @Environment(DataStore.self) var ds: DataStore

    let onBack: () -> Void

    @State private var showMap = false
    @State private var showRouteCard = false
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

    /// One-shot guard for the "~1 min away" gentle haptic. Re-arms once the ETA
    /// climbs back past ~75 s (the feed rolled to the next bus), so each
    /// incoming bus buzzes exactly once.
    @State private var didBuzzOneMin = false

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

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                topBar
                titleBlock
                heroCard
                liveModule
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                trackButton
            }
            .padding(.horizontal, 16)
            // Pushed full-screen (not a sheet) — the safe-area inset already
            // clears the status bar, so only a small breathing gap is needed
            // above the top bar. Matches SoftStopView's top inset.
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // No pull-to-refresh — the dashboard doesn't scroll. The ticker below
        // keeps this stop's arrivals fresh automatically while the view is open.
        // Map opens as a tall card (consistent with the route card); the inline
        // preview is a button, not a live map.
        .sheet(isPresented: $showMap) {
            mapFullScreen
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Full-route glass card, raised from the route strip.
        .sheet(isPresented: $showRouteCard) { routeCard }
        .onAppear {
            ds.ensureArrivals(stop: stopCode)
            loadRoute()
            if let s = ds.stopByCode[stopCode] { centerOnStop(s) }
            recomputePlot()
        }
        .onReceive(ticker) { _ in
            // Keep this stop's arrivals fresh while the view is open. The global
            // app tick only refreshes pinned + open-card stops, so a bus opened
            // at an un-pinned stop would otherwise freeze at its last fetch.
            // `ensureArrivals` self-throttles to the 25 s freshness window.
            ds.ensureArrivals(stop: stopCode)
            recomputePlot()
            buzzIfApproaching()
        }
        .onChange(of: serviceRouteData) { _, _ in recomputePlot() }
        .onChange(of: selectedDirIndex) { _, _ in recomputePlot() }
        .onChange(of: ds.arrivals[stopCode]) { _, _ in recomputePlot() }
    }

    /// Toggle whether this bus is saved. Filled = saved (here or anywhere);
    /// tapping clears every save of this service, or saves it at this stop when
    /// none exists. Mirrors the stop view's single-tap pin toggle. No
    /// confirmation overlay — the star icon's filled/accent state plus the tap
    /// haptic are the feedback.
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

            // Save — a set-once convenience, demoted from a labelled segment to a
            // quiet star icon. The emphasised action (Track) owns the bottom bar.
            Button {
                fb.select(); toggleServiceSaved()
            } label: {
                circleButton(serviceSaved ? "star.fill" : "star", size: 16,
                             tint: serviceSaved ? t.accent : t.fg)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: serviceSaved)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(serviceSaved
                ? "Bus \(svc) saved. Tap to remove."
                : "Save Bus \(svc)")

            // Overflow — Share only. Alert management lives in the Alerts tab.
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

    // MARK: Primary action — pinned Track CTA

    /// The single emphasised action on the bus view: arm or cancel the arrival
    /// track (lock-screen Live Activity + a nudge before the bus arrives).
    /// Pinned full-width at the bottom for thumb reach. Accent-filled as a call
    /// to action; tonal with an accent stroke once tracking (tap to stop).
    private var trackButton: some View {
        Button {
            toggleBoardingAlert()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: boardingAlertOn ? "bell.fill" : "bell")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(boardingAlertOn ? "Tracking — tap to stop" : "Track arrival")
                    .font(t.sans(16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(boardingAlertOn ? t.accent : t.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(boardingAlertOn ? t.accent.opacity(0.15) : t.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(boardingAlertOn ? t.accent.opacity(0.5) : Color.clear,
                            lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.18), value: boardingAlertOn)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(boardingAlertOn
            ? "Tracking bus \(svc). Tap to stop."
            : "Track bus \(svc) — get a Live Activity and a nudge before it arrives")
    }

    /// Share the bus service as a deep link / plain text.
    private func shareSheet() {
        let text = "Bus \(svc) from Stop \(stopCode) — tracked on SG Transit"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    /// Uniform circular button label. `tint` overrides the glyph colour (e.g.
    /// accent for the active saved-star state).
    private func circleButton(_ symbol: String, size: CGFloat,
                              tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint ?? t.fg)
            .frame(width: 44, height: 44)
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
            // First/last bus rides directly under the route line — top of the
            // screen for at-a-glance "have I missed the last bus?" visibility.
            firstLastFooter
                .padding(.top, 1)
        }
    }

    // MARK: Hero — ETA · stops-away · deck · crowd · next two (one glance card)

    /// The headline card: the arrival number a commuter actually decides on,
    /// the stops-away context, the deck type + crowd on the right, and the next
    /// two arrivals folded into a thin footer — every number in one place.
    private var heroCard: some View {
        let s = liveService()
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    heroETARow(s)
                    Text(approachContext(s))
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                if s != nil {
                    CrowdMeter(load: s?.load, t: t)
                }
            }
            if let s {
                Rectangle().fill(t.line).frame(height: 1)
                heroFooter(s)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(t.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(approachA11y(s))
    }

    /// Big arrival readout — minutes (mono) + unit, or "Arriving" / "No live arrival".
    @ViewBuilder
    private func heroETARow(_ s: Service?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let s {
                let eta = fmtETA(s.etaSec)
                if eta.big == "Arr" {
                    Text("Arriving")
                        .font(t.sans(30, weight: .bold))
                        .foregroundStyle(t.soon)
                } else {
                    Text(eta.big)
                        .font(t.mono(40, weight: .bold))
                        .foregroundStyle(t.fg)
                    Text(eta.small)
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
            } else {
                Text("No live arrival")
                    .font(t.sans(20, weight: .bold))
                    .foregroundStyle(t.dim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Quiet footer: deck type (+ wheelchair) on the left, the next two arrivals
    /// on the right. Keeps the vehicle facts and "if you miss it" out of the
    /// headline so the ETA reads cleanly.
    @ViewBuilder
    private func heroFooter(_ s: Service) -> some View {
        let next = nextTwoText(s, Date())
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: s.deck == .DD ? "bus.doubledecker" : "bus.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(s.deck.word)
                    .font(t.mono(11, weight: .medium))
                if s.wab {
                    Image(systemName: "figure.roll")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(t.dim)

            Spacer(minLength: 8)

            if !next.isEmpty {
                HStack(spacing: 6) {
                    Text("Then")
                        .font(t.sans(11, weight: .semibold))
                        .foregroundStyle(t.faint)
                    Text(next)
                        .font(t.mono(12, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// "10 · 26 min" for the 2nd/3rd arrivals (empty when neither exists).
    private func nextTwoText(_ s: Service, _ now: Date) -> String {
        func mins(_ d: Date?) -> String? {
            guard let d else { return nil }
            let e = fmtETA(max(0, Int(d.timeIntervalSince(now))))
            return e.big == "Arr" ? "now" : e.big
        }
        let parts = [mins(s.followingDate), mins(s.thirdDate)].compactMap { $0 }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: " · ") + " min"
    }

    /// Supporting context beneath the hero number — leads with the absolute
    /// arrival clock time ("Arrives 7:39 PM") when known, then the stops-away.
    private func approachContext(_ s: Service?) -> String {
        guard let s else { return "Waiting for the next \(svc)" }
        let stopsPart: String
        if let n = stopsRemaining {
            stopsPart = n == 0 ? "At your stop now" : "\(n) stop\(n == 1 ? "" : "s") away"
        } else {
            stopsPart = "On the way to your stop"
        }
        if let clock = arrivalClock(s) {
            return "Arrives \(clock) · \(stopsPart)"
        }
        return stopsPart
    }

    /// Absolute arrival time ("7:39 PM" / "19:39") from the live arrival date,
    /// honouring the 24-hour setting. Nil when there's no future arrival (e.g.
    /// arriving now) so the context falls back to just the stops-away text.
    private func arrivalClock(_ s: Service) -> String? {
        guard let d = s.arrivalDate, d.timeIntervalSinceNow >= 30 else { return nil }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = m.use24h ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }

    private func approachA11y(_ s: Service?) -> String {
        guard let s else { return "No live arrival for bus \(svc) yet" }
        let eta = fmtETA(s.etaSec)
        let time = eta.big == "Arr" ? "arriving now" : "arriving in \(eta.big) \(eta.small)"
        let ctx = stopsRemaining.map {
            $0 == 0 ? "at your stop" : "\($0) stop\($0 == 1 ? "" : "s") away"
        } ?? "on the way"
        return "Bus \(svc) \(time), \(ctx). \(s.load.label)."
    }

    // MARK: Live module — route strip + map, side by side (fills the screen)

    /// The glanceable "where is it / what's the route" block: a compact vertical
    /// route strip (origin → bus → your stop → destination) beside the live map.
    /// It expands to fill the space left under the hero so the route is always
    /// on-screen — no scrolling. Tapping anywhere opens the full-screen map.
    /// Falls back to the map alone when there's no usable bus position (opened
    /// from a bus search, or before the route loads).
    private var liveModule: some View {
        HStack(spacing: 0) {
            if let dir = currentDirection, !dir.stops.isEmpty,
               estimatedBusIndex != nil {
                // Left — the route strip taps up the full-route glass card.
                Button {
                    fb.select(); showRouteCard = true
                } label: {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        liveRouteStrip(dir)
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            Text("FULL ROUTE")
                                .font(t.mono(9, weight: .semibold))
                                .tracking(0.8)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(t.faint)
                    }
                    .frame(width: 138)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Full route for bus \(svc), with the bus's current position. Opens a card.")

                Rectangle().fill(t.line).frame(width: 1)
            }

            // Right — the map preview taps up the full map card.
            Button {
                fb.select(); frameMapForCard(); showMap = true
            } label: {
                mapPanel.contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(liveTrackingA11y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(t.line, lineWidth: 1))
    }

    private var liveTrackingA11y: String {
        var parts = ["Bus \(svc) on the map"]
        if let n = stopsRemaining {
            parts.append(n == 0 ? "at your stop now"
                                : "\(n) stop\(n == 1 ? "" : "s") away")
        }
        return parts.joined(separator: ", ") + ". Opens the map card."
    }

    // MARK: Route card (glass sheet — full route + live bus position)

    /// Full route timeline in a Liquid-Glass bottom card, raised by tapping the
    /// route strip. Shows every stop with the bus's current position and the
    /// boarding stop; tapping an upcoming stop sets the alight target that
    /// "Remind me to get off" then uses.
    private var routeCard: some View {
        let dest = liveService()?.dest ?? currentDirection?.destinationName ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bus \(svc)")
                        .font(t.sans(22, weight: .bold))
                        .foregroundStyle(t.fg)
                    if !dest.isEmpty {
                        Text("Towards \(dest)")
                            .font(t.sans(14))
                            .foregroundStyle(t.dim)
                    }
                }
                RouteTimeline(t: t, svc: svc, stops: timelineStops,
                              alightId: .constant(nil), selectable: false, embedded: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }

    // ── Compact route strip ─────────────────────────────────

    private struct StripNode {
        enum Kind { case origin, bus, you, dest }
        let kind: Kind
        let title: String
        let sub: String?
    }

    /// Up to four nodes: the line's origin (faint, only once the bus has left
    /// it), the bus (accent), your stop (target ring) and the destination
    /// terminus (faint, only when you're not it). The bus→you run is the solid
    /// accent segment; the rest is a faint dashed rail.
    private func stripNodes(_ dir: RouteDirection) -> [StripNode] {
        let stops = dir.stops
        guard !stops.isEmpty, let busIdx0 = estimatedBusIndex else { return [] }
        let youIdx = min(max(dir.youIndex, 0), stops.count - 1)
        let busIdx = min(max(busIdx0, 0), youIdx)
        let n = max(0, youIdx - busIdx)

        var nodes: [StripNode] = []
        if busIdx > 0, let origin = stops.first?.name {
            nodes.append(StripNode(kind: .origin, title: origin, sub: nil))
        }
        let busSub = n == 0
            ? "At your stop"
            : "\(n) stop\(n == 1 ? "" : "s") away"
        nodes.append(StripNode(kind: .bus, title: "Bus \(svc)", sub: busSub))
        nodes.append(StripNode(kind: .you, title: "Your stop",
                               sub: ds.stopName(stopCode)))
        if youIdx < stops.count - 1, let dest = stops.last?.name {
            nodes.append(StripNode(kind: .dest, title: dest, sub: nil))
        }
        return nodes
    }

    private func liveRouteStrip(_ dir: RouteDirection) -> some View {
        let nodes = stripNodes(dir)
        return VStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .top) {
                        if i != nodes.count - 1 {
                            stripConnector(after: node.kind)
                                .frame(width: 3, height: stripRowH)
                                .offset(y: 12)
                        }
                        stripDot(node.kind)
                            .frame(width: 24, height: 24)
                    }
                    .frame(width: 24, alignment: .top)
                    stripLabel(node)
                        .padding(.top, (node.kind == .bus || node.kind == .you) ? 0 : 3)
                    Spacer(minLength: 0)
                }
                .frame(height: i == nodes.count - 1 ? nil : stripRowH, alignment: .top)
            }
        }
    }

    private var stripRowH: CGFloat { 42 }

    @ViewBuilder
    private func stripDot(_ kind: StripNode.Kind) -> some View {
        switch kind {
        case .origin:
            Circle().stroke(t.faint, lineWidth: 1.5).frame(width: 7, height: 7)
        case .bus:
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(t.contrastFg)
                .frame(width: 22, height: 22)
                .background(t.soon, in: Circle())
                .overlay(Circle().stroke(t.surface, lineWidth: 2))
        case .you:
            Circle().fill(t.surface)
                .overlay(Circle().stroke(t.soon, lineWidth: 3))
                .frame(width: 15, height: 15)
        case .dest:
            Circle().fill(t.dim).frame(width: 8, height: 8)
        }
    }

    private func stripConnector(after kind: StripNode.Kind) -> some View {
        let active = kind == .bus
        return StripVLine()
            .stroke(active ? t.soon : t.faint,
                    style: StrokeStyle(lineWidth: active ? 2.5 : 1.5,
                                       lineCap: .round,
                                       dash: active ? [] : [2, 4]))
    }

    @ViewBuilder
    private func stripLabel(_ node: StripNode) -> some View {
        switch node.kind {
        case .origin, .dest:
            Text(node.title)
                .font(t.mono(11))
                .foregroundStyle(t.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        case .bus, .you:
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                if let sub = node.sub {
                    Text(sub)
                        .font(t.sans(12))
                        .foregroundStyle(node.kind == .bus ? t.soon : t.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    // MARK: First / last bus footer

    /// "Did I miss the last bus?" — a thin line under the title/route line.
    /// Hidden when unknown (older cache, or the non-anchor direction).
    @ViewBuilder
    private var firstLastFooter: some View {
        if let w = currentDirection?.firstLast, let pair = todaysWindow(w),
           pair.first != nil || pair.last != nil {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.faint)
                Text(firstLastLabel(pair))
                    .font(t.sans(12, weight: .medium))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Today's first/last pair (LTA "HHmm" strings), keyed off the calendar day.
    private func todaysWindow(_ w: OperatingWindow) -> (first: String?, last: String?)? {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1:  return (w.firstSun, w.lastSun)   // Sunday
        case 7:  return (w.firstSat, w.lastSat)   // Saturday
        default: return (w.firstWD,  w.lastWD)
        }
    }

    private func firstLastLabel(_ pair: (first: String?, last: String?)) -> String {
        switch (fmtBusClock(pair.first), fmtBusClock(pair.last)) {
        case let (f?, l?):  return "First \(f)  ·  Last \(l)"
        case let (f?, nil): return "First \(f)"
        case let (nil, l?): return "Last \(l)"
        default:            return "Not operating today"
        }
    }

    /// LTA gives "HHmm" (e.g. "0530", "2400", past-midnight "24xx"/"25xx").
    /// Formats to the user's 12/24-h preference; nil for "-"/empty/garbage.
    private func fmtBusClock(_ raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces),
              r.count == 4, let n = Int(r) else { return nil }
        let hh = n / 100, mm = n % 100
        guard (0...47).contains(hh), (0...59).contains(mm) else { return nil }
        let h24 = hh % 24
        if m.use24h { return String(format: "%02d:%02d", h24, mm) }
        var h12 = h24 % 12; if h12 == 0 { h12 = 12 }
        return String(format: "%d:%02d %@", h12, mm, h24 < 12 ? "AM" : "PM")
    }

    // MARK: Live map panel (right side of the live module)

    /// The live map — fills the live module's right side. Non-interactive; a tap
    /// on the module opens the full-screen map. Renders the stop pin, journey
    /// dots, the bus, and the user.
    private var mapPanel: some View {
        ZStack(alignment: .bottom) {
            // `.automatic` frames to fit the markers (stop, bus, journey dots,
            // you) with padding — so nothing clips at the edges of the narrow
            // preview. The full map card uses the interactive `camera` instead.
            Map(position: .constant(.automatic), interactionModes: []) {
                mapAnnotations
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            // A clear "this opens a map" affordance so the static preview never
            // reads as a pannable live map (it isn't — the tap opens a card).
            HStack(spacing: 5) {
                Image(systemName: "map.fill")
                Text("Open map")
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(t.mono(10, weight: .bold))
            .foregroundStyle(t.fg)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(t.line, lineWidth: 1))
            .padding(.bottom, 10)
        }
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
        // Show "You" only when it's plausibly near this stop. A far-off fix
        // (e.g. a default simulator location thousands of km away) would force
        // an `.automatic` camera to zoom out to span the globe.
        if let here = loc.location, let stop = ds.stopByCode[stopCode],
           haversine(here.coordinate.latitude, here.coordinate.longitude,
                     stop.Latitude, stop.Longitude) < 50_000 {
            Annotation("You", coordinate: here.coordinate, anchor: .center) {
                MapUserMarker().accessibilityLabel("Your location")
            }
        }
    }

    private var mapFullScreen: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $camera) { mapAnnotations }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea()
                .onChange(of: ds.stopByCode[stopCode]) { _, stop in
                    guard let s = stop, !didCenterOnStop else { return }
                    centerOnStop(s)
                }

            // Floating glass title — the sheet's drag indicator dismisses the
            // card, so there's no Done button.
            Text("Bus \(svc)")
                .font(t.sans(15, weight: .bold))
                .foregroundStyle(t.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if #available(iOS 26.0, *) {
                            Capsule().fill(.regularMaterial)
                        } else {
                            Capsule().fill(t.surface.opacity(0.94))
                        }
                    }
                )
                .overlay(Capsule().stroke(t.line, lineWidth: 1))
                .padding(.leading, 16)
                .padding(.top, 12)

            // Callout + recenter controls pinned to the bottom.
            VStack {
                Spacer()
                ZStack(alignment: .bottomLeading) {
                    if let callout = liveCalloutInfo {
                        busCallout(callout)
                            .padding(.leading, 16)
                            .padding(.bottom, 24)
                    }
                    VStack(spacing: 10) {
                        if loc.location != nil {
                            mapControlButton("location.fill", "Center on my location") {
                                recenterOnUser()
                            }
                        }
                        mapControlButton("bus.fill", "Recenter on the bus") {
                            recenterOnBus()
                        }
                    }
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

    // MARK: Alerts (top-bar bell + overflow menu)

    private var boardingAlertOn: Bool {
        m.alert(kind: .arrival, busNo: svc, stopCode: stopCode) != nil
    }

    /// Toggle the boarding alert from the pinned Track button: arm or cancel an
    /// arrival alert at this stop. No confirmation overlay — the button's
    /// "Track arrival" → "Tracking — tap to stop" state and the tap haptic are
    /// the feedback, and re-tapping is the undo. The lock-screen Live Activity
    /// follows automatically via AppModel.autoTrackSoonestAlert.
    private func toggleBoardingAlert() {
        fb.select()
        m.toggleArrivalAlert(
            busNo: svc, stopCode: stopCode,
            stopName: ds.stopName(stopCode),
            dest: liveService()?.dest ?? "")
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

    /// Frame the map to a sensible neighbourhood region whenever the card opens,
    /// so it never inherits a zoomed-way-out `.automatic` fit (which would also
    /// try to include a far-away user-location pin). Centres on the stop, and
    /// includes the bus only when it's plausibly nearby.
    private func frameMapForCard() {
        guard let stop = ds.stopByCode[stopCode] else { return }
        let stopC = CLLocationCoordinate2D(latitude: stop.Latitude, longitude: stop.Longitude)
        if let d = displayCoord,
           haversine(stopC.latitude, stopC.longitude, d.latitude, d.longitude) < 8000 {
            let lats = [stopC.latitude, d.latitude]
            let lons = [stopC.longitude, d.longitude]
            let center = CLLocationCoordinate2D(
                latitude: (lats.min()! + lats.max()!) / 2,
                longitude: (lons.min()! + lons.max()!) / 2)
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.006, (lats.max()! - lats.min()!) * 1.8),
                longitudeDelta: max(0.006, (lons.max()! - lons.min()!) * 1.8))
            camera = .region(MKCoordinateRegion(center: center, span: span))
        } else {
            camera = .region(MKCoordinateRegion(center: stopC,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
        didCenterOnStop = true
    }

    /// Recenter the map on the bus's *current* position. Refreshes the plot
    /// first and uses the freshest fix (live GPS / recent / ETA estimate) rather
    /// than the mid-glide marker, so it never lands on a stale, past position.
    private func recenterOnBus() {
        fb.select()
        recomputePlot()
        let target = liveBusCoord ?? estimatedCoord()
            ?? ds.stopByCode[stopCode].map {
                CLLocationCoordinate2D(latitude: $0.Latitude, longitude: $0.Longitude)
            }
        guard let center = target else { return }
        didAutoFrame = true
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        }
    }

    /// Recenter the map on the user's own location. The button that calls this
    /// is only shown when we actually have a fix.
    private func recenterOnUser() {
        fb.select()
        guard let here = loc.location else { return }
        didAutoFrame = true
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(
                center: here.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
    }

    /// A round glass map control (the recenter buttons).
    private func mapControlButton(_ icon: String, _ label: String,
                                  _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    // MARK: Route timeline (feeds the full-route card)

    private func etaClock(forIndex i: Int, busIdx: Int?, youIdx: Int, youEtaSec: Int) -> String? {
        // Only between the bus and your stop do we have a defensible time: it's
        // interpolated from the real arrival ETA. Past your stop we have no
        // anchor, so we show nothing rather than fabricate a 90 s-per-stop guess.
        guard let b = busIdx, youIdx > b, i >= b, i <= youIdx else { return nil }
        let secs = Double(youEtaSec) * Double(i - b) / Double(youIdx - b)
        let clock = fmtClock(Date().addingTimeInterval(secs), use24h: m.use24h)
        return i == b ? clock : "ETA \(clock)"
    }

    /// Full stop list (bus-to-terminus, or the entire line in full-route mode)
    /// with per-stop state for `RouteTimeline`, including the bus's "here" stop.
    private var timelineStops: [RouteStop] {
        guard let r = route, let dir = currentDirection else { return [] }
        let busSeq = estimatedBusIndex
        let youSeq = r.youIndex
        let youEta = liveService()?.etaSec ?? 0
        let canMarkBoard = !fullRoute && dir.anchorPresent
        let showFull = fullRoute || !dir.anchorPresent

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
        guard case .loaded(let s) = ds.arrivals[stopCode],
              var x = s.first(where: { $0.no == svc }) else { return nil }
        // Recompute the countdown against *now* from the absolute arrival
        // instants, so the displayed ETA ticks down smoothly between the 25 s
        // network refreshes instead of freezing at the last fetched value.
        let now = Date()
        if let a = x.arrivalDate { x.etaSec = max(0, Int(a.timeIntervalSince(now))) }
        if let f = x.followingDate {
            x.followingSec = max(x.etaSec, Int(f.timeIntervalSince(now)))
        }
        return x
    }

    /// One gentle nudge as the tracked bus crosses ~1 minute out, so you can
    /// look up without a loud alert. Fires once per approach; `didBuzzOneMin`
    /// re-arms once the ETA climbs back past ~75 s (the feed has rolled to the
    /// next bus). Foreground-only by nature — this view is on screen, which is
    /// exactly when the nudge is useful (background haptics don't play anyway).
    private func buzzIfApproaching() {
        guard let eta = liveService()?.etaSec else { return }
        if eta > 0 && eta <= 60 {
            if !didBuzzOneMin { didBuzzOneMin = true; fb.approachingSoon() }
        } else if eta > 75 {
            didBuzzOneMin = false
        }
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

/// A single vertical line segment — the rail used by the bus view's compact
/// route strip. (A plain Rectangle can't be dashed; a Shape can.)
struct StripVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}
