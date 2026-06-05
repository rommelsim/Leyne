// SoftHomeView — Leyne Home ("Stops near you"): greeting + title with a
// filter/map action pair, a NEAR YOU · LIVE status line, then the single
// closest stop highlighted in its own "Closest to you" section, the rest
// under "Other nearby stops", and a live-updates footer. Each card shows the
// stop's identity and its soonest service's next three arrivals.

import SwiftUI

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
    }

    // MARK: Header / live row

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: greeting, t: t)
            Text("Stops near you")
                .font(t.sans(33, weight: .bold))
                .foregroundStyle(t.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
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
        return SoftNearbyStopCard(
            t: t,
            name: stop.stopName.isEmpty ? code : stop.stopName,
            code: code,
            road: ds.roadName(code),
            walkMin: stop.walkMin,
            distanceM: stop.distanceM,
            service: featured(code),
            feed: feed(code),
            highlight: highlight,
            tick: m.tick,
            onTap: { fb.select(); m.addRecent(stop.stopName.isEmpty ? code : stop.stopName)
                     onOpenStop(code) }
        )
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

    /// Nearby stops (closest first). Pins are excluded — they live on the
    /// Favourites tab.
    private var nearbyStops: [NearbyStop] {
        let pinned = Set(m.pins.map(\.code))
        return ds.nearby
            .filter { !pinned.contains($0.stopCode) }
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

    /// The soonest live-recomputed service at a stop — the card's featured row.
    private func featured(_ code: String) -> Service? {
        m.liveServices(code: code, tracked: []).first
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

/// A nearby-stop card: identity (pin · name · "Stop {code} · road" · walk +
/// distance) over a divider, then the soonest service's next three arrivals in
/// columns. The closest stop is highlighted with a green border + badge.
struct SoftNearbyStopCard: View {
    let t: Theme
    let name: String
    let code: String
    let road: String
    let walkMin: Int
    let distanceM: Int
    let service: Service?
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
                if let service { serviceRow(service) } else { quietRow }
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
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(t.faint)
        }
    }

    private var subtitle: String {
        road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)"
    }

    private func serviceRow(_ s: Service) -> some View {
        let conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed)
        let badge = serviceBadgeColors(etaSec: s.etaSec, confidence: conf, t: t)
        return HStack(spacing: 12) {
            Text(s.no)
                .font(t.sans(17, weight: .bold))
                .foregroundStyle(badge.fg)
                .lineLimit(1)
                .frame(minWidth: 46, minHeight: 40)
                .padding(.horizontal, 8)
                .background(badge.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(destLabel(s.dest))
                .font(t.sans(14, weight: .medium))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            etaColumns(s, confidence: conf)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    /// Up to three arrival columns ("6 · 18 · 29 min") split by hairlines. The
    /// lead column carries proximity colour + a live signal; the rest are ink.
    private func etaColumns(_ s: Service, confidence: ArrivalConfidence) -> some View {
        let etas = arrivalSecs(s)
        return HStack(spacing: 0) {
            ForEach(Array(etas.enumerated()), id: \.offset) { i, sec in
                if i > 0 {
                    Rectangle().fill(t.line).frame(width: 1, height: 30)
                        .padding(.horizontal, 10)
                }
                etaColumn(sec, lead: i == 0, confidence: confidence)
            }
        }
    }

    private func etaColumn(_ sec: Int, lead: Bool, confidence: ArrivalConfidence) -> some View {
        let eta = fmtETA(sec)
        let arriving = eta.big == "Arr"
        let color = lead ? etaColor(etaSec: sec, confidence: confidence, t: t) : t.fg
        let ghost = confidence == .unconfirmed
        return VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if ghost {
                    Text("~").font(t.mono(11, weight: .regular))
                        .foregroundStyle(t.faint).accessibilityHidden(true)
                }
                Text(arriving ? "Arr" : eta.big)
                    .font(t.mono(20, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if lead && confidence == .live {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.soon)
                        .offset(y: -7)
                        .accessibilityHidden(true)
                }
            }
            Text(arriving ? "now" : eta.small)
                .font(t.mono(10))
                .foregroundStyle(t.dim)
        }
        .frame(minWidth: 34)
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

    /// 1–3 upcoming arrival times (seconds), dropping any that aren't real.
    private func arrivalSecs(_ s: Service) -> [Int] {
        var out = [s.etaSec]
        if s.followingSec > s.etaSec { out.append(s.followingSec) }
        if let d = s.thirdDate {
            let third = Int(d.timeIntervalSinceNow)
            if third > (out.last ?? 0) { out.append(max(0, third)) }
        }
        return out
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
