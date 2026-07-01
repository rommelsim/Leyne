// Home — the departures-first main view (iOS). A header (nearest stop + crowd
// chip) over a scrolling sheet: a transfer-to-MRT card, then the live-arrivals
// list with a Time / Bus-number sort and an expandable "see all".

import SwiftUI

struct RDHomeScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var loc: LocationManager
    @State private var pump: Timer?
    @State private var requested: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            sheet
        }
        .background(t.surface)
        .onAppear {
            loc.startIfAuthorized()
            store.prefetchNearbyArrivals()
            startPump()
        }
        .onDisappear { stopPump() }
    }

    // Keeps the nearby stops' live arrivals warm — a few stops per tick so the
    // list stays current without bursting LTA's rate limit (mirrors NearbyView).
    private func startPump() {
        stopPump()
        pump = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                var fired = 0
                for s in store.nearby where fired < 3 {
                    if requested.insert(s.stopCode).inserted {
                        store.ensureArrivals(stop: s.stopCode, silent: true); fired += 1
                    }
                }
                if let code = m.currentNearby?.stopCode {
                    store.ensureArrivals(stop: code)
                }
            }
        }
    }

    private func stopPump() { pump?.invalidate(); pump = nil }

    // MARK: header

    private var header: some View {
        let stop = m.currentStop
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Title block — plain text. Finding / switching stops is now an
                // explicit search button on the right, not a hidden tap on the
                // title (the chevron is gone).
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEAREST STOP")
                        .font(rdFont(11, .bold)).kerning(0.7).foregroundStyle(t.onVariant)
                    HStack(spacing: 7) {
                        Text(stop.name)
                            .font(rdFont(30, .heavy)).foregroundStyle(t.onSurface)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        RDMrtBadgeRow(stopName: stop.name)
                    }
                    Text(headerSubtitle)
                        .font(rdFont(13, .medium)).foregroundStyle(t.onVariant)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Lighter, toolbar-style actions — plain SF Symbols, no circle
                // chrome (the bordered circles read as heavy stacked together).
                HStack(spacing: 6) {
                    RDCircleButton(symbol: "magnifyingglass", bordered: false, iconColor: t.onVariant, t: t) { m.go("switch") }
                    saveButton
                    RDCircleButton(symbol: "person.crop.circle", bordered: false, iconColor: t.onVariant, t: t) { m.go("settings") }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8).padding(.bottom, 14)
            hairline
        }
    }

    /// Quiet supporting line under the stop title: distance + walk + code, folded
    /// into one caption (replaces the old bordered "Stop NNNNN" pill).
    private var headerSubtitle: String {
        guard let n = m.currentNearby, !m.currentStop.code.isEmpty else {
            return m.currentStop.dist   // e.g. "Waiting for your location"
        }
        if n.distanceM <= 40 { return "You're at this stop · Stop \(n.stopCode)" }
        return "\(fmtDistance(n.distanceM)) away · \(n.walkMin) min walk · Stop \(n.stopCode)"
    }

    // Thin dividers do the organising work instead of cards. A full-bleed line
    // separates sections; an inset line (aligned under the row text) separates
    // items within the arrivals list — the Apple Maps / Settings grouping idiom.
    private var hairline: some View { Rectangle().fill(t.outlineVariant).frame(height: 1) }
    private var insetHairline: some View {
        Rectangle().fill(t.outlineVariant).frame(height: 1).padding(.leading, 78)
    }

    private var saveButton: some View {
        RDSym(m.stopSaved ? "bookmark.fill" : "bookmark", size: 22, color: m.stopSaved ? t.primary : t.onVariant)
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .onTapGesture { m.toggleSaveStop() }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                m.notify("Opening saved stops"); m.go("saved")
            })
    }

    // MARK: sheet

    private var sheet: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                mrtRow
                liveSection
                nearbyStationsSection
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: Nearby MRT stations — real, tappable context that fills the lower area

    @ViewBuilder private var nearbyStationsSection: some View {
        if let here = loc.location {
            let near = MrtGeo.nearestStations(to: here.coordinate, limit: 3, withinMeters: 1500)
            if !near.isEmpty {
                hairline
                HStack {
                    Text("NEARBY STATIONS").font(rdFont(11, .heavy)).kerning(0.66).foregroundStyle(t.onVariant)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
                ForEach(Array(near.enumerated()), id: \.element.station.id) { idx, item in
                    if idx > 0 { insetHairline }
                    stationRow(item.station, walkMin: item.walkMin)
                }
            }
        }
    }

    private func stationRow(_ st: MrtGeoStation, walkMin: Int) -> some View {
        let lineColor = st.codes.first.map { mrtLineColorFor($0) } ?? t.transferOrange
        return Button(action: { m.openStation(named: st.name) }) {
            HStack(spacing: 14) {
                RDSym("tram.fill", size: 16, color: lineColor)
                    .frame(width: 46, height: 38)
                    .background(t.scHigh).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(st.name).font(rdFont(16, .semibold)).foregroundStyle(t.onSurface).lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(st.codes.prefix(3), id: \.self) { c in
                            Text(c).font(rdFont(9, .heavy)).foregroundStyle(rdMrtBadgeFg(c))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(mrtLineColorFor(c))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(walkMin) min walk").font(rdFont(12.5, .medium)).foregroundStyle(t.onVariant)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: MRT — one quiet row, not a competing card

    @ViewBuilder private var mrtRow: some View {
        if let nm = m.nearestMrt {
            let st = nm.station
            let lineColor = st.codes.first.map { mrtLineColorFor($0) } ?? t.transferOrange
            let lineName = st.codes.first.flatMap { MRTLine(rawValue: String($0.prefix(2)).uppercased())?.displayName }
            Button(action: { m.openStation(named: st.name) }) {
                HStack(spacing: 11) {
                    // A thin line-coloured bar is the whole MRT accent.
                    Capsule().fill(lineColor).frame(width: 3.5, height: 30)
                    RDSym("tram.fill", size: 18, color: lineColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(st.name).font(rdFont(15.5, .semibold)).foregroundStyle(t.onSurface).lineLimit(1)
                        Text(lineName.map { "\($0) Line" } ?? "MRT station")
                            .font(rdFont(11.5, .medium)).foregroundStyle(lineColor)
                    }
                    Spacer(minLength: 8)
                    Text("\(nm.walkMin) min walk").font(rdFont(12.5, .medium)).foregroundStyle(t.onVariant)
                    RDSym("chevron.right", size: 15, color: t.outline)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            hairline
        }
    }

    // MARK: Live arrivals

    @ViewBuilder private var liveSection: some View {
        HStack(spacing: 7) {
            if isFresh { RDDot(color: t.bus) }
            Text("LIVE ARRIVALS").font(rdFont(11, .heavy)).kerning(0.66).foregroundStyle(t.onVariant)
            if !isFresh, let stale = staleLabel {
                Text("· \(stale)").font(rdFont(11, .medium)).foregroundStyle(t.onVariant)
            }
            Spacer()
            sortToggle
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)

        if m.visibleArrivals.isEmpty {
            Text("No live arrivals right now")
                .font(rdFont(13.5, .medium)).foregroundStyle(t.onVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 22)
        } else {
            ForEach(Array(m.visibleArrivals.enumerated()), id: \.element.id) { idx, a in
                if idx > 0 { insetHairline }
                arrivalRow(a)
            }
            if m.canExpandArrivals {
                hairline
                showAllRow
            }
        }
    }

    /// Minimal text sort — no filled segmented surface. Active option in primary.
    private var sortToggle: some View {
        HStack(spacing: 12) {
            sortText("Time", "eta")
            sortText("Bus no.", "number")
        }
    }

    private func sortText(_ label: String, _ key: String) -> some View {
        let active = m.sortBy == key
        return Button(action: { withAnimation(.easeOut(duration: 0.18)) { m.setSort(key) } }) {
            Text(label).font(rdFont(12, active ? .bold : .medium))
                .foregroundStyle(active ? t.primary : t.onVariant)
        }
        .buttonStyle(.plain)
    }

    private var showAllRow: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.25)) { m.toggleArrivals() } }) {
            HStack(spacing: 6) {
                Text(m.arrivalsExpanded ? "Show fewer" : "Show all \(m.sortedArrivals.count) arrivals")
                    .font(rdFont(13.5, .semibold)).foregroundStyle(t.primary)
                RDSym(m.arrivalsExpanded ? "chevron.up" : "chevron.down", size: 16, color: t.primary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Freshness — "● Live" while recent; a quiet timestamp only once stale.

    private var freshnessSeconds: Int? {
        guard let code = m.currentNearby?.stopCode, let last = store.lastRefresh(code) else { return nil }
        return Int(Date().timeIntervalSince(last))
    }
    private var isFresh: Bool { (freshnessSeconds ?? 999) < 20 }
    private var staleLabel: String? {
        guard let s = freshnessSeconds else { return "Updating…" }
        if s < 60 { return "Updated \(s)s ago" }
        return "Updated \(s / 60)m ago"
    }

    /// "then 11" → "Next 11 min"; nil when there's no following bus.
    private func nextLabel(_ then: String?) -> String? {
        guard let then else { return nil }
        let digits = then.filter(\.isNumber)
        return digits.isEmpty ? nil : "Next \(digits) min"
    }

    /// One arrival as a flat list row (no card, no border, no chevron). The ETA
    /// dominates on the right; destination is secondary, occupancy tertiary. Every
    /// bus-number badge is the same neutral surface — urgency is carried by row
    /// order and the green "Now"/ETA, not by tinting one badge (blue reads as
    /// "selected" here, which it isn't).
    private func arrivalRow(_ a: RDArrival) -> some View {
        let occ = rdOcc(a.load, t)
        let arriving = (Int(a.min) ?? 99) <= 0
        return Button(action: { m.openBus(service: a.route, stopCode: m.currentNearby?.stopCode) }) {
            HStack(spacing: 14) {
                Text(a.route)
                    .font(rdFont(17, .heavy))
                    .foregroundStyle(t.onSurface)
                    .frame(minWidth: 46).frame(height: 38)
                    .padding(.horizontal, 8)
                    .background(t.scHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.dest).font(rdFont(16.5, .semibold)).foregroundStyle(t.onSurface).lineLimit(1)
                    HStack(spacing: 6) {
                        RDDot(color: occ.color, size: 7)
                        Text(occ.label).font(rdFont(12.5, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    if arriving {
                        Text("Now").font(rdFont(17, .heavy)).foregroundStyle(t.bus)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(a.min).font(rdFont(24, .black)).foregroundStyle(t.onSurface)
                                .contentTransition(.numericText())   // cross-fades as it ticks
                            Text("min").font(rdFont(11, .bold)).foregroundStyle(t.onVariant)
                        }
                    }
                    if let next = nextLabel(a.then) {
                        Text(next).font(rdFont(10.5, .medium)).foregroundStyle(t.onVariant)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: a.min)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom nav

struct RDBottomNav: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens

    var body: some View {
        HStack {
            Spacer()
            navItem("Nearby", "location.north.fill", active: m.screen == "map") { m.toMap() }
            Spacer()
            navItem("Saved", "bookmark.fill", active: false) { m.go("saved") }
            Spacer()
        }
        .padding(.top, 7).padding(.bottom, 5)
        .background(t.surface)
        .overlay(Rectangle().fill(t.outlineVariant).frame(height: 1), alignment: .top)
    }

    private func navItem(_ label: String, _ symbol: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            // Flat tab (iOS 26 direction): no capsule — the active tab is simply
            // tinted with the primary colour on both icon and label.
            VStack(spacing: 3) {
                RDSym(symbol, size: 22, color: active ? t.primary : t.onVariant)
                    .frame(height: 26)
                Text(label).font(rdFont(10, active ? .semibold : .medium))
                    .foregroundStyle(active ? t.primary : t.onVariant)
            }
        }
        .buttonStyle(.plain)
    }
}
