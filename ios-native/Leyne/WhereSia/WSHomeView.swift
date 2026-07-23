// WhereSia — Home · Nearby transport (screen 1).
//
// Owner spec 2026-07-08 ("Nearby transport" reference + Leyne Animation
// Specification v1.0): a NEARBY chip + search button top row, "Nearby
// transport" title, an "Updated just now" freshness line, then three cards —
// the closest Bus stop (name, walk line, plated departure rows with seat
// dots and stacked ETAs, "View all buses" in-place expansion), the Nearest
// MRT (name + line bullets, walk line), and a "Browse nearby transport"
// door to the map. Motion per the spec: staggered 60ms launch sequence,
// numeric-only ETA transitions, springing row reorder, 98% tap compress,
// shimmer skeletons, inline error banner, calm springs throughout — all
// gated behind Reduce Motion.

import SwiftUI
import CoreLocation

// Seat-dot vocabulary lives in WSFormat (Load.wsDotColor / wsSeatPhrase);
// the row itself is the shared WSDepartureRow, and the 98%/80ms tap compress
// is WSCompressStyle — all in WSComponents, shared with the Bus stop screen.

// MARK: - Home

struct WSHomeView: View {
    var onSearch: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// Freshness line state: idle ↔ refreshing crossfade (150ms per spec).
    @State private var refreshing = false
    /// Inline "Unable to refresh" banner (slides from top, self-dismisses).
    @State private var showErrorBanner = false
    /// Bus (0) / MRT (1) content mode — the segmented toggle under the hero.
    @State private var mode = 0

    private var coord: CLLocationCoordinate2D? { location.location?.coordinate }

    private var nearbyStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] {
        guard let c = coord else { return [] }
        return MrtGeo.nearestStations(to: c, limit: 4)
    }

    private var busStops: [NearbyStop] {
        store.nearby.filter { !m.hiddenNearby.contains($0.stopCode) }
    }

    var body: some View {
        let _ = m.tick   // per-second live countdown refresh
        ScrollView {
            VStack(spacing: 0) {
                // Launch sequence (spec): hero 0ms → bus card 60ms →
                // MRT card 120ms → browse 180ms. Fade + 12pt rise, ease out.
                // The header is a flat search entry over the page background
                // (the animated sky gradient was removed 2026-07-22 — see
                // WSGradientHero.swift). It owns the search entry, so the old
                // header search circle is gone.
                WSGreetingHero(onSearchTap: onSearch)
                    .wsEntrance(delay: 0)

                // Bus / MRT mode toggle (owner mockups): swaps the content
                // below in place. Bus = nearby stops; MRT = nearest station
                // + crowd/forecast/facilities/line-map/status (WSMrtHomeContent).
                WSSegmented(options: ["Bus", "MRT"], selection: $mode)
                    .padding(.horizontal, 22).padding(.top, 14)
                    .wsEntrance(delay: 0.03)

                freshnessLine
                    .padding(.horizontal, 22).padding(.top, 14)
                    .wsEntrance(delay: 0.05)

                if mode == 0 {
                    busContent
                        .transition(.opacity)
                } else {
                    mrtContent
                        .transition(.opacity)
                }

                if mode == 0 { hiddenFooter }
                Color.clear.frame(height: 24)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: mode)
        .sensoryFeedback(.selection, trigger: mode)
        .refreshable { await refresh() }
        .background(ws.bg)
        .overlay(alignment: .top) { if showErrorBanner { errorBanner } }
        .onAppear(perform: bootstrap)
        .onChange(of: location.location) { _, loc in
            if let loc { store.updateNearby(loc); store.prefetchNearbyArrivals() }
            store.wsWarmCrowd(for: nearbyStations.map(\.station))
        }
        // Nearby rows otherwise only refresh on a location change — sit
        // still and they go stale. The freshness window inside
        // ensureArrivals turns this into an actual fetch ~every 25s.
        .onChange(of: m.tick) { _, _ in store.prefetchNearbyArrivals() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if case .error = store.referenceState {
                    Task { await store.bootstrap() }
                }
                store.prefetchNearbyArrivals()
                store.wsWarmCrowd(for: nearbyStations.map(\.station))
            }
        }
    }

    // MARK: content modes

    @ViewBuilder private var busContent: some View {
        // Bus mode is buses only (owner 2026-07-10): the Nearest-MRT card is
        // gone; instead the nearest bus stops to the user stack down the
        // board, each a full departure card, soonest walk first.
        if busStops.isEmpty {
            loadingOrEmpty
                .padding(.horizontal, 22).padding(.top, 14)
                .wsEntrance(delay: 0.06)
        } else {
            // One board panel, not one slab per stop: six isolated grey cards
            // each carrying two text lines read as repetitive dead weight.
            // The rows share a panel with hairline dividers — the same
            // departure-board grammar as the Bus stop screen. Previously split
            // in two around an in-feed native ad; the ad was removed
            // (owner 2026-07-22) and the board is whole again.
            stopBoard(Array(busStops.prefix(6)))
                .padding(.horizontal, 22).padding(.top, 14)
                .wsEntrance(delay: 0.06)
        }
    }

    /// One board panel of nearby-stop rows separated by hairline dividers.
    private func stopBoard(_ stops: [NearbyStop]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.stopCode) { i, stop in
                if i > 0 { WSRowDivider().padding(.leading, 18) }
                BusStopCard(stop: stop)
            }
        }
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var mrtContent: some View {
        if let item = nearbyStations.first {
            WSMrtHomeContent(station: item.station, distanceM: item.distanceM,
                             walkMin: item.walkMin)
                .padding(.top, 14)
        } else {
            emptyState("Turn on location to see the station nearest you.")
                .padding(.horizontal, 22).padding(.top, 14)
        }
    }

    private func bootstrap() {
        if case .error = store.referenceState {
            Task { await store.bootstrap() }
        }
        location.start()
        // Home renders UNDERNEATH the onboarding overlay (RootView ZStack), so
        // its onAppear runs on first launch too — during onboarding, the
        // location primer owns the permission request (App Store 5.1.1(iv)).
        if location.status == .notDetermined && !m.showOnboarding {
            location.requestPermission()
        }
        if let loc = location.location { store.updateNearby(loc) }
        store.ensureRoutes()
        store.prefetchNearbyArrivals()
        store.wsWarmCrowd(for: nearbyStations.map(\.station))
    }

    /// Pull-to-refresh: freshness line crossfades to "Refreshing…", each
    /// changed ETA animates independently (numericText on the rows — the
    /// card itself is never rebuilt), then back to "Updated just now".
    private func refresh() async {
        withAnimation(.easeInOut(duration: 0.15)) { refreshing = true }
        let before = store.newestRefresh(amongst: busStops.map(\.stopCode))
        for stop in busStops.prefix(3) {
            await store.refreshArrivals(stop: stop.stopCode)
        }
        store.wsWarmCrowd(for: nearbyStations.map(\.station))
        let after = store.newestRefresh(amongst: busStops.map(\.stopCode))
        withAnimation(.easeInOut(duration: 0.15)) { refreshing = false }
        if !busStops.isEmpty && after == before {
            // Nothing landed — surface the inline banner (spec: no popups).
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showErrorBanner = true
            }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { showErrorBanner = false }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: header

    private var header: some View {
        // No headline at all (owner 2026-07-08): the cards' own "Nearest bus
        // stop" / "Nearest MRT" eyebrows carry the message, so the top row is
        // just the quiet freshness line and the search button — content
        // starts immediately.
        HStack(alignment: .center, spacing: 12) {
            freshnessLine
            Button(action: onSearch) {
                WSIcon(glyph: .search, size: 17, color: ws.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(ws.panel))
                    .contentShape(Circle())
            }
            .buttonStyle(WSCompressStyle())
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    /// "Updated just now" ↔ "Refreshing…" — a 150ms crossfade, with the
    /// refresh glyph rotating while a fetch is in flight.
    private var freshnessLine: some View {
        HStack(spacing: 8) {
            WSIcon(glyph: .refresh, size: 13, weight: .regular, color: ws.dim)
                .rotationEffect(.degrees(refreshing && !reduceMotion ? 180 : 0))
                .animation(refreshing ? .easeInOut(duration: 0.6).repeatForever(autoreverses: false)
                                      : .easeOut(duration: 0.25),
                           value: refreshing)
            Text(refreshing ? "Refreshing…" : updatedText)
                .font(ws.sans(14, weight: .medium)).foregroundStyle(ws.dim)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: refreshing)
        .contentShape(Rectangle())
        // Stripe "Buy me a coffee" — WhereSia has no Settings screen, so the
        // support link lives in a long-press menu on this quiet line (owner
        // call 2026-07-14). Opens the Payment Link in the browser: PayNow +
        // cards + Apple Pay, ad-funded app, strictly optional.
        .contextMenu {
            Button {
                openURL(AppLinks.coffee)
            } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
            }
        }
    }

    private var updatedText: String {
        guard let d = store.newestRefresh(amongst: busStops.map(\.stopCode)) else {
            return "Updated —"
        }
        return Date().timeIntervalSince(d) < 60
            ? "Updated just now"
            : WSFmt.upd(d, use24h: m.use24h)
    }

    // The browse-door map button lives in WSRoot (overlaid above the
    // tab-bar safe-area inset — inside this ScrollView it gets covered).

    // MARK: loading / empty / hidden

    @ViewBuilder private var loadingOrEmpty: some View {
        if coord == nil && location.status != .notDetermined {
            emptyState("Turn on location to see transport near you.")
        } else if case .error = store.referenceState {
            Button { Task { await store.bootstrap() } } label: {
                emptyState("Stops aren’t loading right now — tap to retry.")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            WSSkeletonCard()
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 10) {
            WSIcon(glyph: .busSingle, size: 26, color: ws.faint)
            Text(text)
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity.animation(.easeOut(duration: 0.25)))
    }

    @ViewBuilder private var hiddenFooter: some View {
        let hiddenHere = store.nearby.filter { m.hiddenNearby.contains($0.stopCode) }.count
        if hiddenHere > 0 {
            Button {
                withAnimation(.snappy(duration: 0.25)) { m.hiddenNearby = [] }
            } label: {
                Text("\(hiddenHere) \(hiddenHere == 1 ? "stop" : "stops") hidden · SHOW")
                    .font(ws.mono(11, weight: .medium)).tracking(0.4)
                    .foregroundStyle(ws.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: error banner (spec: inline, slides from top, self-dismisses)

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Text("Unable to refresh")
                .font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.text)
            Spacer(minLength: 8)
            Button("Retry") { Task { await refresh() } }
                .font(ws.sans(13, weight: .bold))
                .foregroundStyle(ws.accentSoft)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(ws.panel2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
        .padding(.horizontal, 22).padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Bus stop card
//
// Compact stop row (owner 2026-07-17): the departures moved out of Home —
// each stop is now just its identity ("95081 · Changi Beach CP 5"), the walk
// line, and the bookmark. Tap opens the Stop screen, which owns the board.

private struct BusStopCard: View {
    let stop: NearbyStop
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                push(.busStop(code: stop.stopCode))
            } label: {
                // ONE flush-left column (owner 2026-07-22). The stop code is
                // gone from this row entirely: it was meta, and as a left
                // column it kept fighting the layout — a fixed-size chip
                // beside a variable-height text column left a hole under it,
                // and stretching it into a rail turned the least important
                // element into the heaviest. The code still appears on the
                // stop screen this row opens, and in the a11y label below.
                //
                // A 2×2 grid of STATIC facts — no live ETA (owner 2026-07-22).
                // Arrivals left this row entirely: the live number belongs on
                // the stop screen, where there's room to show the whole board
                // honestly. What's left is everything that helps you CHOOSE a
                // stop, and none of it can go stale mid-glance.
                //
                //   Changi Beach CP 5                 5 min
                //   95081                        380 meters
                //
                // Left column = identity (which stop), right column = cost
                // (how long, how far) on the trailing edge where the eye
                // exits; line 1 is the answer, line 2 the same pair one tier
                // quieter. Four cells on a shared grid, so the card reads as
                // a table rather than four loose bits (owner layout).
                VStack(alignment: .leading, spacing: 3) {
                    // Line 1 — identity left, cost right.
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(stop.stopName)
                            .font(ws.sans(17, weight: .bold)).foregroundStyle(ws.text)
                            // One line, never wrapped (owner 2026-07-19);
                            // a truly long one shrinks a touch, last resort.
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                        mrtBadges
                        Spacer(minLength: 8)
                        walkTime.fixedSize().accessibilityHidden(true)
                    }
                    // Line 2 — the same pair, one tier quieter.
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(stop.stopCode)
                            .font(ws.mono(12, weight: .medium))
                            .foregroundStyle(ws.faint)
                        Spacer(minLength: 8)
                        distanceText.fixedSize().accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(stop.stopName)")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPinned)
        // The row is two lines again, so it can afford a little more air than
        // the three-line version needed (14 → 15, back to the board's
        // original row rhythm).
        .padding(.horizontal, 18).padding(.vertical, 15)
        // No per-row surface: rows live inside the shared board panel
        // (stopBoard) with hairline dividers between them.
        .background(ws.panel)
        // The row is the zoom source for the stop screen it opens (anim
        // spec: matched geometry — same treatment as the MRT card).
        .wsZoomSource(id: wsStopZoomID(stop.stopCode))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button(action: togglePin) {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "bookmark.slash" : "bookmark")
            }
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.25)) { m.hideFromNearby(code: stop.stopCode) }
            } label: {
                Label("Hide from Nearby", systemImage: "eye.slash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(a11y)
        // With the visible bookmark gone, saving must still be reachable
        // without a long-press: this puts it in VoiceOver's Actions rotor.
        .accessibilityAction(named: isPinned ? "Remove from Saved" : "Save stop",
                             togglePin)
    }

    /// Walk minutes — the answer that sits opposite the stop name, because "how
    /// long to get there?" is the decision this row exists to support. 80 m/min
    /// is the standard pedestrian planning figure.
    @ViewBuilder private var walkTime: some View {
        let d = stop.distanceM
        if d <= 0 {
            Text("Nearby")
                .font(ws.sans(13.5, weight: .semibold)).foregroundStyle(ws.text)
        } else if d > 50_000 {
            // A simulator fix or a stale GPS lock — "169575 min walk" is noise,
            // not data. Say the one true thing and stop.
            Text("Far from here")
                .font(ws.sans(13.5, weight: .semibold)).foregroundStyle(ws.dim)
        } else {
            let walkMin = max(1, Int((Double(d) / 80).rounded()))
            HStack(spacing: 5) {
                WSIcon(glyph: .walk, size: 11, weight: .medium, color: ws.dim)
                Text(walkMin <= 60 ? "\(walkMin) min" : "over an hour")
                    .font(ws.mono(13.5, weight: .bold)).foregroundStyle(ws.text)
            }
        }
    }

    /// Raw distance, under the walk time — the supporting detail that makes the
    /// minutes checkable. Spelt out ("380 meters", never "380 m") per the
    /// app-wide rule, since a bare "m" reads as minutes at a glance.
    @ViewBuilder private var distanceText: some View {
        let d = stop.distanceM
        if d > 0 {
            // Beyond the walk threshold the MINUTES are nonsense, but the
            // distance never is — and printing it keeps line 2 balanced and
            // lets the reader sanity-check a stale GPS lock for themselves.
            Text(d < 1000 ? "\(d) meters"
                          : String(format: d >= 50_000 ? "%.0f km" : "%.1f km",
                                   Double(d) / 1000))
                .font(ws.sans(12, weight: .medium))
                .foregroundStyle(ws.faint)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: d)
        }
    }

    /// MRT interchange badges (owner 2026-07-17): when this bus stop sits at
    /// a rail station ("Farrer Rd Stn Exit A" → Farrer Road, CC20), its
    /// station codes appear as line-coloured tiles — the same LineBullet
    /// grammar as everywhere else in the app. Nothing for plain stops.
    @ViewBuilder private var mrtBadges: some View {
        if let ic = wsInterchange(forStopName: stop.stopName) {
            HStack(spacing: 4) {
                ForEach(ic.codes, id: \.self) { code in
                    LineBullet(code: code)
                }
            }
            .accessibilityLabel("At \(ic.name) MRT station")
        }
    }

    private var isPinned: Bool { m.pins.contains { $0.code == stop.stopCode } }
    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == stop.stopCode }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: stop.stopCode, nickname: "")) }
    }

    private var a11y: String {
        // The code is no longer shown in the row, so VoiceOver carries it —
        // it's still how riders match a stop against a pole sign.
        var parts = ["Bus stop \(stop.stopName)", "code \(stop.stopCode)"]
        if stop.distanceM > 0, stop.distanceM <= 50_000 {
            parts.append("\(max(1, Int((Double(stop.distanceM) / 80).rounded()))) minute walk")
            parts.append(stop.distanceM < 1000
                         ? "\(stop.distanceM) meters away"
                         : String(format: "%.1f kilometers away", Double(stop.distanceM) / 1000))
        }
        return parts.joined(separator: ", ")
    }
}

/// "🚶 1 min walk · 39 meters" — shared by both cards so the two stops always
/// speak the same format. Walking-distance changes crossfade only (spec).
/// Spelt-out "meters" (never "m", which reads as minutes at a glance) and
/// `text`-level contrast — this line is a primary decision input, not meta.
private struct WalkLine: View {
    let distanceM: Int
    /// Quiet variant for the compact stop rows, where the walk line is meta
    /// under the stop name rather than a primary decision input.
    var compact: Bool = false
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            WSIcon(glyph: .walk, size: compact ? 11 : 13, weight: .medium, color: ws.dim)
            Text(text)
                .font(ws.sans(compact ? 12.5 : 13.5, weight: compact ? .medium : .semibold))
                .foregroundStyle(compact ? ws.dim : ws.text)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
                // One line always — with the next-bus teaser on the row's
                // trailing edge this can get squeezed; shrink, never wrap.
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
    private var text: String {
        guard distanceM > 0 else { return "Nearby" }
        // Walk minutes only while walking is plausible (~1 h). Beyond that —
        // and especially the far-off fixes a simulator or a stale GPS lock
        // produces — "169575 min walk · 13566.0 km" is noise, not data.
        if distanceM > 50_000 { return "Far from here" }
        let walkMin = max(1, Int((Double(distanceM) / 80).rounded()))
        let dist = distanceM < 1000 ? "\(distanceM) meters"
                                    : String(format: "%.1f km", Double(distanceM) / 1000)
        guard walkMin <= 60 else { return "\(dist) away" }
        return "\(walkMin) min walk  ·  \(dist)"
    }
}

private func walkLine(distanceM: Int) -> WalkLine { WalkLine(distanceM: distanceM) }

// MARK: - Nearest MRT card

private struct NearestMrtCard: View {
    let station: MrtGeoStation
    let distanceM: Int
    let walkMin: Int
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            push(.mrtStation(station))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    WSIcon(glyph: .train, size: 15, weight: .medium, color: ws.dim)
                    Text("Nearest MRT")
                        .font(ws.sans(14, weight: .semibold)).foregroundStyle(ws.dim)
                    Spacer(minLength: 8)
                    WSIcon(glyph: .chevron, size: 12, color: ws.faint)
                }
                HStack(spacing: 10) {
                    Text(station.name)
                        .font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    ForEach(station.codes, id: \.self) { LineBullet(code: $0) }
                    if let crowd = store.wsCrowd(for: station), crowd != .unknown {
                        Spacer(minLength: 6)
                        HStack(spacing: 6) {
                            CrowdGauge(fraction: crowd.wsFraction, width: 22)
                            Text(crowd.wsWord)
                                .font(ws.mono(11, weight: .bold)).foregroundStyle(ws.dim)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 12)
                WSRowDivider().padding(.top, 14)
                walkLine(distanceM: distanceM)
                    .padding(.top, 13)
            }
            .padding(.horizontal, 18).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ws.panel)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(WSCompressStyle())
        // The card is the zoom source for the station screen it opens —
        // tapping it expands the card into the detail (anim spec: matched
        // geometry, "feels connected").
        .wsZoomSource(id: wsMrtZoomID(station))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu {
            Button { m.toggleMrtSaved(station) } label: {
                Label(m.isMrtSaved(station) ? "Remove from Saved" : "Save station",
                      systemImage: m.isMrtSaved(station) ? "bookmark.slash" : "bookmark")
            }
        }
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        var parts = ["Nearest MRT, \(station.name)", wsLineNames(from: station.codes)]
        if distanceM > 0 { parts.append("\(walkMin) minute walk") }
        if let crowd = store.wsCrowd(for: station), crowd != .unknown {
            parts.append("crowd \(crowd.wsWord)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Distinct human line names from a station's codes, e.g. "North South / Thomson–East Coast".
func wsLineNames(from codes: [String]) -> String {
    var names: [String] = []
    for c in codes {
        let name: String
        switch c.prefix(2).uppercased() {
        case "NS": name = "North South"
        case "EW", "CG": name = "East West"
        case "NE": name = "North East"
        case "CC", "CE": name = "Circle"
        case "DT": name = "Downtown"
        case "TE": name = "Thomson–East Coast"
        default: name = "LRT"
        }
        if !names.contains(name) { names.append(name) }
    }
    return names.joined(separator: " / ")
}
