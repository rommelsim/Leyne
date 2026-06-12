// SoftHomeView — Leyne Home ("Stops near you"): a one-line greeting · clock ·
// weather context strip, the "Stops near you" title with an alerts bell, a
// compact LIVE status line, then the single closest stop (marked by its own
// "Closest stop" badge) followed by the rest under "More stops". Each card
// shows the stop's identity and its soonest service's next three arrivals.

import SwiftUI
import MapKit
import UIKit

struct SoftHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @StateObject private var loc = LocationManager.shared
    @ObservedObject private var ws = WeatherService.shared

    /// Line codes the user has tapped to dismiss this session. Cleared
    /// when the app cold-starts so a new disruption surfaces again.
    @State private var dismissedAlerts: Set<String> = []

    /// Drives the push to the central alerts list from the header bell.
    @State private var showAlerts = false

    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void
    let onOpenSearch: () -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            // A List (not a ScrollView) so each stop gets a native trailing
            // swipe action to Save/Remove — the same swipe affordance as the
            // Saved tab. Header + live row + MRT alerts ride as plain rows so
            // they scroll normally (no sticky section headers).
            List {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    liveRow
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                mrtAlertCards
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                let stops = nearbyStops
                if let closest = stops.first {
                    // The closest stop stands alone — its own "Closest stop"
                    // badge labels it, so no section header is needed.
                    stopCard(closest, highlight: true)
                    let others = Array(stops.dropFirst().prefix(11))
                    if !others.isEmpty {
                        Text("More stops")
                            .font(t.sans(15, weight: .semibold))
                            .foregroundStyle(t.dim)
                            .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 2, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        ForEach(others, id: \.id) { stopCard($0, highlight: false) }
                    }
                } else {
                    SoftEmptyState(t: t,
                                   onNearby: { loc.requestAndStart() },
                                   onSearch: { onOpenSearch() })
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Color.clear.frame(height: 24)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(t.bg)
            .refreshable { await refreshAll() }
        }
        .onAppear {
            warmArrivals()
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l) }
            ds.prefetchNearbyArrivals()
        }
        .onChange(of: m.pins) { _, _ in warmArrivals() }
        .onChange(of: loc.location) { _, new in
            if let l = new { ds.updateNearby(l); ds.prefetchNearbyArrivals() }
        }
        // Header bell → central alerts list, pushed onto the Home stack so it
        // keeps its own nav bar (title + Edit) and the swipe-back gesture.
        .navigationDestination(isPresented: $showAlerts) {
            ManageAlertsView().toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: Header / live row

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Weather + greeting + clock — degrades invisibly when
            // WeatherKit is unavailable (WeatherHeader shows only the
            // greeting row in that case).
            WeatherHeader(t: t)
                .padding(.horizontal, -16)  // bleed to scroll-view edge

            HStack(alignment: .center, spacing: 12) {
                Text("Stops near you")
                    .font(t.sans(33, weight: .bold))
                    .foregroundStyle(t.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                alertButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// Top-right bell → the central alerts list, with a count badge when the
    /// user has any alerts set.
    private var alertButton: some View {
        Button {
            fb.tap()
            showAlerts = true
        } label: {
            Image(systemName: "bell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 44, height: 44)
                .background(t.surface, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if !m.alerts.isEmpty {
                        Text("\(m.alerts.count)")
                            .font(t.sans(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(t.soon, in: Capsule())
                            .overlay(Capsule().stroke(t.bg, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.alerts.isEmpty ? "Alerts" : "Alerts, \(m.alerts.count) set")
    }

    private var liveRow: some View {
        let located = loc.location != nil
        return HStack(spacing: 6) {
            Image(systemName: located ? "location.fill" : "location.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(located ? t.meBlue : t.dim)
            if located {
                Circle().fill(t.soon).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(t.mono(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(t.dim)
            } else {
                Text("LOCATION OFF")
                    .font(t.mono(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }

    private func stopCard(_ stop: NearbyStop, highlight: Bool) -> some View {
        let code = stop.stopCode
        let name = stop.stopName.isEmpty ? code : stop.stopName
        return SoftNearbyStopCard(
            t: t,
            name: name,
            code: code,
            road: ds.roadName(code),
            walkMin: stop.walkMin,
            arrivals: rankedArrivals(code),
            feed: feed(code),
            highlight: highlight,
            tick: m.tick,
            onTap: { fb.select(); m.addRecent(name); onOpenStop(code) },
            isSaved: m.isPinned(code)
        )
        // Long-press menu (matches the mockup): the card lifts as the preview.
        // Long-press → a peek of the stop (mini live-arrivals view) + actions.
        .contextMenu(menuItems: {
            Button {
                fb.success(); m.togglePin(code: code)
            } label: {
                Label(m.isPinned(code) ? "Remove from Saved" : "Save stop",
                      systemImage: m.isPinned(code) ? "star.slash" : "star")
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
        }, preview: {
            stopPreview(code: code, name: name)
        })
        // Native trailing swipe → Save/Remove, identical to the Saved tab.
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                fb.success(); m.togglePin(code: code)
            } label: {
                Label(m.isPinned(code) ? "Remove" : "Save",
                      systemImage: m.isPinned(code) ? "star.slash.fill" : "star.fill")
            }
            // Swipe-action labels render white; tint with a real colour (not
            // t.soon, which is white in dark mode → invisible glyph).
            .tint(.green)
        }
    }

    // MARK: Context-menu actions

    /// Opens walking directions to the stop in Apple Maps (external handoff):
    /// Apple Maps draws a route from the user's current location to the stop.
    private func openOnMap(code: String, name: String) {
        guard let stop = ds.stopByCode[code] else { return }
        let coord = CLLocationCoordinate2D(latitude: stop.Latitude,
                                           longitude: stop.Longitude)
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        destination.name = name.isEmpty ? "Stop \(code)" : name
        MKMapItem.openMaps(
            with: [.forCurrentLocation(), destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ])
    }

    /// Nearby stops (closest first). Saved stops are kept — "nearby" means
    /// physically near you regardless of saved status (they also appear on the
    /// Saved tab). Only stops the user explicitly hid are dropped.
    private var nearbyStops: [NearbyStop] {
        let hidden = m.hiddenNearby
        return ds.nearby
            .filter { !hidden.contains($0.stopCode) }
            .sorted { $0.distanceM < $1.distanceM }
    }

    // MARK: MRT alerts (unchanged)

    @ViewBuilder
    private var mrtAlertCards: some View {
        let visible = ds.trainAlerts.filter { !dismissedAlerts.contains($0.id) }
        if !visible.isEmpty {
            VStack(spacing: 10) {
                ForEach(visible) { alert in
                    mrtAlertCard(alert)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: visible)
        }
    }

    private func mrtAlertCard(_ alert: TrainAlert) -> some View {
        Button {
            fb.select()
            withAnimation(.easeOut(duration: 0.2)) {
                _ = dismissedAlerts.insert(alert.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                MRTLineBar(color: alert.line?.color ?? t.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(t.sans(13, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(alert.detail)
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Data helpers

    private func feed(_ code: String) -> Freshness { Freshness.from(ds.lastRefresh(code)) }

    /// Top-3 services at a stop, ranked by the Home card's "what to show" rule:
    ///   1. Favourite buses first (saved at this stop OR anywhere),
    ///   2. then earliest arrival within each group,
    ///   3. capped at three so the card stays scannable.
    /// `liveServices` already returns the stop's services sorted by ETA, so a
    /// stable partition into favourites + the rest preserves the soonest-first
    /// order inside each group.
    /// A compact "peek" of a stop for the long-press preview — the stop name and
    /// its live arrivals (service no · crowd · ETA), like a miniature Stop view.
    private func stopPreview(code: String, name: String) -> some View {
        let services = m.liveServices(code: code, tracked: [])
            .sorted { $0.no.localizedStandardCompare($1.no) == .orderedAscending }
        let road = ds.roadName(code)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(t.sans(16, weight: .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                Text(road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)")
                    .font(t.mono(11))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle().fill(t.line).frame(height: 1)

            if services.isEmpty {
                Text("No live arrivals right now")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(services.prefix(7).enumerated()), id: \.element.id) { i, s in
                        let eta = fmtETA(s.etaSec)
                        if i > 0 {
                            Rectangle().fill(t.line).frame(height: 1).padding(.leading, 16)
                        }
                        HStack(spacing: 10) {
                            Text(s.no)
                                .font(t.mono(15, weight: .bold))
                                .foregroundStyle(t.fg)
                                .frame(minWidth: 42, alignment: .leading)
                            CrowdMeter(load: s.load, t: t, showLabel: false)
                            Spacer(minLength: 8)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(eta.big)
                                    .font(t.mono(15, weight: .bold))
                                    .foregroundStyle(eta.big == "Arr" ? t.soon : t.fg)
                                Text(eta.small)
                                    .font(t.sans(11))
                                    .foregroundStyle(t.dim)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .frame(width: 300)
        .background(t.surface)
    }

    private func rankedArrivals(_ code: String) -> [RankedArrival] {
        let services = m.liveServices(code: code, tracked: [])
        func isFav(_ s: Service) -> Bool {
            m.isFavService(no: s.no, stop: code) || m.isFavService(no: s.no, stop: nil)
        }
        let favs = services.filter(isFav)
        let rest = services.filter { !isFav($0) }
        return (favs + rest).prefix(3).map { RankedArrival(service: $0, fav: isFav($0)) }
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
    }

    private func refreshAll() async {
        for pin in m.pins { await ds.refreshArrivals(stop: pin.code) }
        if let l = loc.location { ds.updateNearby(l) }
        ds.prefetchNearbyArrivals()
    }

}

// MARK: - Nearby stop card

/// One ranked arrival on the Home card: a service plus whether the user has
/// favourited it (drives the leading star + the favourite-first ordering).
struct RankedArrival: Identifiable {
    let service: Service
    let fav: Bool
    var id: String { service.no }
}

/// A nearby-stop card: identity (pin · name · "Stop {code} · road") plus a
/// compact meta line (walk time + soonest arrival), with a trailing chevron.
/// Tapping anywhere opens the full stop view. The closest stop gets a green
/// border + badge.
struct SoftNearbyStopCard: View {
    let t: Theme
    let name: String
    let code: String
    let road: String
    let walkMin: Int
    let arrivals: [RankedArrival]
    let feed: Freshness
    let highlight: Bool
    let tick: Int            // forces a per-second live ETA recompute
    /// Tapping the card opens the full stop view — there is no inline expand.
    let onTap: () -> Void
    let isSaved: Bool

    var body: some View {
        let _ = tick
        return VStack(alignment: .leading, spacing: 0) {
            if highlight { closestBadge.padding(.bottom, 10) }
            headerRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(highlight ? t.soon : t.line, lineWidth: highlight ? 1.5 : 1))
    }

    /// The whole row is one tap target → opens the full stop view. A trailing
    /// chevron signals the navigation; there is no inline expand.
    private var headerRow: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                pinTile
                identityText
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(name)")
    }

    private var closestBadge: some View {
        Text("Closest stop")
            .font(t.sans(11, weight: .bold))
            .foregroundStyle(t.contrastFg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(t.soon, in: Capsule())
    }

    private var pinTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surfaceHi)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(t.fg)
        }
        .frame(width: 42, height: 42)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(name)
                    .font(t.sans(17, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Saved marker — pops in when the stop is saved (swipe / menu),
                // giving the save a visible, on-brand result.
                if isSaved {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.soon)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Saved")
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: isSaved)
            Text(subtitle)
                .font(t.mono(12.5))
                .foregroundStyle(t.dim)
                .lineLimit(1)
            // One tight meta line: walk time + the soonest arrival.
            compactMeta
        }
    }

    /// Single meta line: walk time + the soonest arrival, merged to save a
    /// whole row. The whisper "~" precedes an unconfirmed estimate, matching
    /// the app-wide honesty cue.
    @ViewBuilder
    private var compactMeta: some View {
        let soonest = arrivals.min(by: { $0.service.etaSec < $1.service.etaSec })
        let summary = soonest.flatMap {
            stopTeaser(count: arrivals.count, soonestEtaSec: $0.service.etaSec)
        }
        HStack(spacing: 5) {
            Image(systemName: "figure.walk")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.soon)
            Text("\(max(1, walkMin)) min")
                .foregroundStyle(t.soon)
            if let soonest, let summary {
                let conf = ArrivalConfidence.of(monitored: soonest.service.monitored, feed: feed)
                Text("·").foregroundStyle(t.faint)
                Image(systemName: "bus.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.dim)
                if conf == .unconfirmed {
                    Text("~").foregroundStyle(t.faint).accessibilityHidden(true)
                }
                Text(summary.whenText)
                    .foregroundStyle(t.fg)
            }
        }
        .font(t.mono(12, weight: .medium))
        .padding(.top, 1)
    }

    private var subtitle: String {
        road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)"
    }
}

// MARK: - EmptyState

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
