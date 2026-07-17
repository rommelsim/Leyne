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
                // The hero is the living sky (WSGradientHero) — greeting +
                // search over a time/weather-driven ambient gradient, NO photo
                // (owner 2026-07-10, copyright). It owns the search entry, so
                // the old header search circle is gone.
                WSGreetingHero(onSearchTap: onSearch)
                    .wsEntrance(delay: 0)

                // Bus / MRT mode toggle (owner mockups): swaps the content
                // below in place. Bus = nearby stops; MRT = nearest station
                // + crowd/forecast/facilities/line-map/status (WSMrtHomeContent).
                WSSegmented(options: ["Bus", "MRT"], selection: $mode)
                    .padding(.horizontal, 22).padding(.top, 14)
                    .wsEntrance(delay: 0.03)

                freshnessLine
                    .padding(.horizontal, 22).padding(.top, 12)
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
            ForEach(Array(busStops.prefix(6).enumerated()), id: \.element.stopCode) { i, stop in
                BusStopCard(stop: stop)
                    .padding(.horizontal, 22).padding(.top, 14)
                    .wsEntrance(delay: 0.06 + Double(i) * 0.04)
                // One native ad per board, in-feed after the second stop
                // card (moved up from below the mini-map card, which the
                // tab bar was covering — owner 2026-07-17). Renders
                // nothing until a creative loads.
                if i == 1 { NativeAdCard().padding(.horizontal, 22).padding(.top, 14) }
            }
            // Boards with 0–1 stops still get their one ad, below.
            if busStops.count < 2 {
                NativeAdCard().padding(.horizontal, 22).padding(.top, 14)
            }
        }
    }

    @ViewBuilder private var mrtContent: some View {
        if let item = nearbyStations.first {
            WSMrtHomeContent(station: item.station, distanceM: item.distanceM,
                             walkMin: item.walkMin)
                .padding(.top, 14)
            NativeAdCard().padding(.horizontal, 22).padding(.top, 14)
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
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
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
                // Same identity grammar as a departure row: a plate on the
                // left (here the stop code, mono — clearly a code, not a
                // number in prose), then exactly two text lines. The MRT
                // tiles sit inline after the name so an interchange never
                // adds a third line (owner 2026-07-17).
                HStack(spacing: 12) {
                    // Compact chip, not a big plate — the code is meta, the
                    // stop NAME is the identity (owner 2026-07-17: the old
                    // 64×42 pill was distracting).
                    WSCodeChip(text: stop.stopCode)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(stop.stopName)
                                .font(ws.sans(17, weight: .bold)).foregroundStyle(ws.text)
                                .lineLimit(1).layoutPriority(1)
                            mrtBadges
                        }
                        WalkLine(distanceM: stop.distanceM, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(stop.stopName)")

            // Visible bookmark, same trailing-action pattern as the MRT
            // station screen. Fills when saved.
            Button(action: togglePin) {
                WSIcon(glyph: isPinned ? .bookmarkFilled : .bookmark,
                       size: 18, color: isPinned ? ws.accent : ws.dim)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: isPinned)
            .accessibilityLabel(isPinned ? "Remove \(stop.stopName) from Saved"
                                         : "Save \(stop.stopName)")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // The card is the zoom source for the stop screen it opens (anim
        // spec: matched geometry — same treatment as the MRT card).
        .wsZoomSource(id: wsStopZoomID(stop.stopCode))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        var parts = ["Bus stop \(stop.stopName)"]
        if stop.distanceM > 0 {
            parts.append("\(max(1, Int((Double(stop.distanceM) / 80).rounded()))) minute walk")
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
        }
    }
    private var text: String {
        guard distanceM > 0 else { return "Nearby" }
        let walkMin = max(1, Int((Double(distanceM) / 80).rounded()))
        let dist = distanceM < 1000 ? "\(distanceM) meters"
                                    : String(format: "%.1f km", Double(distanceM) / 1000)
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
                                .font(ws.mono(10, weight: .bold)).foregroundStyle(ws.dim)
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
