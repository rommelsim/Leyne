// SoftFavouritesView — Leyne 2.4.0 Favourites tab.
//
// DESIGN (2.4.0 restyle):
//   • Large bold title "Saved" + three-segment filter: All | Stops | Buses.
//       All   = pinned stops section + saved bus services section
//       Stops = pinned stops only
//       Buses = saved bus services only
//   • Each stop is a SoftNearbyStopCard-style t.surface card (cornerRadius 18)
//     with an identity block, walk/distance, bus chips, and a gold star badge.
//   • Swipe gestures:
//       Pinned stop   → trailing swipe (left): destructive Delete → unpinStop
//       Saved service → trailing swipe (left): destructive Delete → removeFavService
//   • "+ Add stop" bottom row wired to onOpenSearch().

import SwiftUI

// MARK: - Filter enum

enum FavSegment: Hashable { case all, stops, buses }

// MARK: - Main view

struct SoftFavouritesView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onOpenStop: (String) -> Void
    let onOpenBus: (String, String) -> Void
    let onOpenSearch: () -> Void

    @State private var segment: FavSegment = .all

    private var t: Theme { m.t }

    private var isEmpty: Bool {
        m.pins.isEmpty && m.favServices.isEmpty
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            List {
                // ── Title + segmented control ──────────────────────────────
                Section {
                    // empty — content is in the header
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saved")
                            .font(t.sans(31, weight: .bold))
                            .foregroundStyle(t.fg)
                            .padding(.top, 8)
                        segmentedControl
                    }
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                if isEmpty {
                    // Empty state row
                    emptyState
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    // ── Stops ──────────────────────────────────────────────
                    if segment == .all || segment == .stops {
                        if !m.pins.isEmpty {
                            if segment == .all {
                                stopsHeader
                                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            ForEach(m.pins, id: \.code) { pin in
                                favStopRow(pin)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            unpinStop(pin.code)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } else if segment == .stops {
                            hint("Pin a stop to see all its arrivals here.")
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    // ── Saved services ─────────────────────────────────────
                    if segment == .all || segment == .buses {
                        if !m.favServices.isEmpty {
                            servicesHeader
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            ForEach(m.favServices) { fav in
                                serviceRow(fav)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            m.removeFavService(fav)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } else if segment == .buses {
                            hint("Save a bus service to track it here.")
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    // ── Add stop row ───────────────────────────────────────
                    addStopRow
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Bottom padding row
                Color.clear.frame(height: 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(t.bg)
            .refreshable { await refreshAll() }
        }
        .onAppear { warmArrivals() }
        .onChange(of: m.pins) { _, _ in warmArrivals() }
        .onChange(of: m.favServices) { _, _ in warmArrivals() }
    }

    // MARK: Segmented control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentPill("All",   for: .all)
            segmentPill("Stops", for: .stops)
            segmentPill("Buses", for: .buses)
        }
        .padding(3)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func segmentPill(_ label: String, for value: FavSegment) -> some View {
        let active = segment == value
        return Button {
            fb.select()
            withAnimation(.easeInOut(duration: 0.15)) { segment = value }
        } label: {
            Text(label)
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(active ? t.contrastFg : t.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    active ? AnyShapeStyle(t.soon) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Stop row

    @ViewBuilder
    private func favStopRow(_ pin: Pin) -> some View {
        FavStopCard(
            t: t,
            code: pin.code,
            name: stopName(pin.code),
            road: ds.roadName(pin.code),
            walkMin: walkMinFromLocation(code: pin.code),
            distanceM: distanceMFromLocation(code: pin.code),
            services: ds.servicesFor(pin.code),
            feed: feed(pin.code),
            tick: m.tick,
            onTap: { fb.select(); onOpenStop(pin.code) }
        )
    }

    // MARK: Section headers

    private var stopsHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.soon)
            Text("Saved stops")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer()
        }
        .padding(.leading, 2)
    }

    private var servicesHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "bus.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.soon)
            Text("Saved services")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer()
        }
        .padding(.leading, 2)
    }

    // MARK: Service row

    private func serviceRow(_ fav: FavService) -> some View {
        let resolved = fav.isAnywhere ? anywhereArrival(fav.no) : atStopArrival(fav.no, stop: fav.stop!)
        let svc = resolved?.svc
        let whereName = resolved?.stopName ?? (fav.isAnywhere ? "No nearby arrivals" : stopName(fav.stop ?? ""))
        let conf = svc.map {
            ArrivalConfidence.of(monitored: $0.monitored,
                                 feed: feed(resolved?.stopCode ?? fav.stop ?? ""))
        } ?? ArrivalConfidence.none

        return Button {
            fb.select()
            if let code = resolved?.stopCode ?? fav.stop { onOpenBus(code, fav.no) }
        } label: {
            HStack(spacing: 12) {
                // Badge keeps its standard look — proximity is not colour-coded.
                ServiceBadge(svc: fav.no, t: t, size: .md)
                VStack(alignment: .leading, spacing: 3) {
                    (Text(fav.no)
                        .font(t.sans(15, weight: .bold))
                        .foregroundStyle(t.fg)
                     + Text(svc.map { "  Towards \($0.dest)" } ?? "")
                        .font(t.sans(14, weight: .medium))
                        .foregroundStyle(t.fg))
                    .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: fav.isAnywhere ? "location.fill" : "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(fav.isAnywhere ? "Near you · \(whereName)" : whereName)
                            .font(t.mono(11.5))
                    }
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                serviceETAs(svc, conf: conf)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(t.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Service ETA helpers (preserved from original)

    @ViewBuilder
    private func serviceETAs(_ svc: Service?, conf: ArrivalConfidence) -> some View {
        if let svc {
            let e1 = fmtETA(svc.etaSec)
            // Uniform ink — soon-ness isn't colour-coded; ghosts read faint.
            let color = conf == .unconfirmed ? t.dim : t.fg
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                etaText(e1, color: color, big: true)
                if let nextLabel = followingLabel(svc) {
                    Rectangle().fill(t.line).frame(width: 1, height: 16)
                    Text(nextLabel)
                        .font(t.mono(12, weight: .medium))
                        .foregroundStyle(t.dim)
                }
            }
        } else {
            Text("—").font(t.mono(16, weight: .semibold)).foregroundStyle(t.faint)
        }
    }

    private func etaText(_ eta: ETA, color: Color, big: Bool) -> some View {
        let arriving = eta.big == "Arr"
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(arriving ? eta.small : eta.big)
                .font(t.mono(big ? 18 : 13, weight: big ? .bold : .semibold))
                .foregroundStyle(color)
            if !arriving {
                Text(eta.small)
                    .font(t.mono(big ? 12 : 10, weight: .semibold))
                    .foregroundStyle(color.opacity(0.85))
            }
        }
    }

    private func followingLabel(_ s: Service) -> String? {
        let next = fmtETA(s.followingSec)
        guard next.big != "Arr", !next.big.isEmpty else { return nil }
        if let d = s.thirdDate {
            let third = fmtETA(max(0, Int(d.timeIntervalSinceNow)))
            if third.big != "Arr", !third.big.isEmpty {
                return "\(next.big) · \(third.big) min"
            }
        }
        return "\(next.big) min"
    }

    // MARK: Add stop row

    private var addStopRow: some View {
        // The Buses segment lists saved services, so the add row adds a bus
        // there; otherwise it adds a stop. Search finds both either way — only
        // the label follows the section the user is looking at.
        let isBuses = segment == .buses
        return Button {
            fb.select()
            onOpenSearch()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(t.surfaceHi)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.meBlue)
                }
                .frame(width: 36, height: 36)
                Text(isBuses ? "Add bus" : "Add stop")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.meBlue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(t.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(isBuses ? "Add a bus to favourites"
                                    : "Add a stop to favourites")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(t.meBlue)
                .frame(width: 64, height: 64)
                .background(t.surfaceHi,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("No favourites yet")
                .font(t.sans(20, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Pin the stops and buses you use most — tap the pin on any stop or bus — and they'll show up here.")
                .font(t.sans(13))
                .foregroundStyle(t.dim)
            Button(action: { fb.select(); onOpenSearch() }) {
                Text("Find a stop")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Shared primitives

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(t.sans(13))
            .foregroundStyle(t.faint)
            .padding(.leading, 2)
    }

    // MARK: Arrival resolution (for services section)

    private func atStopArrival(_ no: String,
                                stop: String) -> (svc: Service, stopName: String, stopCode: String)? {
        guard let s = ds.servicesFor(stop).first(where: { $0.no == no }) else { return nil }
        return (s, stopName(stop), stop)
    }

    private func anywhereArrival(_ no: String) -> (svc: Service, stopName: String, stopCode: String)? {
        for pin in m.pins {
            if let s = ds.servicesFor(pin.code).first(where: { $0.no == no }) {
                return (s, stopName(pin.code), pin.code)
            }
        }
        return nil
    }

    // MARK: Mutations

    private func unpinStop(_ code: String) {
        fb.tap()
        m.pins.removeAll { $0.code == code }
    }

    // MARK: Data helpers

    private func feed(_ code: String) -> Freshness { Freshness.from(ds.lastRefresh(code)) }

    private func stopName(_ code: String) -> String {
        let n = ds.stopName(code)
        return n.isEmpty ? code : n
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
        for fav in m.favServices { if let s = fav.stop { ds.ensureArrivals(stop: s) } }
    }

    private func refreshAll() async {
        for pin in m.pins { await ds.refreshArrivals(stop: pin.code) }
        for fav in m.favServices { if let s = fav.stop { await ds.refreshArrivals(stop: s) } }
    }
}

// MARK: - Distance helpers (free functions)

@MainActor
private func walkMinFromLocation(code: String) -> Int {
    guard let here = LocationManager.shared.location,
          let stop = DataStore.shared.stopByCode[code] else { return 0 }
    let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                      stop.Latitude, stop.Longitude)
    return max(1, Int((d / 80).rounded()))
}

@MainActor
private func distanceMFromLocation(code: String) -> Int {
    guard let here = LocationManager.shared.location,
          let stop = DataStore.shared.stopByCode[code] else { return 0 }
    return Int(haversine(here.coordinate.latitude, here.coordinate.longitude,
                         stop.Latitude, stop.Longitude).rounded())
}

// MARK: - FavStopCard

/// Stop card used on the Favourites tab.
/// Matches SoftNearbyStopCard layout (identity block + divider + chip row)
/// with a gold star badge on the pin tile (all stops in Saved are pinned).
private struct FavStopCard: View {
    let t: Theme
    let code: String
    let name: String
    let road: String
    let walkMin: Int
    let distanceM: Int
    let services: [Service]
    let feed: Freshness
    let tick: Int             // drives per-second ETA recompute
    let onTap: () -> Void

    private static let maxChips = 4

    private var sorted: [Service] {
        services.sorted { $0.etaSec < $1.etaSec }
    }

    var body: some View {
        let _ = tick
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                identityBlock
                Rectangle()
                    .fill(t.line)
                    .frame(height: 1)
                    .padding(.vertical, 12)
                if sorted.isEmpty {
                    quietRow
                } else {
                    chipRow
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(name)")
    }

    private var identityBlock: some View {
        HStack(spacing: 12) {
            // Pin tile — the place glyph. Star badge removed: everything in
            // this tab is already saved, so the badge added no signal.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(t.surfaceHi)
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
                // Walk + distance row
                if walkMin > 0 || distanceM > 0 {
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

    // Chip row — reuses MiniBusChip from SoftStopCard.swift
    private var chipRow: some View {
        let shown = Array(sorted.prefix(Self.maxChips))
        return HStack(alignment: .top, spacing: 7) {
            ForEach(Array(shown.enumerated()), id: \.element.no) { i, s in
                let conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed)
                MiniBusChip(
                    t: t,
                    svc: s.no,
                    etaSec: s.etaSec,
                    confidence: conf,
                    highlight: i == 0 && conf == .live
                               && ETATier.of(etaSec: s.etaSec).isImminent
                )
            }
            if sorted.count > Self.maxChips {
                moreChip(count: sorted.count - Self.maxChips)
            }
        }
    }

    private func moreChip(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("+\(count)")
                .font(t.sans(15, weight: .bold))
                .foregroundStyle(t.dim)
            Text("more")
                .font(t.mono(11, weight: .medium))
                .foregroundStyle(t.faint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(t.surfaceHi,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(count) more buses")
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
}
