// WhereSia — Track bus (screen 7).
//
// Map-first tracking screen (owner 2026-07-11, sheet redone 2026-07-12). The
// live map is a full-screen hero behind a hand-rolled bottom sheet (not a
// system `.sheet` — that auto-inset + rounded-all-corners at non-.large
// detents read as a floating card disconnected from the map, and never
// cleanly dismissed on back-navigation). The sheet's header IS the ETA — the
// thing you drag to pull the route up is the same element that tells you when
// the bus arrives (anim spec: spatial continuity). Dragging the sheet between
// peek (simple ETA card) / half / full continuously shrinks, dims and blurs
// the map in place, and re-fits its camera wider once there's room to show
// the whole approach instead of just the tight your-stop framing. Tapping the
// map opens a full-screen interactive map with the approach stops and a
// live-info bar.
//
// Position is APPROXIMATE — LTA gives coords + ETAs for the next buses only, so
// per-stop minute times are not invented (only the your-stop ETA is real).
// iOS-only native MapKit (Android deliberately has no bus map — android-no-map).

import SwiftUI
import UIKit
import MapKit
import CoreLocation

/// Rounds only the top two corners — the flush-to-bottom-edge look of a real
/// bottom sheet (Apple Maps), vs. a system `.sheet`'s all-corners rounding.
private struct WSTopRoundedCorner: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect,
                          byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct WSTrackBusView: View {
    let stopCode: String
    let serviceNo: String
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var serviceRouteData: ServiceRoute?
    @State private var selectedDirIndex = 0
    @State private var busIndex: Int?
    @State private var busCoord: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var refreshTick = false

    /// The pull-up sheet's current height — a hand-rolled bottom sheet
    /// (owner: a real `.sheet` auto-insets + rounds all four corners at
    /// non-`.large` detents, so it read as a floating card disconnected from
    /// the map instead of one unified surface; it also left a stray sheet
    /// behind on back-navigation since `.sheet(isPresented: .constant(true))`
    /// never gets a clean dismiss when the screen pops).
    @State private var sheetHeight: CGFloat = Self.sheetPeek
    @State private var sheetDragStartHeight: CGFloat?
    /// Sticky docked/undocked flag — NOT recomputed fresh from `sheetHeight`
    /// every frame (owner-reported: dragging slowly through the swap
    /// threshold made the card "spasm," jittering back and forth). A single
    /// trigger line flips on the tiniest per-frame wobble in the drag value,
    /// and each flip swaps the sheet's content (compact card <-> full
    /// scrollable route), which is what actually visibly jittered. A
    /// hysteresis band around the threshold means the flip only fires once,
    /// cleanly, in each direction.
    @State private var docked: Bool = true
    // Tall enough to clear the ETA header + divider + CTA's fixed height at
    // rest (~330pt) without clipping them — anything smaller cuts off the CTA
    // button since only the route ScrollView between them is flexible.
    private static let sheetPeek: CGFloat = 340
    /// How far past peek the sheet has to move before the content actually
    /// swaps from the compact docked card to the full scrollable route list.
    /// Was gated to a `sheetStage` that only updated on drag-release, so
    /// mid-drag the (still-compact) content sat inside a taller frame than it
    /// needed, leaving dead space at the bottom (owner-reported "gap").
    /// Computed straight from `sheetHeight` instead so it tracks the drag.
    private static let sheetContentSwapThreshold: CGFloat = 60
    /// The full-screen interactive map (tap the hero to open).
    @State private var showFullMap = false
    /// The ⓘ operating-hours / route-ends popover.
    @State private var showInfo = false

    /// The tracked stop's own coordinate (for the live map).
    private var stopCoord: CLLocationCoordinate2D? {
        guard let s = store.stopByCode[stopCode] else { return nil }
        return CLLocationCoordinate2D(latitude: s.Latitude, longitude: s.Longitude)
    }

    private var service: Service? { store.servicesFor(stopCode).first { $0.no == serviceNo } }
    private var isAlerted: Bool {
        m.alert(kind: .arrival, busNo: serviceNo, stopCode: stopCode) != nil
    }

    /// The direction currently shown in the Route section below — starts on
    /// whichever direction serves `stopCode` but can be flipped with the
    /// switcher when the service runs both ways (mirrors Android's
    /// SegmentedButton on this same screen, restyled via WSSegmented).
    private var currentDirection: RouteDirection? {
        guard let sr = serviceRouteData, selectedDirIndex < sr.directions.count else { return nil }
        return sr.directions[selectedDirIndex]
    }

    /// The direction that actually serves the tracked stop, regardless of
    /// which one is currently being browsed. Anything describing the REAL bus
    /// being tracked (hero card, live bus marker) is grounded here so
    /// switching to the other direction never misrepresents it.
    private var anchorDirection: RouteDirection? {
        serviceRouteData?.directions.first(where: \.anchorPresent) ?? serviceRouteData?.directions.first
    }

    /// The live bus marker's stop index — meaningful only against the
    /// direction that actually serves this stop. Nil while the OTHER
    /// direction is being browsed, so a tracked bus is never drawn onto (or
    /// used to grey out stops on) a route it isn't actually running.
    private var displayBusIndex: Int? { busIndex }

    var body: some View {
        let _ = m.tick
        GeometryReader { geo in
            let undockedHeight = geo.size.height * 0.9
            // 0 docked, 1 fully undocked. Drives the map's live dim as the
            // sheet is dragged, not just a snap between fixed states.
            let progress = min(1, max(0, (sheetHeight - Self.sheetPeek) / (undockedHeight - Self.sheetPeek)))
            ZStack(alignment: .bottom) {
                // ── Hero map: the full-screen hero. Interactive (pinch to
                //    zoom, drag to pan) at rest — "Tap to expand" is the only
                //    way into the dedicated full-screen map now, so a plain
                //    tap on the map itself doesn't swallow zoom/pan gestures.
                //    A plain opacity scrim dims it as the sheet rises — NOT
                //    scaleEffect/blur, which forced the live MKMapView to
                //    re-render every drag frame and caused visible flashing
                //    plus a rendering gap at its shrunk-away edge (both
                //    owner-reported).
                heroMap(height: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.black.opacity(0.32 * progress)
                    .allowsHitTesting(false)

                mapTapHint
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(1 - progress)
                    .allowsHitTesting(progress < 0.5)

                bottomSheet(undockedHeight: undockedHeight, docked: docked,
                           bottomInset: geo.safeAreaInsets.bottom)
            }
            // Re-fit the camera once the sheet actually crosses into/out of
            // docked — tight on the approach docked, the whole segment
            // undocked.
            .onChange(of: sheetHeight, initial: true) { _, newHeight in
                updateDocked(for: newHeight)
            }
            .onChange(of: docked) { _, isDocked in
                // Refit only when returning to docked — the old undock refit
                // zoomed out to the whole run behind a 90%-height sheet + dim,
                // pure motion with nothing to see (owner: "what does it zoom
                // in to and for?").
                if isDocked {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.6)) {
                        refitMap()
                    }
                }
                // The initial `.task` fetch can silently come back nil on a
                // transient network hiccup, leaving `serviceRouteData` nil
                // forever with no retry (owner-reported: route sometimes
                // missing after pulling the card up — it was stuck showing
                // the loading shimmer indefinitely). Retry right when the
                // user pulls the sheet up to see it, since that's the moment
                // it'd actually be noticed missing.
                if !isDocked, serviceRouteData == nil {
                    Task { await loadRoute() }
                }
            }
        }
        .background(ws.bg)
        // The bar names the bus itself — "TRACK BUS" told the user nothing.
        .wsHeaderBar(eyebrow: "Track bus", title: "Bus \(serviceNo)",
                     collapsed: true, onBack: onBack) {
            HStack(spacing: 8) {
                // Bookmark the bus right here — previously the only save button
                // was buried on the Full-route screen (owner: hard to bookmark).
                WSHairButton(glyph: m.isFavService(no: serviceNo, stop: stopCode)
                                    ? .bookmarkFilled : .bookmark) {
                    m.toggleFavService(no: serviceNo, stop: stopCode)
                }
                WSHairButton(glyph: .info) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showInfo = true
                }
                .popover(isPresented: $showInfo) {
                    busInfoPopover
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light),
                         trigger: m.isFavService(no: serviceNo, stop: stopCode))
        .fullScreenCover(isPresented: $showFullMap) {
            WSBusFullMap(serviceNo: serviceNo,
                         seg: approachSegment(),
                         stopCoord: stopCoord,
                         stopName: store.stopName(stopCode),
                         busCoord: busCoord,
                         dest: destTitle,
                         awayText: stopsAway,
                         etaText: fullMapETA.text,
                         etaNow: fullMapETA.now,
                         crowd: (service?.load).map { ($0.wsDotColor, $0.wsSeatPhrase) },
                         onClose: { showFullMap = false })
        }
        .onAppear {
            store.ensureArrivals(stop: stopCode, force: true)
        }
        // Keep the tracked stop live while open (freshness-gated inside), and
        // refetch immediately on return from background — the tick loop was
        // paused, so the card would otherwise show minutes-old data until a
        // pull-to-refresh (owner-reported).
        .onChange(of: m.tick) { _, _ in
            store.ensureArrivals(stop: stopCode)
            // Move the map bus + "stops away" as the (freshly-cached) live GPS
            // advances — the map is no longer a frozen open-time snapshot.
            syncBusFromService()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.ensureArrivals(stop: stopCode, force: true) }
        }
        .task {
            // .task (not a fire-and-forget Task in onAppear) so the route
            // fetch cancels automatically if the user pops before it resolves.
            await loadRoute()
        }
        .sensoryFeedback(.success, trigger: refreshTick)
    }

    private func openFull() {
        UISelectionFeedbackGenerator().selectionChanged()
        showFullMap = true
    }

    /// "6 stops away" for the full-map info bar — nil when there's no live GPS
    /// index to count from, or the bus is already at the stop.
    private var stopsAway: String? {
        guard let dir = anchorDirection, let bi = busIndex, !dir.stops.isEmpty else { return nil }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let away = max(0, you - min(bi, you))
        guard away > 0 else { return nil }
        return away == 1 ? "1 stop away" : "\(away) stops away"
    }

    private var fullMapETA: (text: String, now: Bool) {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        if now { return ("Arriving", true) }
        if let sec { return ("\(max(1, sec / 60)) min", false) }
        return ("—", false)
    }

    // MARK: bottom sheet — one unified surface over the full-screen map
    //
    // Hand-rolled (not a system `.sheet`) so it reads as flush with the map
    // instead of a floating, all-corners-rounded card: rounded TOP corners
    // only, extends past the bottom safe area, drag handle lives in the ETA
    // header. Previously two separately-clipped `ws.panel` cards also stacked
    // with their own corner radii + shadow (owner: Bus view not polished) —
    // now a single panel start to finish.

    private func bottomSheet(undockedHeight: CGFloat, docked: Bool, bottomInset: CGFloat) -> some View {
        // The panel is laid out ONCE at its full (undocked) height and slid
        // with `.offset` — NOT `.frame(height: sheetHeight)`. Resizing the
        // frame per drag frame re-laid-out the entire panel (header + route
        // ScrollView) AND re-rendered the drop shadow — a Gaussian blur over
        // a layer whose size changed every frame — which dropped the frame
        // rate visibly while pulling the card up (owner-reported). An offset
        // is a cheap translation: layout and shadow are computed once and the
        // panel just slides. The CTA can't live inside a full-height sliding
        // panel (it would slide offscreen when docked), so it's pinned as its
        // own opaque footer layered over the panel's bottom edge.
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                etaHeader
                    .contentShape(Rectangle())
                    .gesture(sheetDrag(undocked: undockedHeight))
                WSRowDivider().padding(.horizontal, 18).padding(.vertical, 14)
                if docked {
                    // Docked = the simple ETA card only. No scroll container, no
                    // stop list — a fixed compact summary row so nothing from the
                    // route list can ever leak through a too-short sheet (owner-
                    // reported bug: a partial stop row was visible above the CTA).
                    routeCard(compact: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            routeCard(compact: false)
                            adCard.padding(.top, 14)
                            // Clearance for the pinned CTA footer overlaying
                            // the bottom of the panel (it's outside this
                            // scroll view now).
                            Color.clear.frame(height: 102 + bottomInset)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await store.refreshArrivals(stop: stopCode)
                        await loadRoute()
                        refreshTick.toggle()
                    }
                }
            }
            .frame(height: undockedHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ws.panel)
            .clipShape(WSTopRoundedCorner(radius: 22))
            // Hairline, not a drop shadow: the sheet still needs a hard edge
            // against the live map, but soft depth washes out in sunlight.
            .overlay(WSTopRoundedCorner(radius: 22).stroke(ws.rule, lineWidth: 1))
            .offset(y: undockedHeight - sheetHeight)

            // `.ignoresSafeArea` below drops the automatic home-indicator
            // inset, so the CTA reclaims it manually — otherwise it sits
            // flush under the indicator on Face ID devices. Opaque panel
            // fill so undocked scroll content passes behind it, not through.
            cta.padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity)
                .background(ws.panel)
        }
        .frame(height: undockedHeight, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        // NOT `.animation(value: sheetHeight)` — that implicitly springs
        // EVERY change, including the ~60-120/s updates from onChanged
        // below, so each finger movement queued a new spring on top of the
        // last one and the sheet visibly lagged behind the drag, leaving a
        // gap to the map underneath (owner-reported). Only the two explicit
        // `withAnimation` calls below (snap-to-rest, and the initial
        // appearance) should animate; the live drag must track 1:1.
        .wsEntrance()
    }

    /// Widens the docked/undocked swap threshold into a band so a slow drag
    /// hovering right around the trigger line doesn't flip content back and
    /// forth every frame.
    private func updateDocked(for height: CGFloat) {
        let trigger = Self.sheetPeek + Self.sheetContentSwapThreshold
        let band: CGFloat = 20
        let newDocked = docked ? (height < trigger + band) : (height < trigger - band)
        if newDocked != docked { docked = newDocked }
    }

    private func sheetDrag(undocked: CGFloat) -> some Gesture {
        // Global space, NOT the default .local — the header this gesture
        // lives on moves with every sheetHeight change, so local-space
        // translations were measured against a frame that shifted under the
        // finger each event. On a slow drag that feeds back (height update →
        // header moves → translation jumps → height jumps) as a visible
        // jitter (owner-reported spasm).
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = sheetDragStartHeight ?? sheetHeight
                sheetDragStartHeight = start
                // No animation here — 1:1 with the finger every frame.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    sheetHeight = min(undocked, max(Self.sheetPeek * 0.7, start - value.translation.height))
                }
            }
            .onEnded { value in
                sheetDragStartHeight = nil
                let draggingUp = value.translation.height < 0
                let midpoint = (Self.sheetPeek + undocked) / 2
                // A decisive flick commits to the other state even before
                // crossing the midpoint — feels responsive, not sticky.
                let fastFlick = abs(value.predictedEndTranslation.height - value.translation.height) > 200
                let goUndocked = fastFlick ? draggingUp : sheetHeight > midpoint
                let target = goUndocked ? undocked : Self.sheetPeek
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    sheetHeight = target
                }
            }
    }

    // MARK: ETA header (the sheet grabber)
    //
    // The header of the pull-up sheet doubles as the ETA hero: a grab handle,
    // which bus toward where + LIVE, then the big your-stop ETA. Same plate /
    // seat-dot / stacked-ETA grammar as WSDepartureRow so a tapped row grows
    // into a card that reads as the same object. Only the ETA numeral animates
    // (numericText); the seat dot's colour crossfades.

    private var etaHeader: some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        let minutes = sec.map { max(1, $0 / 60) }
        let sched = !(service?.monitored ?? true)
        return VStack(spacing: 0) {
            // Grab handle — signals the sheet pulls up over the map.
            Capsule().fill(ws.rule).frame(width: 40, height: 5)
                .padding(.top, 10).padding(.bottom, 14)

            // ── Header: which bus, toward where, live. ──────────────────
            HStack(spacing: 12) {
                RouteTile(text: serviceNo, size: .large)
                VStack(alignment: .leading, spacing: 3) {
                    Text(destTitle)
                        .font(ws.sans(16, weight: .heavy)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    if let load = service?.load {
                        HStack(spacing: 6) {
                            Circle().fill(load.wsDotColor).frame(width: 7, height: 7)
                                .animation(.easeInOut(duration: 0.2), value: load)
                            Text(load.wsSeatPhrase)
                                .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                                .lineLimit(1).allowsTightening(true)
                        }
                    } else {
                        Text("Waiting for the next bus…")
                            .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    }
                }
                Spacer(minLength: 8)
                if service != nil { WSLiveBadge() }
            }

            WSRowDivider().padding(.vertical, 14)

            // ── ETA hero: the whole reason the screen is open. ──────────
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Group {
                    if now {
                        Text("Arriving")
                            .font(ws.sans(32, weight: .heavy)).foregroundStyle(ws.now)
                    } else if let minutes {
                        // Scheduled-only ETA carries the whisper "~" — never a
                        // banner (feedback_timely_over_honest).
                        (Text(sched ? "~" : "").font(ws.sans(20, weight: .semibold)).foregroundStyle(ws.dim)
                         // The hero ETA MUST be tabular: `.monospacedDigit()`
                         // does not reliably apply to a bundled custom face,
                         // so this goes through ws.mono (IBM Plex Mono, real
                         // tabular figures) — otherwise the number jitters as
                         // it counts down.
                         + Text("\(minutes)").font(ws.mono(36, weight: .bold)).foregroundStyle(ws.text)
                         + Text(" min").font(ws.sans(16, weight: .semibold)).foregroundStyle(ws.dim))
                    } else {
                        Text("—").font(ws.sans(32, weight: .heavy)).foregroundStyle(ws.faint)
                    }
                }
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                Spacer(minLength: 8)
                Text(now ? "at your stop" : "to your stop")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            }
        }
        .padding(.horizontal, 18).padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Green left tick while arriving — the same "now" mark as the rows.
        .overlay(alignment: .leading) {
            if now {
                RoundedRectangle(cornerRadius: 2).fill(ws.now)
                    .frame(width: 4).padding(.vertical, 16)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .animation(.snappy(duration: 0.28), value: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardA11y(now: now, minutes: minutes, sched: sched))
    }

    private var destTitle: String {
        if let dest = service?.dest, !dest.isEmpty { return "To \(dest)" }
        let name = anchorDirection?.destinationName ?? ""
        return name.isEmpty ? "Bus \(serviceNo)" : "To \(name)"
    }

    private func cardA11y(now: Bool, minutes: Int?, sched: Bool) -> String {
        var parts = ["Tracking bus \(serviceNo)"]
        if let dest = service?.dest, !dest.isEmpty { parts.append("to \(dest)") }
        if now { parts.append("at your stop now") }
        else if let minutes { parts.append("\(sched ? "around " : "")\(minutes) minutes to your stop") }
        if let load = service?.load { parts.append(load.wsSeatPhrase) }
        return parts.joined(separator: ", ")
    }

    // MARK: info popover (ⓘ — operating hours + route ends)

    private var busInfoPopover: some View {
        let w = anchorDirection?.firstLast
        let origin = anchorDirection?.originName ?? ""
        let dest = anchorDirection?.destinationName ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RouteTile(text: serviceNo, size: .small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bus \(serviceNo)")
                        .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
                    if !origin.isEmpty && !dest.isEmpty {
                        Text("\(origin) → \(dest)")
                            .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            Text("FIRST & LAST BUS · YOUR STOP")
                .font(ws.mono(9.5, weight: .bold)).tracking(1).foregroundStyle(ws.faint)
                .padding(.bottom, 6)
            if let w {
                infoHoursRow("Weekdays", w.firstWD, w.lastWD)
                infoHoursRow("Saturday", w.firstSat, w.lastSat)
                infoHoursRow("Sun / P.H.", w.firstSun, w.lastSun, last: true)
            } else {
                Text(serviceRouteData == nil ? "Loading…" : "Not published for this stop.")
                    .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    .padding(.vertical, 8)
            }

            Button {
                showInfo = false
                push(.serviceInfo(no: serviceNo, fromStop: stopCode))
            } label: {
                HStack(spacing: 4) {
                    Text("Full route & stops")
                        .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.accentSoft)
                    WSIcon(glyph: .chevron, size: 10, color: ws.accentSoft)
                }
                .padding(.top, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 268)
        .background(ws.panel)
    }

    private func infoHoursRow(_ key: String, _ first: String?, _ last: String?,
                              last isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer()
                (Text(WSFmt.firstLast(first)).foregroundStyle(ws.text)
                 + Text(" – ").foregroundStyle(ws.dim)
                 + Text(WSFmt.firstLast(last)).foregroundStyle(ws.text))
                    .font(ws.mono(13, weight: .bold))
            }
            .padding(.vertical, 8)
            if !isLast { WSRowDivider() }
        }
    }

    // MARK: hero map
    //
    // The one thing a "tracking" view should show, promoted to the hero: the
    // bus on its way to your stop. Non-interactive preview (tap opens the
    // full-screen map); shared marker content with the full-screen map via
    // WSApproachMapContent so the two draw identically.

    /// The stops on the live approach (bus → your stop) with their coords —
    /// the segment the map draws as labelled stop markers.
    private func approachSegment() -> [WSApproachStop] {
        guard let dir = anchorDirection, !dir.stops.isEmpty else { return [] }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let lo = (busIndex.map { min($0, you) }) ?? max(0, you - 4)
        return (lo...you).map { i in
            WSApproachStop(coord: CLLocationCoordinate2D(latitude: dir.stops[i].lat,
                                                         longitude: dir.stops[i].lon),
                           isYou: i == you, name: dir.stops[i].name)
        }
    }

    /// The full run from the bus (or route start) to your stop.
    private func wideSegment() -> [WSApproachStop] {
        guard let dir = anchorDirection, !dir.stops.isEmpty else { return approachSegment() }
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        let lo = busIndex.map { min($0, you) } ?? 0
        return (lo...you).map { i in
            WSApproachStop(coord: CLLocationCoordinate2D(latitude: dir.stops[i].lat,
                                                         longitude: dir.stops[i].lon),
                           isYou: i == you, name: dir.stops[i].name)
        }
    }

    @ViewBuilder private func heroMap(height: CGFloat?) -> some View {
        // Zoom + pan directly on the docked map (owner: couldn't pinch to
        // zoom before — the whole map ate every tap to jump to the
        // full-screen cover instead). Rotate/pitch stay off; this is a
        // preview, not the primary navigation surface — "Tap to expand" is
        // the deliberate, explicit way into that.
        Map(position: $camera, interactionModes: [.zoom, .pan]) {
            WSApproachMapContent(ws: ws, serviceNo: serviceNo,
                                 seg: approachSegment(),
                                 stopCoord: stopCoord, stopName: store.stopName(stopCode),
                                 busCoord: busCoord)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: height)
        .clipped()
        // No legend: the route line + labelled YOUR STOP pin and numbered bus
        // plate are self-explanatory, and the legend competed with "Tap to
        // expand" for the map's header row (UX critique, 2026-07-13).
        .overlay(alignment: .topLeading) {
            if busCoord == nil {
                Text("Live bus updating…")
                    .font(ws.sans(11, weight: .semibold)).foregroundStyle(ws.dim)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(ws.panel))
                    .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
                    .padding(.top, 10).padding(.leading, 14)
            }
        }
        .accessibilityLabel(busCoord == nil
            ? "Map of your stop and the bus route; live bus position updating. Double tap to expand."
            : "Map showing bus \(serviceNo) approaching your stop. Double tap to expand.")
    }

    private var mapTapHint: some View {
        Button(action: openFull) {
            HStack(spacing: 5) {
                WSIcon(glyph: .map, size: 12, weight: .semibold, color: ws.text)
                Text("Tap to expand")
                    .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.text)
            }
            .padding(.horizontal, 11).frame(height: 30)
            .wsGlassChrome(cornerRadius: 15, tint: ws.tabbar)
            .contentShape(Rectangle())
        }
        .buttonStyle(WSCompressStyle())
        .padding(.top, 10).padding(.trailing, 22)
    }

    /// Frame the map to fit your stop, the bus, and the approach segment.
    /// `wide` widens it to the whole bus→you run — used once the sheet is
    /// pulled past peek and there's room above it to show the bigger picture.
    private func refitMap(wide: Bool = false) {
        let seg = wide ? wideSegment() : approachSegment()
        var region = wsApproachRegion(seg: seg, stop: stopCoord, bus: busCoord)
        // The peeked sheet permanently covers the bottom ~340pt of the
        // full-screen map, so a region centered on the whole screen puts the
        // markers under the sheet (owner screenshot: collapsed map showed
        // bare streets). When docked, stretch the region south so the fitted
        // content sits in the visible strip above the sheet.
        if docked {
            let screenH = UIScreen.main.bounds.height
            let covered = min(0.75, Self.sheetPeek / max(screenH, 1))
            let extra = region.span.latitudeDelta * covered / (1 - covered)
            region.span.latitudeDelta += extra
            region.center.latitude -= extra / 2
        }
        camera = .region(region)
    }

    // MARK: route card — the live "approach" (Option A, owner 2026-07-10)
    //
    // NOT the whole line. The old card listed all ~32 stops as a static
    // timeline — a foreign idiom to the rest of the app, and dead space that
    // never changed (LTA gives no per-stop times). This shows only the segment
    // that's actually live: how many stops the bus is from you, plus the
    // handful on final approach. The full end-to-end route lives on Service
    // Info (the ⓘ / "Full route ›" link). Grounded on the anchor direction —
    // no direction switcher (that's a full-route concern).

    /// `compact: true` is the docked card — headline only, no stop list, no
    /// "Full route" link (owner: docked view was leaking a partial stop row
    /// through the collapsed sheet instead of showing only what fits). The
    /// full breakdown only appears once the sheet is pulled up (undocked).
    @ViewBuilder private func routeCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                WSIcon(glyph: .busSingle, size: 15, weight: .medium, color: ws.dim)
                Text("On the way")
                    .font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer(minLength: 8)
                if !compact, serviceRouteData != nil {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        push(.serviceInfo(no: serviceNo, fromStop: stopCode))
                    } label: {
                        HStack(spacing: 4) {
                            Text("Full route")
                                .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.accentSoft)
                            WSIcon(glyph: .chevron, size: 10, color: ws.accentSoft)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WSCompressStyle())
                    .accessibilityLabel("See the full route for bus \(serviceNo)")
                }
            }

            if let dir = anchorDirection, !dir.stops.isEmpty {
                let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
                let busIdx = busIndex.map { min($0, you) }
                if compact {
                    approachHeadline(you: you, busIdx: busIdx).padding(.top, 14)
                } else {
                    approach(dir).padding(.top, 14)
                }
            } else if !compact {
                // Route still resolving — shimmer skeleton, never a spinner.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array([150, 190, 120].enumerated()), id: \.offset) { _, w in
                        HStack(spacing: 15) {
                            WSShimmerBar(width: 13, height: 13)
                            WSShimmerBar(width: CGFloat(w), height: 13)
                        }
                    }
                }
                .padding(.top, 18).padding(.bottom, 6)
                .accessibilityLabel("Loading route")
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: approach

    /// Only ever show the final approach — the last few stops before you. A bus
    /// that's still far would otherwise dump its entire 15–25-stop run into the
    /// card (owner-reported "immense" list); those earlier stops collapse into a
    /// single "N earlier stops · full route" row instead.
    private static let approachWindow = 5

    private func approach(_ dir: RouteDirection) -> some View {
        let stops = dir.stops
        let you = min(max(dir.youIndex, 0), stops.count - 1)
        let busIdx = busIndex.map { min($0, you) }
        // Window: bus → your stop when a live position exists; otherwise just
        // the last few stops before you — spatial context, no invented count.
        let naturalStart = busIdx ?? max(0, you - 3)
        let truncated = (you - naturalStart) > Self.approachWindow
        let start = truncated ? max(0, you - Self.approachWindow) : naturalStart
        let hidden = start - naturalStart   // stops between the bus and the window
        let ic = wsInterchange(forStopName: stops[you].name)
        // HORIZONTAL rail (owner 2026-07-19: the vertical list read as a
        // static timeline). The approach becomes a left→right progress strip —
        // the bus physically travels toward your stop, colour and motion carry
        // the liveness; your stop's detail card sits below it.
        return VStack(alignment: .leading, spacing: 0) {
            approachHeadline(you: you, busIdx: busIdx).padding(.bottom, 16)
            approachRail(stops: stops, start: start, you: you,
                         busIdx: busIdx, hidden: hidden)
                .padding(.bottom, 16)
            youBody(stops[you], ic: ic)
        }
    }

    /// The approach as a horizontal strip: hairline track, a blue→(green when
    /// arriving) progress fill behind the bus, a dot per stop, your stop as
    /// the big accent terminus, and the bus itself as a pinging capsule that
    /// springs along the rail as its GPS index advances.
    private func approachRail(stops: [RouteStopLive], start: Int, you: Int,
                              busIdx: Int?, hidden: Int) -> some View {
        let count = you - start + 1
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        let busFrac: CGFloat? = busIdx.map { bi in
            count > 1 ? CGFloat(max(0, bi - start)) / CGFloat(count - 1) : 1
        }
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let midY = geo.size.height / 2
                let xAt: (Int) -> CGFloat = { j in
                    count > 1 ? CGFloat(j) / CGFloat(count - 1) * (w - 16) + 8 : w / 2
                }
                ZStack(alignment: .leading) {
                    // Track.
                    Capsule().fill(ws.rule)
                        .frame(width: w, height: 4)
                        .position(x: w / 2, y: midY)
                    // Covered ground — blue while travelling, green on arrival.
                    if let busFrac {
                        let pw = max(10, busFrac * (w - 16) + 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [ws.accent, now ? ws.now : ws.accentSoft],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: pw, height: 4)
                            .position(x: pw / 2, y: midY)
                            .animation(reduceMotion ? .easeInOut(duration: 0.3)
                                       : .spring(response: 0.6, dampingFraction: 0.9),
                                       value: busFrac)
                    }
                    // Stop dots; your stop is the big terminus.
                    ForEach(0..<count, id: \.self) { j in
                        let i = start + j
                        let passed = busIdx.map { i <= $0 } ?? false
                        let isYou = i == you
                        Circle()
                            .fill(isYou ? ws.accent : (passed ? ws.accentSoft : ws.bg))
                            .frame(width: isYou ? 16 : 10, height: isYou ? 16 : 10)
                            .overlay(Circle().stroke(
                                isYou ? Color.white : (passed ? ws.accentSoft : ws.faint),
                                lineWidth: isYou ? 2.5 : 2))
                            // The terminus pings only when the bus capsule
                            // (the true live signal) isn't on the rail.
                            .background { if isYou && busFrac == nil { WSPing(cornerRadius: 999) } }
                            .position(x: xAt(j), y: midY)
                            .animation(.easeInOut(duration: 0.25), value: passed)
                    }
                    // The bus — pinging capsule riding the rail.
                    if let busFrac {
                        HStack(spacing: 3) {
                            WSIcon(glyph: .busSingle, size: 10, weight: .bold, color: .white)
                            Text(serviceNo)
                                .font(ws.mono(11, weight: .bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7).frame(height: 22)
                        .background(Capsule().fill(now ? ws.now : ws.accent))
                        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                        .background { WSPing(cornerRadius: 999) }
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .position(x: min(max(24, busFrac * (w - 16) + 8), w - 24), y: midY)
                        .animation(reduceMotion ? .easeInOut(duration: 0.3)
                                   : .spring(response: 0.6, dampingFraction: 0.8),
                                   value: busFrac)
                    }
                }
            }
            .frame(height: 36)
            .accessibilityElement()
            .accessibilityLabel(busIdx.map {
                "Bus \(serviceNo), \(max(0, you - $0)) stops from your stop"
            } ?? "Final approach to your stop")

            // Earlier stops collapse into one quiet doorway to the full route.
            if hidden > 0 {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    push(.serviceInfo(no: serviceNo, fromStop: stopCode))
                } label: {
                    HStack(spacing: 4) {
                        Text("+\(hidden) earlier \(hidden == 1 ? "stop" : "stops") · full route")
                            .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.dim)
                        WSIcon(glyph: .chevron, size: 9, color: ws.accentSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(WSCompressStyle())
                .accessibilityLabel("\(hidden) earlier stops. Open the full route.")
            }
        }
    }

    /// "6 stops away · Seats available" — the one genuinely live line in this
    /// card. Falls back to "Final approach" when there's no GPS to count from.
    @ViewBuilder private func approachHeadline(you: Int, busIdx: Int?) -> some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        HStack(spacing: 8) {
            if let busIdx {
                let away = max(0, you - busIdx)
                if now {
                    Text("Arriving")
                        .font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.now)
                } else if away == 0 {
                    // GPS says the bus is at/near your stop but the tracked
                    // ETA isn't under a minute (usually a nearer bus of the
                    // same service) — don't shout "Arriving" against a
                    // headline ETA of 20 min.
                    Text("Approaching your stop")
                        .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
                } else {
                    (Text("\(away)").font(ws.mono(22, weight: .bold)).foregroundStyle(ws.text)
                     + Text(away == 1 ? " stop away" : " stops away")
                        .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim))
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                }
            } else {
                Text("Final approach")
                    .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.text)
            }
            // No crowd repeat here — the sheet header two rows up already
            // says "· Seats available"; the same phrase twice in one card
            // read as clutter (owner route-list refinement, 2026-07-13).
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.28), value: busIdx)
    }

    private func youBody(_ stop: RouteStopLive, ic: (name: String, codes: [String])?) -> some View {
        let sec = service.map { wsLiveETASec($0) }
        let now = (sec ?? Int.max) < 60
        return VStack(alignment: .leading, spacing: 4) {
            Text(ic != nil ? "Your stop · MRT interchange" : "Your stop")
                .font(ws.sans(11, weight: .heavy)).tracking(0.4).foregroundStyle(ws.dim)
            Text(stop.name).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
            if let sec {
                Text(now ? "Arriving now" : "~\(max(1, sec / 60)) min")
                    .font(ws.sans(12, weight: .semibold)).foregroundStyle(now ? ws.now : ws.dim)
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            }
            if let ic {
                // The interchange line is a doorway into the MRT context —
                // tapping it opens the station (anim spec: the CC pill is a
                // continuity element between the bus and MRT worlds).
                if let st = MrtGeo.station(forCode: ic.codes.first ?? "") {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        push(.mrtStation(st))
                    } label: {
                        interchangeFlag("Change for", ic.codes)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WSCompressStyle())
                } else {
                    interchangeFlag("Change for", ic.codes)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(now ? ws.nowFill : ws.panel2)
        // Green marks "arriving this minute" only; the resting highlight is
        // the neutral nested surface + blue edge (identity stays blue).
        .overlay(alignment: .leading) { Rectangle().fill(now ? ws.now : ws.accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .padding(.bottom, 14)
    }

    private func interchangeFlag(_ label: String, _ codes: [String]) -> some View {
        HStack(spacing: 7) {
            WSIcon(glyph: .train, size: 15, color: ws.dim)
            Text(label).font(ws.sans(11, weight: .medium)).foregroundStyle(ws.dim)
            ForEach(codes.prefix(3), id: \.self) { LineBullet(code: $0) }
        }
        .padding(.top, 2)
    }

    // MARK: inline ad
    //
    // In-content MREC styled as a sheet card (same migration as the MRT station
    // view), replacing the old anchored bottom banner that fought the pinned
    // alert CTA. Self-suppresses when ads are disabled.
    @ViewBuilder private var adCard: some View {
        if !AdConfig.adsSuppressed {
            MediumRectAd()
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    // MARK: CTA

    private var cta: some View {
        Button {
            let name = store.stopName(stopCode)
            m.toggleArrivalAlert(busNo: serviceNo, stopCode: stopCode,
                                 stopName: name, dest: service?.dest ?? "")
        } label: {
            HStack(spacing: 9) {
                WSIcon(glyph: isAlerted ? .bellRing : .alerts, size: 19, color: ws.bg)
                Text(isAlerted ? "Alert set · tap to cancel" : "Alert me 1 stop before")
                    .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.bg)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(ws.text)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(WSCompressStyle())
        .padding(.horizontal, 22).padding(.vertical, 12)
        // Arming reads as a small win (.success); cancelling is a quieter
        // acknowledgement (.impact) — matches the app's "quiet by default"
        // haptic restraint (Feedback.swift).
        .sensoryFeedback(trigger: isAlerted) { _, new in new ? .success : .impact(weight: .light) }
    }

    // MARK: data

    private func loadRoute() async {
        guard let sr = await store.serviceRoute(service: serviceNo, stopCode: stopCode) else { return }
        let isFirstLoad = serviceRouteData == nil
        if reduceMotion { serviceRouteData = sr }
        else { withAnimation(.easeOut(duration: 0.35)) { serviceRouteData = sr } }
        // Preserve a manual direction switch across pull-to-refresh reloads —
        // only (re)seat the selection on first load, or if it's gone stale
        // (fewer directions came back than the index needs).
        if isFirstLoad || selectedDirIndex >= sr.directions.count {
            selectedDirIndex = sr.initialIndex
        }
        // The live bus position is plotted only against the direction that
        // actually serves this stop — grounded here regardless of which
        // direction is currently browsed below, so the tracked bus is never
        // drawn onto a route it isn't actually running.
        guard let anchor = sr.directions.first(where: { $0.anchorPresent }) ?? sr.directions.first,
              !anchor.stops.isEmpty else {
            busIndex = nil
            busCoord = nil
            refitMap()
            return
        }
        if let coord = await store.liveBus(service: serviceNo, stopCode: stopCode) {
            busCoord = coord
            busIndex = nearestStopIndex(to: coord, on: anchor)
        } else {
            busIndex = nil
            busCoord = nil
        }
        refitMap()
    }

    private func nearestStopIndex(to coord: CLLocationCoordinate2D, on dir: RouteDirection) -> Int? {
        let you = min(max(dir.youIndex, 0), dir.stops.count - 1)
        var best: (idx: Int, d: Double)? = nil
        for i in 0...you {
            let s = dir.stops[i]
            let d = haversine(coord.latitude, coord.longitude, s.lat, s.lon)
            if best == nil || d < best!.d { best = (i, d) }
        }
        return best?.idx
    }

    /// Live position without a network round-trip or camera refit: the tracked
    /// stop's arrivals are already refreshed every ~25s by `ensureArrivals`, and
    /// the cached `Service` carries the next bus's GPS (`busLat/busLon`). Reading
    /// those on each tick moves the map marker + "stops away" count between
    /// refreshes without fighting the user's pan/zoom (unlike `refitMap`). The
    /// your-stop ETA numeral already ticks off `m.tick`.
    private func syncBusFromService() {
        guard let svc = service, let lat = svc.busLat, let lon = svc.busLon,
              lat != 0, lon != 0,
              let anchor = anchorDirection, !anchor.stops.isEmpty else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        // Skip if effectively unchanged (avoid re-animating on every tick).
        if let cur = busCoord,
           abs(cur.latitude - lat) < 1e-5, abs(cur.longitude - lon) < 1e-5 { return }
        let idx = nearestStopIndex(to: coord, on: anchor)
        if reduceMotion {
            busCoord = coord; busIndex = idx
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { busCoord = coord; busIndex = idx }
        }
    }
}

// MARK: - Shared map content
//
// The approach markers, drawn identically by the hero preview and the
// full-screen map: the route polyline, upcoming-stop dots, the highlighted
// YOUR STOP pin, and the live green bus plate. The board's one hard rule holds
// — colour is data (blue = your stop, green = the live bus); everything else
// stays neutral.

/// One stop on the drawn approach segment.
struct WSApproachStop {
    let coord: CLLocationCoordinate2D
    let isYou: Bool
    let name: String
}

struct WSApproachMapContent: MapContent {
    let ws: WSTheme
    let serviceNo: String
    let seg: [WSApproachStop]
    let stopCoord: CLLocationCoordinate2D?
    let stopName: String
    let busCoord: CLLocationCoordinate2D?

    @MapContentBuilder var body: some MapContent {
        // The user's own live location — a person in an indigo puck, not the
        // default dot (which tints with the app accent and read as a muddy
        // brown blob; owner 2026-07-14). Indigo keeps it clear of the marker
        // palette: blue = your stop, green = the live bus.
        UserAnnotation {
            WSIcon(glyph: .me, size: 12, weight: .bold, color: .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.indigo))
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }

        // Upcoming stops on the approach — proper mini stop markers (bus
        // glyph in a white puck + the stop's name), not anonymous nodes, so
        // the bus's remaining run reads without a route line (owner pulled
        // the polyline, 2026-07-14: MKDirections geometry was buggy).
        ForEach(Array(seg.enumerated()), id: \.offset) { _, s in
            if !s.isYou {
                // Node only, no name capsule — six named nodes cluttered the
                // overlay; the names carry no decision weight here (owner
                // 2026-07-19). "Your stop" and the live bus stay labelled.
                Annotation("", coordinate: s.coord, anchor: .center) {
                    WSIcon(glyph: .busSingle, size: 10, weight: .bold, color: ws.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white))
                        .overlay(Circle().stroke(ws.accent, lineWidth: 2))
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                }
                .annotationTitles(.hidden)
            }
        }
        // YOUR STOP — the boarding stop, the loudest mark on the map: an
        // accent flag naming the stop (eyebrow + name), white-edged so it
        // separates from the tile, over the haloed pin dot.
        if let stopCoord {
            Annotation("Your stop", coordinate: stopCoord, anchor: .bottom) {
                VStack(spacing: 3) {
                    VStack(spacing: 1) {
                        Text("YOUR STOP")
                            .font(ws.mono(8.5, weight: .bold)).tracking(0.5)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(stopName)
                            .font(ws.sans(11.5, weight: .heavy)).foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ws.accent))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    ZStack {
                        Circle().fill(ws.accent).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                        Circle().fill(.white).frame(width: 6, height: 6)
                    }
                    .background { WSPing(cornerRadius: 999) }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
            }
            .annotationTitles(.hidden)
        }

        // THE BUS — live position, green plate.
        if let busCoord {
            Annotation("Bus \(serviceNo)", coordinate: busCoord, anchor: .center) {
                Text(serviceNo)
                    .font(ws.mono(12, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(ws.now))
                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            }
            .annotationTitles(.hidden)
        }
    }
}

/// Frame a region that fits your stop, the live bus, and the approach segment.
func wsApproachRegion(seg: [WSApproachStop],
                      stop: CLLocationCoordinate2D?,
                      bus: CLLocationCoordinate2D?) -> MKCoordinateRegion {
    var lats: [Double] = [], lons: [Double] = []
    if let stop { lats.append(stop.latitude); lons.append(stop.longitude) }
    if let bus { lats.append(bus.latitude); lons.append(bus.longitude) }
    for s in seg { lats.append(s.coord.latitude); lons.append(s.coord.longitude) }
    guard let minLat = lats.min(), let maxLat = lats.max(),
          let minLon = lons.min(), let maxLon = lons.max() else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1.3421, longitude: 103.8198),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    }
    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                       longitude: (minLon + maxLon) / 2),
        span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.008),
                               longitudeDelta: max((maxLon - minLon) * 1.5, 0.008)))
}

// MARK: - Full-screen map
//
// Tapping the hero opens this: the same approach markers on a fully interactive
// map, with a close button and a glass live-info bar (bus, ETA, crowd) docked
// at the bottom. A momentary snapshot — the markers reflect the position at the
// moment it opened (cover-first; a live-updating morph can come later).

private struct WSBusFullMap: View {
    let serviceNo: String
    let seg: [WSApproachStop]
    let stopCoord: CLLocationCoordinate2D?
    let stopName: String
    let busCoord: CLLocationCoordinate2D?
    let dest: String
    let awayText: String?
    let etaText: String
    let etaNow: Bool
    let crowd: (color: Color, phrase: String)?
    var onClose: () -> Void

    @Environment(\.ws) private var ws
    @State private var camera: MapCameraPosition

    init(serviceNo: String,
         seg: [WSApproachStop],
         stopCoord: CLLocationCoordinate2D?,
         stopName: String,
         busCoord: CLLocationCoordinate2D?,
         dest: String,
         awayText: String?,
         etaText: String, etaNow: Bool,
         crowd: (color: Color, phrase: String)?,
         onClose: @escaping () -> Void) {
        self.serviceNo = serviceNo
        self.seg = seg
        self.stopCoord = stopCoord
        self.stopName = stopName
        self.busCoord = busCoord
        self.dest = dest
        self.awayText = awayText
        self.etaText = etaText
        self.etaNow = etaNow
        self.crowd = crowd
        self.onClose = onClose
        _camera = State(initialValue: .region(
            wsApproachRegion(seg: seg, stop: stopCoord, bus: busCoord)))
    }

    var body: some View {
        // ZStack (not chained .overlay) with .plain button styles + explicit
        // contentShape — the same idiom WSMapView uses so the controls win the
        // tap over the interactive Map's gesture layer (owner: X/recenter were
        // unresponsive with .overlay + WSCompressStyle).
        ZStack {
            Map(position: $camera) {
                WSApproachMapContent(ws: ws, serviceNo: serviceNo,
                                     seg: seg, stopCoord: stopCoord, stopName: stopName,
                                     busCoord: busCoord)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    title
                    Spacer(minLength: 8)
                    closeButton
                }
                Spacer(minLength: 0)
                HStack { Spacer(minLength: 0); recenterButton }
                    .padding(.bottom, 12)
                infoBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            RouteTile(text: serviceNo, size: .small)
            Text("Live position")
                .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.text)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .wsGlassChrome(cornerRadius: 20, tint: ws.tabbar)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            WSIcon(glyph: .close, size: 16, weight: .bold, color: ws.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .wsGlassChrome(cornerRadius: 22, tint: ws.tabbar, interactive: true)
        .accessibilityLabel("Close map")
    }

    // "Find me" — centres on the user's own location (falling back to the
    // bus+stop frame if location isn't available yet). MapKit tracks the blue
    // dot, so this follows the user without a CLLocationManager here.
    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                camera = .userLocation(
                    fallback: .region(wsApproachRegion(seg: seg, stop: stopCoord, bus: busCoord)))
            }
        } label: {
            WSIcon(glyph: .location, size: 18, color: ws.text)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .wsGlassChrome(cornerRadius: 23, tint: ws.tabbar, interactive: true)
        .accessibilityLabel("Centre on my location")
    }

    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(etaNow ? "Arriving" : "\(etaText)")
                        .font(ws.sans(20, weight: .heavy).monospacedDigit())
                        .foregroundStyle(etaNow ? ws.now : ws.text)
                    Text(etaNow ? "at your stop" : "to your stop")
                        .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                }
                Spacer(minLength: 8)
                if let crowd {
                    HStack(spacing: 6) {
                        Circle().fill(crowd.color).frame(width: 8, height: 8)
                        Text(crowd.phrase)
                            .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(ws.dim)
                            .lineLimit(1).allowsTightening(true)
                    }
                }
            }
            // A little more context: where it's headed + how far out.
            if !dest.isEmpty || awayText != nil {
                HStack(spacing: 7) {
                    if !dest.isEmpty {
                        Text(dest)
                            .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim)
                            .lineLimit(1)
                    }
                    if !dest.isEmpty && awayText != nil {
                        Text("·").font(ws.mono(11)).foregroundStyle(ws.faint)
                    }
                    if let awayText {
                        Text(awayText)
                            .font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .wsGlassChrome(cornerRadius: 22, tint: ws.tabbar)
        .padding(.horizontal, 16).padding(.bottom, 20)
    }
}
