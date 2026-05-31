// SoftHomeView — Leyne 3.0 Home: greeting + search bar + a live-location
// row, then two sections of StopCards — your Pinned stops, then Nearby
// stops — each previewing the next buses as confidence-treated mini-chips.
// The standalone Nearby tab folds in here. MRT disruption cards surface on
// top when present.

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

                    if !m.pins.isEmpty {
                        section(label: "Pinned") {
                            ForEach(m.pins, id: \.code) { pin in
                                pinnedCard(pin)
                            }
                        }
                    }

                    if !nearbyStops.isEmpty {
                        section(label: "Nearby") {
                            ForEach(nearbyStops.prefix(12), id: \.id) { stop in
                                nearbyCard(stop)
                            }
                        }
                    }

                    if m.pins.isEmpty && nearbyStops.isEmpty {
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

    // MARK: Header / search / live row

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: "\(greeting), Rommel", t: t)
            Text("Stops near you")
                .font(t.sans(30, weight: .semibold))
                .foregroundStyle(t.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var liveRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.dim)
            Text(loc.location != nil ? "NEAR YOU" : "LOCATION OFF")
                .font(t.mono(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(t.dim)
            if loc.location != nil {
                Circle().fill(t.accent).frame(width: 6, height: 6)
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
            Eyebrow(text: label, t: t).padding(.leading, 2)
            content()
        }
    }

    private func pinnedCard(_ pin: Pin) -> some View {
        SoftStopCard(
            t: t,
            name: stopName(pin.code),
            code: pin.code,
            desc: ds.roadName(pin.code),
            trailing: walkMinutes(for: pin.code).map { "\($0) min" },
            services: filteredServices(for: pin),
            feed: feed(pin.code),
            onTap: { fb.select(); onOpenStop(pin.code) }
        )
    }

    private func nearbyCard(_ stop: NearbyStop) -> some View {
        SoftStopCard(
            t: t,
            name: stop.stopName,
            code: stop.stopCode,
            desc: ds.roadName(stop.stopCode),
            trailing: fmtDistance(stop.distanceM),
            services: ds.servicesFor(stop.stopCode),
            feed: feed(stop.stopCode),
            onTap: { fb.select(); onOpenStop(stop.stopCode) }
        )
    }

    /// Nearby stops minus any already shown in the Pinned section, so a
    /// stop never appears twice.
    private var nearbyStops: [NearbyStop] {
        let pinned = Set(m.pins.map(\.code))
        return ds.nearby.filter { !pinned.contains($0.stopCode) }
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

    private func stopName(_ code: String) -> String {
        let n = ds.stopName(code)
        return n.isEmpty ? code : n
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
    }

    private func refreshAll() async {
        for pin in m.pins { await ds.refreshArrivals(stop: pin.code) }
        if let l = loc.location { ds.updateNearby(l) }
        ds.prefetchNearbyArrivals()
    }

    /// Walk-time (minutes) from the user to the stop. 80 m/min ≈ 5 km/h.
    private func walkMinutes(for code: String) -> Int? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[code] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return max(1, Int((d / 80).rounded()))
    }

    private func filteredServices(for pin: Pin) -> [Service] {
        let all = liveServices(for: pin.code)
        if let tracked = pin.tracked, !tracked.isEmpty {
            return all.filter { tracked.contains($0.no) }
        }
        return all
    }

    private func liveServices(for code: String) -> [Service] {
        if case .loaded(let s) = ds.arrivals[code] { return s }
        return []
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
