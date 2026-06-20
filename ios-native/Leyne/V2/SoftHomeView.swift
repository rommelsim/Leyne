// SoftHomeView — Glance Phase 1 departures board.
//
// Replaces the old "Stops near you" card list with a departures-first board:
//   • "Where to?" search field (button → switches to the Search tab, matching
//     the existing cross-tab navigation pattern in SoftRoot)
//   • Compact context line: greeting + LIVE dot
//   • Pinned stops first, then nearby stops — each as a stop section with a
//     header (name · walk · code · save star · optional alert dot) followed by
//     its DepartureCards. ETAs visible with zero taps.
//   • Skeleton while the first fetch is in-flight
//   • "Updated Xs ago" freshness stamp per stop section
//   • Contextual alert banner (only when an alert is present)
//
// Preserved from the old view:
//   • All existing @State, EnvironmentObjects, callbacks, navigation closures
//   • Live 1-second tick via m.tick
//   • Saved-stop fallback when GPS is off/denied
//   • Save/pin toggle, context-menu, swipe actions
//   • NativeAdCard placement, refreshable, .onAppear warm-up
//   • SoftEmptyState for the zero-stops case
//   • LocationNudge, openOnMap context-menu action
//
// Phase 1 adopts the new Glance tokens (t.brand, t.go, t.ink3, t.rounded(),
// glanceCard modifier). Other tabs/screens keep their existing tokens.

import SwiftUI
import MapKit
import UIKit

struct SoftHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @StateObject private var loc = LocationManager.shared

    /// Line codes the user has tapped to dismiss this session. Cleared
    /// when the app cold-starts so a new disruption surfaces again.
    @State private var dismissedAlerts: Set<String> = []

    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void
    let onOpenSearch: () -> Void
    /// Direct bus-detail push from a DepartureCard tap. Pushes `SoftRoute.bus`
    /// onto the Home stack so the user lands on the bus view, not the stop view.
    let onOpenBus: (String, String) -> Void  // (stopCode, serviceNo)
    // Phase 5 IA — replaces the Saved/Alerts/Settings tabs with sheet entry points
    // embedded in the search-bar row. Default no-op closures make these additive:
    // callers that don't supply them (e.g. legacy SoftRoot) compile unchanged.
    var onOpenSaved: (() -> Void)?    = nil
    var onOpenAlerts: (() -> Void)?   = nil
    var onOpenSettings: (() -> Void)? = nil

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            // A List preserves native trailing-swipe actions (Save/Remove) and
            // handles row insets cleanly across all content. Header rows and
            // MRT alert cards ride as plain rows so they scroll with the content.
            List {
                searchField
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                contextLine
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                mrtAlertCards
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                stopContent

                Color.clear.frame(height: 24)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Plain List reserves a chunk of default top content margin, which
            // read as dead space above the search bar. Zero it — the safe-area
            // inset still keeps the first row clear of the status bar / island.
            .contentMargins(.top, 0, for: .scrollContent)
            .background(t.bg)
            .refreshable { await refreshAll() }
        }
        .onAppear {
            warmArrivals()
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l); ds.prefetchNearbyArrivals() }
        }
        .onChange(of: m.pins) { _, _ in warmArrivals() }
        .onChange(of: loc.location) { _, new in
            if let l = new { ds.updateNearby(l); ds.prefetchNearbyArrivals() }
        }
    }

    // MARK: - Search field

    /// "Where to?" — a tappable search bar.
    /// Phase 5: Saved (star) + alerts bell + gear are embedded at the trailing
    /// edge inside the card, matching the prototype's searchbar__me avatar.
    /// When the Phase 5 callbacks are nil (legacy callers) the icons are hidden.
    private var searchField: some View {
        HStack(spacing: 0) {
            // Tappable search portion
            Button(action: { fb.select(); onOpenSearch() }) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.ink3)
                    Text("Where to?")
                        .font(t.sans(15, weight: .medium))
                        .foregroundStyle(t.ink3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for buses, stops, or stations")

            // Trailing action cluster (Phase 5 — only shown when callbacks are set)
            if onOpenSaved != nil || onOpenAlerts != nil || onOpenSettings != nil {
                HStack(spacing: 6) {
                    if let openSaved = onOpenSaved {
                        searchBarAction(icon: "star.fill", tint: t.brand) {
                            fb.select(); openSaved()
                        }
                        .accessibilityLabel("Saved stops and services")
                    }
                    if let openAlerts = onOpenAlerts {
                        ZStack(alignment: .topTrailing) {
                            searchBarAction(icon: "bell.fill", tint: t.fg) {
                                fb.select(); openAlerts()
                            }
                            if m.unseenAlertCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        .accessibilityLabel(m.unseenAlertCount > 0
                            ? "Alerts, \(m.unseenAlertCount) unseen" : "Alerts")
                    }
                    if let openSettings = onOpenSettings {
                        searchBarAction(icon: "gearshape.fill", tint: t.fg) {
                            fb.select(); openSettings()
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .padding(.trailing, 10)
            }
        }
        .glanceCard(fill: t.surface)
    }

    private func searchBarAction(icon: String,
                                  tint: Color,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(t.surfaceHi, in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Context line

    /// Compact "Good morning · LIVE" line. No duplicate clock — the old
    /// greetingClock is replaced by the simpler greeting + live badge.
    private var contextLine: some View {
        HStack(spacing: 8) {
            TimelineView(.everyMinute) { ctx in
                Text(greeting(for: ctx.date))
                    .font(t.sans(13, weight: .semibold))
                    .foregroundStyle(t.fg)
            }
            Spacer(minLength: 0)
            if loc.location == nil {
                Text("Location off")
                    .font(t.rounded(11, .bold))
                    .foregroundStyle(t.ink3)
                    .tracking(0.5)
            } else if !nearbyStops.isEmpty || !m.pins.isEmpty {
                // Only claim "LIVE" when there are actually stops whose arrivals
                // are flowing — not while the board is still empty/resolving
                // (location on but nothing to be live about yet).
                liveBadge
            }
        }
        .padding(.vertical, 2)
    }

    /// Pulsing green "LIVE" dot + text.
    private var liveBadge: some View {
        HStack(spacing: 5) {
            // Breathe animation — 2 s period, matching prototype `.live .dot`.
            // TimelineView drives a continuous repaint without a retained Timer.
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let opacity = 0.45 + 0.55 * (0.5 + 0.5 * sin(phase * .pi * 2 / 2.0))
                Circle()
                    .fill(t.go)
                    .frame(width: 7, height: 7)
                    .opacity(opacity)
            }
            Text("LIVE")
                .font(t.rounded(11, .bold))
                .foregroundStyle(t.go)
                .tracking(0.5)
        }
        .accessibilityLabel("Live arrivals active")
    }

    // MARK: - Stop content

    @ViewBuilder
    private var stopContent: some View {
        let nearby = nearbyStops
        let pinnedCodes = m.pins.map(\.code)

        if !pinnedCodes.isEmpty || !nearby.isEmpty {
            // Pinned stops float to the top — shown regardless of location.
            if !pinnedCodes.isEmpty {
                sectionHeader(title: "Saved", freshestCode: pinnedCodes.first)
                ForEach(pinnedCodes, id: \.self) { code in
                    stopSection(
                        code: code,
                        name: savedStopName(code),
                        walkMin: walkMin(code),
                        arrivals: rankedArrivals(code),
                        isPinned: true
                    )
                }
            }

            // Nearby stops (sorted by distance; excludes hidden).
            if !nearby.isEmpty {
                sectionHeader(title: "Nearby", freshestCode: nearby.first?.stopCode)
                ForEach(Array(nearby.enumerated()), id: \.element.id) { index, stop in
                    stopSection(
                        code: stop.stopCode,
                        name: stop.stopName.isEmpty ? stop.stopCode : stop.stopName,
                        walkMin: stop.walkMin,
                        arrivals: rankedArrivals(stop.stopCode),
                        isPinned: m.isPinned(stop.stopCode)
                    )
                    if index == 2 {
                        NativeAdCard()
                            .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                      bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if loc.location == nil && !pinnedCodes.isEmpty {
                // Location is off but saved stops are shown — prompt to enable.
                locationNudge
            }
        } else if !m.pins.isEmpty {
            // No nearby stops (location off) but has saved stops.
            let pins = m.pins
            sectionHeader(title: "Your stops", freshestCode: pins.first?.code)
            ForEach(Array(pins.enumerated()), id: \.element.code) { index, pin in
                stopSection(
                    code: pin.code,
                    name: savedStopName(pin.code),
                    walkMin: walkMin(pin.code),
                    arrivals: rankedArrivals(pin.code),
                    isPinned: true,
                    badgeLabel: index == 0 ? "Your stop" : nil
                )
                if index == 2 {
                    NativeAdCard()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                  bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            if loc.location == nil { locationNudge }
        } else {
            SoftEmptyState(t: t,
                           onNearby: { loc.requestAndStart() },
                           onSearch: { onOpenSearch() })
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Section headers

    /// A section label row ("Saved", "Nearby") with an "updated Xs ago" stamp.
    /// The stamp reads from the freshest stop in that section.
    private func sectionHeader(title: String, freshestCode: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(t.rounded(12, .bold))
                .foregroundStyle(t.ink3)
                .tracking(0.6)
            Spacer(minLength: 0)
            if let code = freshestCode, let stamp = updatedStamp(code) {
                Text(stamp)
                    .font(t.rounded(11, .semibold))
                    .foregroundStyle(t.ink3)
                    .monospacedDigit()
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Stop section

    /// One stop: a header row (name · walk · code · save star · alert dot)
    /// followed by its DepartureCards — ETAs visible with zero taps.
    @ViewBuilder
    private func stopSection(
        code: String,
        name: String,
        walkMin: Int,
        arrivals: [RankedArrival],
        isPinned: Bool,
        badgeLabel: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            // Stop header
            stopHeader(code: code, name: name, walkMin: walkMin, isPinned: isPinned)

            // Departure cards or skeleton
            let feed = feed(code)
            if arrivals.isEmpty && feed == .offline {
                // First load skeleton — 2 placeholder cards
                DepartureCardSkeleton(t: t)
                DepartureCardSkeleton(t: t)
            } else if arrivals.isEmpty {
                Text("No services right now")
                    .font(t.sans(13))
                    .foregroundStyle(t.ink3)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            } else {
                ForEach(arrivals.prefix(4)) { ranked in
                    let svc = ranked.service
                    let following = followingEtas(svc)
                    DepartureCard(
                        t: t,
                        service: svc,
                        stopCode: code,
                        feed: feed,
                        tick: m.tick,
                        followingEtas: following,
                        onTap: {
                            fb.select()
                            m.addRecent(name)
                            // Direct push to the bus detail (SoftRoute.bus) —
                            // matches the prototype's card tap behaviour.
                            onOpenBus(code, svc.no)
                        }
                    )
                }
            }
        }
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Trailing swipe to Save/Remove — same as the old card.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                fb.success(); m.togglePin(code: code)
            } label: {
                Label(isPinned ? "Remove" : "Save",
                      systemImage: isPinned ? "star.slash.fill" : "star.fill")
            }
            .tint(isPinned ? .red : .green)
        }
        .contextMenu(menuItems: {
            Button {
                fb.success(); m.togglePin(code: code)
            } label: {
                Label(isPinned ? "Remove from Saved" : "Save stop",
                      systemImage: isPinned ? "star.slash" : "star")
            }
            Button {
                fb.select(); openOnMap(code: code, name: name)
            } label: {
                Label("Open on Map", systemImage: "map")
            }
            Button {
                fb.success(); UIPasteboard.general.string = code
            } label: {
                Label("Copy Stop Code", systemImage: "doc.on.doc")
            }
        })
    }

    // MARK: - Stop header

    private func stopHeader(code: String, name: String, walkMin: Int, isPinned: Bool) -> some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(t.rounded(19, .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if walkMin > 0 {
                        Text("\(walkMin) min walk")
                            .font(t.sans(12.5, weight: .semibold))
                            .foregroundStyle(t.brand)
                    }
                    if walkMin > 0 {
                        Text("·")
                            .font(t.sans(12.5))
                            .foregroundStyle(t.ink3)
                    }
                    Text("Stop \(code)")
                        .font(t.sans(12.5))
                        .foregroundStyle(t.ink3)
                }
            }

            Spacer(minLength: 4)

            // Alert dot — visible if this stop has an active MRT/bus alert.
            if stopHasAlert(code: code) {
                Circle()
                    .fill(t.warn)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Service alert")
            }

            // Save / pin star — matches the prototype's `.stophead .pin`.
            Button {
                fb.success(); m.togglePin(code: code)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPinned ? t.brand : t.ink3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPinned)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Remove from saved" : "Save stop")
        }
        .padding(.top, 4)
    }

    // MARK: - MRT alert banner

    /// Contextual alert banner — only shown when there is an active dismissible alert.
    /// Rendered once at the top of the board (above stop sections), matching the
    /// prototype's single `.alert` card.
    @ViewBuilder
    private var mrtAlertCards: some View {
        let visible = ds.trainAlerts.filter { !dismissedAlerts.contains($0.id) }
        if !visible.isEmpty {
            VStack(spacing: 8) {
                ForEach(visible) { alert in
                    alertBanner(alert)
                }
            }
        }
    }

    private func alertBanner(_ alert: TrainAlert) -> some View {
        Button {
            fb.select()
            withAnimation(.easeOut(duration: 0.2)) {
                _ = dismissedAlerts.insert(alert.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                // Left accent bar — matches `.alert { border-left: 3px solid var(--warn) }`.
                Capsule()
                    .fill(t.warn)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(t.warnText)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(t.sans(13.5, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(alert.detail)
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glanceCard(fill: t.surface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location nudge (saved-stop fallback with location off)

    private var locationNudge: some View {
        Button {
            fb.select(); loc.requestAndStart()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.brand)
                Text("Turn on location for stops near you")
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.brand)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 5, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Data helpers

    /// Nearby stops (closest first), filtering out hidden stops.
    private var nearbyStops: [NearbyStop] {
        let hidden = m.hiddenNearby
        return ds.nearby
            .filter { !hidden.contains($0.stopCode) }
            .sorted { $0.distanceM < $1.distanceM }
    }

    /// Stop-level feed freshness. Exposed via DataStore.
    private func feed(_ code: String) -> Freshness { Freshness.from(ds.lastRefresh(code)) }

    /// "Updated 8s ago" stamp — nil when the stop has never been fetched.
    private func updatedStamp(_ code: String) -> String? {
        guard let last = ds.lastRefresh(code) else { return nil }
        let sec = Int(Date().timeIntervalSince(last))
        return "updated \(sec)s ago"
    }

    /// Whether a stop has any visible (undismissed) MRT alert.
    /// A per-stop bus-alert signal can be threaded in Phase 3; for now we
    /// surface the alert dot when any train alert is active — it's contextual,
    /// not stop-specific, and matches the prototype's `stop.alert` flag behaviour.
    private func stopHasAlert(code: String) -> Bool {
        !ds.trainAlerts.filter { !dismissedAlerts.contains($0.id) }.isEmpty
    }

    /// Top-4 services at a stop, ranked: favourites first, then earliest ETA.
    private func rankedArrivals(_ code: String) -> [RankedArrival] {
        let services = m.liveServices(code: code, tracked: [])
        func isFav(_ s: Service) -> Bool {
            m.isFavService(no: s.no, stop: code) || m.isFavService(no: s.no, stop: nil)
        }
        let favs = services.filter(isFav)
        let rest = services.filter { !isFav($0) }
        // Show up to 4 cards per stop to keep the board scannable.
        return (favs + rest).prefix(4).map { RankedArrival(service: $0, fav: isFav($0)) }
    }

    /// Following-bus ETAs for the "then X · Y min" sub-row. The Service model
    /// stores the next bus's `followingDate` and `thirdDate`; we convert those
    /// to seconds from now so DepartureCard can format them.
    private func followingEtas(_ svc: Service) -> [Int] {
        let now = Date()
        var result: [Int] = []
        if let d = svc.followingDate {
            result.append(max(0, Int(d.timeIntervalSince(now))))
        }
        if let d = svc.thirdDate {
            result.append(max(0, Int(d.timeIntervalSince(now))))
        }
        return result
    }

    private func savedStopName(_ code: String) -> String {
        let n = ds.stopName(code)
        return n.isEmpty ? code : n
    }

    /// Walk time in minutes to a stop, or 0 when location is unknown.
    private func walkMin(_ code: String) -> Int {
        guard let here = loc.location, let stop = ds.stopByCode[code] else { return 0 }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return max(1, Int((d / 80).rounded()))
    }

    /// Opens walking directions to the stop in Apple Maps.
    private func openOnMap(code: String, name: String) {
        guard let stop = ds.stopByCode[code] else { return }
        let coord = CLLocationCoordinate2D(latitude: stop.Latitude, longitude: stop.Longitude)
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        destination.name = name.isEmpty ? "Stop \(code)" : name
        MKMapItem.openMaps(
            with: [.forCurrentLocation(), destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ])
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
    }

    private func refreshAll() async {
        for pin in m.pins { await ds.refreshArrivals(stop: pin.code) }
        if let l = loc.location { ds.updateNearby(l) }
        ds.prefetchNearbyArrivals()
    }

    private func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }
}

// MARK: - RankedArrival (unchanged)

/// One ranked arrival on the Home board: a service plus whether the user has
/// favourited it (drives the favourite-first ordering).
struct RankedArrival: Identifiable {
    let service: Service
    let fav: Bool
    var id: String { service.no }
}

// MARK: - EmptyState (unchanged)

struct SoftEmptyState: View {
    let t: Theme
    let onNearby: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(t.accent)
                .frame(width: 64, height: 64)
                .background(t.liveBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("No stops yet")
                .font(t.sans(20, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Turn on location to see stops near you, or search for one.")
                .font(t.sans(13))
                .foregroundStyle(t.dim)

            HStack(spacing: 8) {
                Button(action: onNearby) {
                    Text("Use location")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(t.accent, in: Capsule())
                }.buttonStyle(.plain)
                Button(action: onSearch) {
                    Text("Search")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().stroke(t.line, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
