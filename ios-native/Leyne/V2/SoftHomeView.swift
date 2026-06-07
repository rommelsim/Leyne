// SoftHomeView — Leyne Home ("Stops near you"): greeting + title with a
// filter/map action pair, a NEAR YOU · LIVE status line, then the single
// closest stop highlighted in its own "Closest to you" section, the rest
// under "Other nearby stops", and a live-updates footer. Each card shows the
// stop's identity and its soonest service's next three arrivals.

import SwiftUI
import MapKit
import UIKit

/// Identifies the stop a long-press "Arrival Alerts" sheet is open for.
private struct AlertTarget: Identifiable {
    let code: String
    var id: String { code }
}

struct SoftHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @StateObject private var loc = LocationManager.shared

    /// Line codes the user has tapped to dismiss this session. Cleared
    /// when the app cold-starts so a new disruption surfaces again.
    @State private var dismissedAlerts: Set<String> = []

    /// Drives the push to the central alerts list from the header bell.
    @State private var showAlerts = false

    /// Stop whose long-press "Arrival Alerts" sheet is open (nil = none).
    @State private var alertTarget: AlertTarget?

    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void
    let onOpenSearch: () -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

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
        // Long-press "Arrival Alerts" → stop-level sheet (targets the soonest bus).
        .sheet(item: $alertTarget) { target in
            StopAlertSheet(
                stopCode: target.code,
                stopName: ds.stopName(target.code),
                road: ds.roadName(target.code),
                onClose: { alertTarget = nil })
            .environmentObject(m)
            .environmentObject(fb)
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header / live row

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: greeting, t: t)
                Text("Stops near you")
                    .font(t.sans(33, weight: .bold))
                    .foregroundStyle(t.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            alertButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
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
                .frame(width: 42, height: 42)
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
            onTap: { fb.select(); m.addRecent(name); onOpenStop(code) }
        )
        // Long-press menu (matches the mockup): the card lifts as the preview.
        // Long-press → a peek of the stop (mini live-arrivals view) + actions.
        .contextMenu(menuItems: {
            Button {
                fb.select(); m.addRecent(name); onOpenStop(code)
            } label: {
                Label("Open Stop", systemImage: "arrow.up.forward")
            }
            Divider()
            Button {
                fb.select(); m.togglePin(code: code)
            } label: {
                Label(m.isPinned(code) ? "Remove from Saved" : "Add to Saved",
                      systemImage: m.isPinned(code) ? "star.slash" : "star")
            }
            Button {
                fb.select(); alertTarget = AlertTarget(code: code)
            } label: {
                Label("Arrival Alerts", systemImage: "bell")
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
            Button {
                fb.select(); shareStop(code: code, name: name)
            } label: {
                Label("Share Stop", systemImage: "square.and.arrow.up")
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

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
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

    var body: some View {
        let _ = tick
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if highlight { closestBadge.padding(.bottom, 12) }
                identityRow
                Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 12)
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
    private func arrivalRow(_ a: RankedArrival) -> some View {
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
                    .foregroundStyle(Color(hex: "F5B500"))
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
        .padding(.top, 2)
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
