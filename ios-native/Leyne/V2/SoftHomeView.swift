// SoftHomeView — Leyne Home ("Stops near you"): weather + greeting + title
// with a filter/map action pair, a NEAR YOU · LIVE status line, then the
// single closest stop highlighted in its own "Closest to you" section, the
// rest under "Other nearby stops", and a live-updates footer. Each card shows
// the stop's identity and its soonest service's next three arrivals.

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

    /// Active arrival-alert toast (one-tap "Arrival Alerts" from the long-press
    /// menu), nil when none is showing.
    @State private var alertToast: ArrivalAlertToastState?

    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void
    let onOpenSearch: () -> Void
    /// Direct bus-chip tap on a nearby card → straight to the Bus card.
    let onOpenBus: (String, String) -> Void
    let onOpenSaved: () -> Void
    let onOpenSettings: () -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            // Ambient weather tint — a sub-conscious wash from the top of the
            // screen that makes the home feel like *now* (warm when clear,
            // cool-grey when raining). Felt, not seen; never blocks content.
            WeatherAmbientLayer(bucket: ws.snapshot?.bucket, isDark: t.isDark)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    liveRow
                    mrtAlertCards

                    let stops = nearbyStops
                    if let closest = stops.first {
                        section(label: "Closest to you") {
                            stopCard(closest, highlight: true)
                        }
                        let others = Array(stops.dropFirst().prefix(11))
                        if !others.isEmpty {
                            section(label: "Other nearby stops") {
                                ForEach(others, id: \.id) { stopCard($0, highlight: false) }
                            }
                        }
                        liveUpdatesBanner
                    } else {
                        SoftEmptyState(t: t,
                                       onNearby: { loc.requestAndStart() },
                                       onSearch: { onOpenSearch() })
                            .padding(.top, 4)
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
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
        // Long-press "Arrival Alerts" arms the soonest bus in ONE tap (no sheet);
        // a toast with Undo confirms it.
        .arrivalAlertToastOverlay(state: $alertToast, t: t)
    }

    /// One-tap "Arrival Alerts" (long-press menu): arm the stop's soonest live
    /// bus and confirm with an Undo toast. Falls back to opening the stop when
    /// nothing is live yet so the user can still pick a bus (Android parity).
    private func quickArrivalAlert(code: String) {
        ds.ensureArrivals(stop: code)
        guard let soonest = m.liveServices(code: code, tracked: []).first else {
            onOpenStop(code)
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            alertToast = m.toggleArrivalAlertWithToast(
                busNo: soonest.no, stopCode: code,
                stopName: ds.stopName(code), dest: soonest.dest)
        }
    }

    // MARK: Header / live row

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Weather + greeting + clock — degrades invisibly when
            // WeatherKit is unavailable (WeatherHeader shows only the
            // greeting row in that case).
            WeatherHeader(t: t)
                .padding(.horizontal, -16)  // bleed to scroll-view edge

            // The app's single command row: search field + alerts + Saved +
            // Settings, all on one line so the corner doesn't read as a
            // stray stack of circles. The title row below stays clean.
            HStack(spacing: 9) {
                searchField
                alertButton
                headerIconButton("star.fill", label: "Saved",
                                 action: onOpenSaved)
                headerIconButton("gearshape.fill", label: "Settings",
                                 action: onOpenSettings)
            }

            Text("Stops near you")
                .font(t.sans(33, weight: .bold))
                .foregroundStyle(t.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// The search field — visually a field, behaviourally a button that
    /// raises the Search card (which owns the real keyboard focus).
    private var searchField: some View {
        Button {
            fb.tap(); onOpenSearch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.dim)
                Text("Search")
                    .font(t.sans(14))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .leyneGlass(in: Capsule(), theme: t)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search buses, stops, or postal codes")
        .accessibilityAddTraits(.isSearchField)
    }

    /// 42pt glass circle button for the header row (Saved / Settings).
    private func headerIconButton(_ symbol: String, label: String,
                                  action: @escaping () -> Void) -> some View {
        Button {
            fb.tap(); action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 42, height: 42)
                .leyneGlass(in: Circle(), theme: t)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Top-right bell → the central alerts list, with a count badge when the
    /// user has any alerts set.
    private var alertButton: some View {
        Button {
            fb.tap()
            showAlerts = true
        } label: {
            Image(systemName: "bell.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 42, height: 42)
                .leyneGlass(in: Circle(), theme: t)
                .overlay(alignment: .topTrailing) {
                    if !m.alerts.isEmpty {
                        Text("\(m.alerts.count)")
                            .font(t.sans(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(t.identity, in: Capsule())
                            .overlay(Capsule().stroke(t.bg, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.alerts.isEmpty ? "Alerts" : "Alerts, \(m.alerts.count) set")
    }

    private var liveRow: some View {
        let located = loc.location != nil
        return HStack(spacing: 7) {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(located ? t.meBlue : t.dim)
            Text(located ? "NEAR YOU" : "LOCATION OFF")
                .font(t.mono(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(located ? t.meBlue : t.dim)
            if located {
                Circle().fill(t.soon).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(t.mono(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }

    // MARK: Sections

    @ViewBuilder
    private func section<Content: View>(label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
                .padding(.leading, 2)
            content()
        }
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
            distanceM: stop.distanceM,
            arrivals: rankedArrivals(code),
            feed: feed(code),
            highlight: highlight,
            tick: m.tick,
            onTap: { fb.select(); m.addRecent(name); onOpenStop(code) },
            // Bus rows deep-tap straight into the Bus card — no Stop hop.
            onOpenBus: { svc in
                fb.select(); m.addRecent(name); onOpenBus(code, svc)
            }
        )
        // Long-press → a peek of the stop (mini live-arrivals view) + a SHORT
        // action list: the two decisions a commuter actually makes here (save,
        // alert), with the occasional utilities folded into one "More"
        // submenu. Tapping the peek itself opens the stop, so no "Open Stop"
        // row. Hide stays separate + destructive at the bottom.
        .contextMenu(menuItems: {
            Button {
                fb.select(); m.togglePin(code: code)
            } label: {
                Label(m.isPinned(code) ? "Remove from Saved" : "Add to Saved",
                      systemImage: m.isPinned(code) ? "star.slash" : "star")
            }
            Button {
                fb.select(); quickArrivalAlert(code: code)
            } label: {
                Label("Arrival Alerts", systemImage: "bell")
            }
            Menu {
                Button {
                    fb.select(); openOnMap(code: code, name: name)
                } label: {
                    Label("Open on Map", systemImage: "map")
                }
                Button {
                    fb.select(); shareStop(code: code, name: name)
                } label: {
                    Label("Share Stop", systemImage: "square.and.arrow.up")
                }
                Button {
                    fb.success(); UIPasteboard.general.string = code
                } label: {
                    Label("Copy Stop Code", systemImage: "doc.on.doc")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            Divider()
            Button(role: .destructive) {
                fb.select(); m.hideFromNearby(code: code)
            } label: {
                Label("Hide From Nearby", systemImage: "eye.slash")
            }
        }, preview: {
            stopPreview(code: code, name: name)
        })
    }

    // MARK: Context-menu actions

    /// Opens the stop's location in Apple Maps (external handoff).
    private func openOnMap(code: String, name: String) {
        guard let stop = ds.stopByCode[code] else { return }
        let coord = CLLocationCoordinate2D(latitude: stop.Latitude,
                                           longitude: stop.Longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = name.isEmpty ? "Stop \(code)" : name
        item.openInMaps()
    }

    /// Shares the stop as text + a universal link (lyne.sg/stop/<code>) so the
    /// recipient can deep-link straight into it. Presents from the top-most VC.
    private func shareStop(code: String, name: String) {
        let label = name.isEmpty ? "Stop \(code)" : "\(name) (Stop \(code))"
        let text = "\(label) — track arrivals on Leyne https://lyne.sg/stop/\(code)"
        let av = UIActivityViewController(activityItems: [text],
                                          applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        av.popoverPresentationController?.sourceView = top.view
        top.present(av, animated: true)
    }

    private var liveUpdatesBanner: some View {
        Button { fb.tap(); Task { await refreshAll() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.soon)
                (Text("Live updates  ").font(t.sans(13, weight: .semibold)).foregroundColor(t.fg)
                 + Text("Arrival times update every few seconds.")
                    .font(t.sans(13)).foregroundColor(t.dim))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Live updates. Arrival times update every few seconds. Tap to refresh.")
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
    /// The long-press "peek" of a stop — a miniature Stop view speaking the
    /// app's full card language: identity header (map-pin tile, name, code ·
    /// road, walk + LIVE signal), then surface-card arrival rows with
    /// proximity-tinted service badges, destination, crowding, and a coloured
    /// ETA — not a bare wireframe list.
    private func stopPreview(code: String, name: String) -> some View {
        let services = m.liveServices(code: code, tracked: [])
            .sorted { $0.etaSec < $1.etaSec }
        let road = ds.roadName(code)
        let fresh = feed(code)
        let nearby = ds.nearby.first { $0.stopCode == code }
        return VStack(alignment: .leading, spacing: 0) {
            // ── Identity header — quotes SoftNearbyStopCard's identityRow ──
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(t.surfaceHi)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.fg)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(t.sans(16, weight: .bold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    Text(road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                    if let nearby {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(max(1, nearby.walkMin)) min walk")
                            Text("·").foregroundStyle(t.faint)
                            Text(fmtDistance(nearby.distanceM)).foregroundStyle(t.dim)
                        }
                        .font(t.mono(11, weight: .medium))
                        .foregroundStyle(t.soon)
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 8)
                if fresh == .live {
                    HStack(spacing: 4) {
                        Circle().fill(t.soon).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(t.mono(9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(t.soon)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // ── Arrival rows — surface cards, same language as Stop view ──
            if services.isEmpty {
                HStack(spacing: 7) {
                    ConfidenceDot(confidence: .stale, t: t, size: 6)
                    Text("No live arrivals right now")
                        .font(t.mono(12))
                        .foregroundStyle(t.faint)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(t.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(services.prefix(5).enumerated()), id: \.element.id) { _, s in
                        previewArrivalRow(s, fresh: fresh)
                    }
                    if services.count > 5 {
                        Text("+\(services.count - 5) more — tap to open")
                            .font(t.mono(11))
                            .foregroundStyle(t.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 330)
        .background(t.bg)
    }

    /// One arrival row inside the long-press peek: proximity-tinted service
    /// badge · destination + crowding · coloured ETA.
    private func previewArrivalRow(_ s: Service, fresh: Freshness) -> some View {
        let conf = ArrivalConfidence.of(monitored: s.monitored, feed: fresh)
        let badge = serviceBadgeColors(etaSec: s.etaSec, confidence: conf, t: t)
        let eta = fmtETA(s.etaSec)
        let arriving = eta.big == "Arr"
        return HStack(spacing: 11) {
            ServiceBadge(svc: s.no, t: t, size: .md,
                         fillOverride: badge.fill, fgOverride: badge.fg)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.dest.isEmpty ? "Bus \(s.no)" : "To \(s.dest)")
                    .font(t.sans(13, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                CrowdMeter(load: s.load, t: t, showLabel: false)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if conf == .unconfirmed {
                    Text("~").font(t.mono(11))
                        .foregroundStyle(t.faint)
                }
                Text(arriving ? "Arr" : eta.big)
                    .font(t.mono(18, weight: .semibold))
                    .foregroundStyle(etaColor(etaSec: s.etaSec, confidence: conf, t: t))
                Text(arriving ? "now" : eta.small)
                    .font(t.mono(10))
                    .foregroundStyle(t.dim)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(t.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

/// A nearby-stop card: identity (pin · name · "Stop {code} · road" · walk +
/// distance) over a divider, then the stop's top-3 services — favourites first,
/// then soonest — each on its own row with its next arrival. A "View all buses"
/// footer opens the full stop. The closest stop gets a green border + badge.
struct SoftNearbyStopCard: View {
    let t: Theme
    let name: String
    let code: String
    let road: String
    let walkMin: Int
    let distanceM: Int
    let arrivals: [RankedArrival]
    let feed: Freshness
    let highlight: Bool
    let tick: Int            // forces a per-second live ETA recompute
    let onTap: () -> Void
    /// When set, each arrival row is its own tap target → opens that bus
    /// directly (the rest of the card still opens the stop).
    var onOpenBus: ((String) -> Void)? = nil

    var body: some View {
        let _ = tick
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if highlight { closestBadge.padding(.bottom, 12) }
                identityRow
                Rectangle().fill(t.line).frame(height: 1)
                    .padding(.vertical, 14)
                if arrivals.isEmpty {
                    quietRow
                } else {
                    VStack(spacing: 12) {
                        ForEach(arrivals) { arrivalRow($0) }
                    }
                    viewAllRow
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(highlight ? t.soon : t.line, lineWidth: highlight ? 1.5 : 1))
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

    private var identityRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surfaceHi)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.fg)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(t.sans(17, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(t.mono(12.5))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.soon)
                    Text("\(max(1, walkMin)) min walk")
                        .foregroundStyle(t.soon)
                    Text("·").foregroundStyle(t.faint)
                    Text(fmtDistance(distanceM)).foregroundStyle(t.dim)
                }
                .font(t.mono(12.5, weight: .medium))
                .padding(.top, 1)
            }
            Spacer(minLength: 4)
        }
    }

    private var subtitle: String {
        road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)"
    }

    /// One ranked service: number badge (proximity-tinted), a gold star when
    /// favourited, the destination, then its soonest arrival on the trailing
    /// edge. Matches the "Top 3 arrivals" rows in the spec.
    @ViewBuilder
    private func arrivalRow(_ a: RankedArrival) -> some View {
        if let onOpenBus {
            // Nested inside the card's outer Button — SwiftUI routes taps on
            // the inner button to it alone, so the row opens the bus while
            // the rest of the card still opens the stop.
            Button {
                onOpenBus(a.service.no)
            } label: {
                arrivalRowContent(a).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bus \(a.service.no). Opens the bus directly.")
        } else {
            arrivalRowContent(a)
        }
    }

    private func arrivalRowContent(_ a: RankedArrival) -> some View {
        let s = a.service
        let conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed)
        let badge = serviceBadgeColors(etaSec: s.etaSec, confidence: conf, t: t)
        return HStack(spacing: 10) {
            Text(s.no)
                .font(t.sans(16, weight: .bold))
                .foregroundStyle(badge.fg)
                .lineLimit(1)
                .frame(minWidth: 46, minHeight: 36)
                .padding(.horizontal, 6)
                .background(badge.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            if a.fav {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .accessibilityLabel("Favourite")
            }
            Text(destLabel(s.dest))
                .font(t.sans(14, weight: .medium))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            etaTrailing(s.etaSec, confidence: conf)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    /// The single soonest arrival, trailing-aligned: proximity-tinted "Arr"
    /// (with a live signal) or "{n} min". A faint "~" precedes an unconfirmed
    /// estimate — the whisper-quiet honesty cue used app-wide.
    private func etaTrailing(_ sec: Int, confidence: ArrivalConfidence) -> some View {
        let eta = fmtETA(sec)
        let arriving = eta.big == "Arr"
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            if confidence == .unconfirmed {
                Text("~").font(t.mono(13, weight: .regular))
                    .foregroundStyle(t.faint).accessibilityHidden(true)
            }
            Text(arriving ? "Arr" : eta.big)
                .font(t.mono(19, weight: .semibold))
                .foregroundStyle(etaColor(etaSec: sec, confidence: confidence, t: t))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if arriving {
                if confidence == .live {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.soon)
                        .offset(y: -6)
                        .accessibilityHidden(true)
                }
            } else {
                Text(eta.small)
                    .font(t.mono(11))
                    .foregroundStyle(t.dim)
            }
        }
    }

    /// "View all buses" footer with a leading hairline — the tappable cue that
    /// opens the full stop (the whole card shares the same action).
    private var viewAllRow: some View {
        HStack(spacing: 6) {
            Text("View all buses")
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.faint)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(t.line).frame(height: 1)
        }
        // Gap between the last bus pill and this divider (was 2 → pill bottom
        // touched the line above "View all buses").
        .padding(.top, 14)
    }

    private var quietRow: some View {
        HStack(spacing: 7) {
            ConfidenceDot(confidence: .stale, t: t, size: 6)
            Text("No live arrivals right now")
                .font(t.mono(12))
                .foregroundStyle(t.faint)
            Spacer(minLength: 0)
        }
    }

    private func destLabel(_ dest: String) -> String {
        dest.isEmpty ? "Next bus" : (dest.hasPrefix("To ") ? dest : "To \(dest)")
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
