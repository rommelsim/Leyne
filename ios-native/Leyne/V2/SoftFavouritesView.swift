// SoftFavouritesView — Leyne 2.4.0 Favourites tab: saved stops and services.
//   • Favourite stops    = `m.pins` → full SoftStopCard (star, distance + walk,
//                          chips, Updated + crowd footer).
//   • Favourite services = `m.favServices` → one row per saved bus. A service
//                          can be saved "anywhere" (next arrival on its route
//                          near you) or "at this stop".
// Filter chips (All / Stops / Services / Bus + Stop) narrow the list. "Edit"
// per section toggles inline remove. "+" opens search; the gear opens Settings.

import SwiftUI

enum FavFilter: Hashable { case all, stops, services, busStop }

struct SoftFavouritesView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onOpenStop: (String) -> Void
    let onOpenBus: (String, String) -> Void
    let onOpenSearch: () -> Void

    @State private var filter: FavFilter = .all
    @State private var editingStops = false
    @State private var editingServices = false

    private var t: Theme { m.t }

    private var isEmpty: Bool { m.pins.isEmpty && m.favServices.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isEmpty {
                        emptyState
                    } else {
                        SortChipRow(t: t, selection: $filter, options: [
                            (.all, "All"),
                            (.stops, "Stops"),
                            (.services, "Services"),
                            (.busStop, "Bus + Stop"),
                        ])
                        if showStops { stopsSection }
                        if showServices { servicesSection }
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .refreshable { await refreshAll() }
        }
        .onAppear { warmArrivals() }
        .onChange(of: m.pins) { _, _ in warmArrivals() }
        .onChange(of: m.favServices) { _, _ in warmArrivals() }
    }

    private var showStops: Bool { filter == .all || filter == .stops }
    private var showServices: Bool { filter == .all || filter == .services || filter == .busStop }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: greeting, t: t)
                Text("Favourites")
                    .font(t.sans(33, weight: .bold))
                    .foregroundStyle(t.fg)
                Text("Your saved stops and services")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 8)
            circleButton("plus", label: "Add a favourite") { fb.select(); onOpenSearch() }
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 40, height: 40)
                .background(t.surface, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Stops

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Pinned stops", icon: "mappin.circle.fill",
                          showEdit: !m.pins.isEmpty, editing: $editingStops)
            if m.pins.isEmpty {
                hint("Pin a stop to see all its arrivals here.")
            } else {
                ForEach(m.pins, id: \.code) { pin in stopCard(pin) }
            }
        }
    }

    private func stopCard(_ pin: Pin) -> some View {
        HStack(spacing: 10) {
            if editingStops { removeButton { unpinStop(pin.code) } }
            SoftStopCard(
                t: t,
                name: stopName(pin.code),
                code: pin.code,
                desc: ds.roadName(pin.code),
                trailing: distanceLabel(pin.code),
                services: ds.servicesFor(pin.code),
                feed: feed(pin.code),
                onTap: { fb.select(); onOpenStop(pin.code) },
                favourite: true,
                walk: walkMinutes(for: pin.code).map { "\($0) min" },
                updatedLabel: updatedLabel(pin.code)
            )
        }
    }

    // MARK: Services

    private var servicesSection: some View {
        let items = filteredServices
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Pinned services", icon: "bus.fill",
                          showEdit: !items.isEmpty, editing: $editingServices)
            if items.isEmpty {
                hint(filter == .services
                     ? "Save a bus 'anywhere' to follow it across stops."
                     : "Track a specific bus at a stop to follow it here.")
            } else {
                VStack(spacing: 8) { ForEach(items) { serviceRow($0) } }
            }
        }
    }

    private var filteredServices: [FavService] {
        switch filter {
        case .services: return m.favServices.filter { $0.isAnywhere }
        case .busStop:  return m.favServices.filter { !$0.isAnywhere }
        default:        return m.favServices
        }
    }

    private func serviceRow(_ fav: FavService) -> some View {
        // Resolve the live arrival: at the saved stop, or the nearest stop the
        // service passes (for "anywhere").
        let resolved = fav.isAnywhere ? anywhereArrival(fav.no) : atStopArrival(fav.no, stop: fav.stop!)
        let svc = resolved?.svc
        let where_ = resolved?.stopName ?? (fav.isAnywhere ? "No nearby arrivals" : stopName(fav.stop ?? ""))
        let conf = svc.map { ArrivalConfidence.of(monitored: $0.monitored, feed: feed(resolved?.stopCode ?? fav.stop ?? "")) } ?? ArrivalConfidence.none
        let badge = serviceBadgeColors(etaSec: svc?.etaSec ?? .max, confidence: conf, t: t)
        return HStack(spacing: 12) {
            if editingServices { removeButton { m.removeFavService(fav) } }
            Button {
                fb.select()
                if let code = resolved?.stopCode ?? fav.stop { onOpenBus(code, fav.no) }
            } label: {
                HStack(spacing: 12) {
                    ServiceBadge(svc: fav.no, t: t, size: .md,
                                 fillOverride: badge.fill, fgOverride: badge.fg)
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(fav.no).font(t.sans(15, weight: .bold)).foregroundStyle(t.fg)
                         + Text(svc.map { "  Towards \($0.dest)" } ?? "")
                            .font(t.sans(14, weight: .medium)).foregroundStyle(t.fg))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: fav.isAnywhere ? "location.fill" : "mappin")
                                .font(.system(size: 10, weight: .semibold))
                            Text(fav.isAnywhere ? "Near you · \(where_)" : where_)
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
                .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
    }

    /// Primary ETA (proximity-coloured) + the next two arrivals, mirroring the
    /// mockup's "2 · 18 · 35 min" row.
    @ViewBuilder
    private func serviceETAs(_ svc: Service?, conf: ArrivalConfidence) -> some View {
        if let svc {
            let e1 = fmtETA(svc.etaSec)
            let color = etaColor(etaSec: svc.etaSec, confidence: conf, t: t)
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

    /// "18 · 35 min" from the following + third arrivals, when present.
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

    // MARK: Shared bits

    private func sectionHeader(_ title: String, icon: String, showEdit: Bool, editing: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.soon)
            Text(title)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer()
            if showEdit {
                Button {
                    fb.select()
                    withAnimation(.easeInOut(duration: 0.15)) { editing.wrappedValue.toggle() }
                } label: {
                    Text(editing.wrappedValue ? "Done" : "Edit")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.meBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 2)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(t.sans(13)).foregroundStyle(t.faint).padding(.leading, 2)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button { fb.select(); withAnimation(.easeInOut(duration: 0.2)) { action() } } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(t.crit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(t.meBlue)
                .frame(width: 64, height: 64)
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Arrival resolution

    private func atStopArrival(_ no: String, stop: String) -> (svc: Service, stopName: String, stopCode: String)? {
        guard let s = ds.servicesFor(stop).first(where: { $0.no == no }) else { return nil }
        return (s, stopName(stop), stop)
    }

    /// Nearest stop the service passes (ds.nearby is distance-sorted) + its
    /// arrival — the "next arrival near you" for an anywhere favourite.
    private func anywhereArrival(_ no: String) -> (svc: Service, stopName: String, stopCode: String)? {
        for stop in ds.nearby {
            if let s = ds.servicesFor(stop.stopCode).first(where: { $0.no == no }) {
                return (s, stop.stopName, stop.stopCode)
            }
        }
        return nil
    }

    // MARK: Mutations

    private func unpinStop(_ code: String) { m.pins.removeAll { $0.code == code } }

    // MARK: Data helpers

    private func feed(_ code: String) -> Freshness { Freshness.from(ds.lastRefresh(code)) }

    private func stopName(_ code: String) -> String {
        let n = ds.stopName(code)
        return n.isEmpty ? code : n
    }

    private func updatedLabel(_ code: String) -> String? {
        guard let last = ds.lastRefresh(code) else { return nil }
        let s = Int(Date().timeIntervalSince(last))
        if s < 5  { return "Updated just now" }
        if s < 60 { return "Updated \(s) sec ago" }
        return "Updated \(s / 60) min ago"
    }

    private func distanceLabel(_ code: String) -> String? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[code] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return fmtDistance(Int(d.rounded()))
    }

    private func walkMinutes(for code: String) -> Int? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[code] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return max(1, Int((d / 80).rounded()))
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
        for fav in m.favServices { if let s = fav.stop { ds.ensureArrivals(stop: s) } }
        ds.prefetchNearbyArrivals()
    }

    private func refreshAll() async {
        for pin in m.pins { await ds.refreshArrivals(stop: pin.code) }
        for fav in m.favServices { if let s = fav.stop { await ds.refreshArrivals(stop: s) } }
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
