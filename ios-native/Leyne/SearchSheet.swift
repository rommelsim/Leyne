// Quick Search — Conservative (A) + Ambitious (B). Live LTA Buses + Stops.

import SwiftUI
import os

private let searchLog = Logger(subsystem: "com.leyne.Leyne", category: "Search")

// ═══ Variant A — Conservative ═══════════════════════════════
struct SearchSheetA: View {
    let t: Theme
    let dark: Bool
    let onClose: () -> Void
    let onPick: (String) -> Void          // stop code

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var q = ""
    @FocusState private var focused: Bool

    // Postal-code geocode state. `postalGeoFor` is the postal code the
    // current `postalGeo` was resolved for — so a fresh 6-digit entry
    // re-triggers the lookup and a partially-typed code doesn't burn
    // OneMap requests.
    @State private var postalGeo: GeoPlace?
    @State private var postalGeoFor: String?
    @State private var postalLoading = false
    @State private var postalFailed = false

    private var buses: [LTABusServiceDTO] { store.searchServices(q) }
    private var stops: [LTABusStop] { store.searchStops(q) }
    private var total: Int { buses.count + stops.count }
    private var isPostalQuery: Bool {
        detectQueryKind(q).kind == "postal"
    }

    private func pickStop(_ code: String) {
        m.addRecent(q.isEmpty ? store.stopName(code) : q)
        onPick(code); onClose()
    }
    private func pickBus(_ no: String) {
        Task {
            if let s = await store.originStop(ofService: no) {
                m.addRecent(no); onPick(s.BusStopCode); onClose()
            }
        }
    }

    /// Trigger an OneMap geocode lookup whenever the user types a fresh
    /// 6-digit postal code. Idempotent — a partial change to the same code
    /// doesn't re-fire.
    private func maybeGeocode() {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard detectQueryKind(trimmed).kind == "postal",
              postalGeoFor != trimmed else { return }
        searchLog.notice("postal lookup START code=\(trimmed, privacy: .public)")
        postalGeoFor = trimmed
        postalGeo = nil
        postalFailed = false
        postalLoading = true
        Task {
            let result = await GeocodeService.shared.postalCode(trimmed)
            await MainActor.run {
                guard postalGeoFor == trimmed else {
                    searchLog.notice("postal lookup STALE \(trimmed, privacy: .public) — query changed")
                    return
                }
                postalLoading = false
                if let r = result {
                    postalGeo = r
                    searchLog.notice("postal lookup OK \(trimmed, privacy: .public) → \(r.label, privacy: .public)")
                } else {
                    postalFailed = true
                    searchLog.error("postal lookup FAILED \(trimmed, privacy: .public)")
                }
            }
        }
    }

    var body: some View {
        // Outer ScrollView is the layout's primary actor — it naturally
        // fills the available space and scrolls content. The search field
        // + detected pill ride on `safeAreaInset(.top)`; the "AT A STOP?"
        // hint rides on `safeAreaInset(.bottom)`. This is iOS's native
        // search-sheet pattern. The earlier `VStack { search; pill;
        // ScrollView; footer }` was collapsing the middle ScrollView to
        // 0pt on iOS 26 — neither `.frame(maxHeight: .infinity)` nor
        // `.layoutPriority(1)` could un-collapse it.
        ScrollView {
            if q.isEmpty {
                emptyState
            } else if isPostalQuery {
                postalResults
            } else {
                results
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15)).foregroundStyle(t.dim)
                            .padding(.leading, 10)
                        TextField("Bus or stop (name / code)", text: $q)
                            .focused($focused).font(t.sans(15)).foregroundStyle(t.fg)
                            .autocorrectionDisabled().padding(.horizontal, 8)
                        if !q.isEmpty {
                            Button { q = "" } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(t.dim)
                            }.padding(.trailing, 10)
                        }
                    }
                    .frame(height: 40)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))
                    Button("Cancel", action: onClose)
                        .font(t.sans(14, weight: .medium))
                        .foregroundStyle(t.accent)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                .overlay(alignment: .bottom) { Divider().overlay(t.line) }

                if !q.isEmpty {
                    HStack {
                        (Text("DETECTED · ")
                         + Text(detectQueryKind(q).label.isEmpty ? "ANY" : detectQueryKind(q).label.uppercased()).foregroundColor(t.fg)
                         + Text(total > 0 ? " · \(total) match\(total == 1 ? "" : "es")" : ""))
                            .font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
                }
            }
            .background(t.bg)   // opaque so scrolled content doesn't bleed through
        }
        // The "AT A STOP? · Scan poster QR" footer was visual-only — the
        // QR scanner was never implemented. Removed so the sheet doesn't
        // tease a non-existent feature. No AdBanner here either (would
        // re-trigger an iOS 26 layout collapse); ads appear on Home /
        // Nearby / Settings via tabViewBottomAccessory.
        .background(t.bg.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: q) { _, _ in maybeGeocode() }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onClose(); m.setTab(.nearby) } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9).fill(t.accent.opacity(0.09))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "location.fill").foregroundStyle(t.accent))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Stops near me").font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                        Text("Live, sorted by walking distance").font(t.sans(11)).foregroundStyle(t.dim)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(t.dim)
                }
                .padding(14)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.bottom, 18)

            if !m.recents.isEmpty {
                Text("RECENT").font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim).padding(.bottom, 10)
                FlowChips(items: m.recents, t: t) { q = $0 }
            } else {
                Text("Search a bus number or a stop name / 5-digit code.")
                    .font(t.sans(12)).foregroundStyle(t.dim).padding(.top, 8)
            }
        }
        .padding(16)
    }

    @ViewBuilder private var results: some View {
        VStack(spacing: 0) {
            if total == 0 {
                VStack(spacing: 6) {
                    Text("Nothing matches “\(q)”").font(t.sans(13))
                    Text("Try a bus number or a stop name / 5-digit code.").font(t.sans(11))
                }.foregroundStyle(t.dim).padding(40)
            }
            if !buses.isEmpty {
                srGroup("BUSES", buses.count) {
                    ForEach(buses.prefix(20), id: \.ServiceNo) { b in
                        SRRow(t: t, leading: .bus(b.ServiceNo),
                              title: b.LoopDesc?.isEmpty == false ? "Loop · \(b.LoopDesc!)" : "Service \(b.ServiceNo)",
                              sub: (b.Operator ?? "") + (b.Category.map { " · \($0.capitalized)" } ?? "")) {
                            pickBus(b.ServiceNo)
                        }
                    }
                }
            }
            if !stops.isEmpty {
                srGroup("STOPS", stops.count) {
                    ForEach(stops.prefix(30), id: \.BusStopCode) { s in
                        SRRow(t: t, leading: .icon("smallcircle.filled.circle", t.accent),
                              title: s.Description, sub: "STOP \(s.BusStopCode) · \(s.RoadName)") {
                            pickStop(s.BusStopCode)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4).padding(.bottom, 24)
    }

    private func srGroup<C: View>(_ label: String, _ count: Int, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack { Text(label); Spacer(); Text("\(count)") }
                .font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
            c()
        }
    }

    // MARK: - Postal-code results (6-digit query → stops within radius)

    @ViewBuilder private var postalResults: some View {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if postalLoading {
            VStack(spacing: 10) {
                ProgressView().tint(t.dim).controlSize(.regular)
                Text("Finding postal code \(trimmed)…")
                    .font(t.sans(13)).foregroundStyle(t.dim)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 80)
        } else if postalGeo == nil {
            // postalGeo is nil either because the API failed (postalFailed
            // = true) OR because maybeGeocode hasn't fired yet (race on
            // sheet open). In both cases the user benefits from the same
            // "couldn't find" guidance with a retry affordance.
            VStack(spacing: 8) {
                Image(systemName: postalFailed ? "wifi.exclamationmark" : "magnifyingglass")
                    .font(.system(size: 24)).foregroundStyle(t.dim)
                Text(postalFailed
                     ? "Can't look up postal codes right now"
                     : "Couldn't find postal code \(trimmed)")
                    .font(t.sans(13, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .multilineTextAlignment(.center)
                Text(postalFailed
                     ? "OneMap (the postal-code service) didn't respond. Check your connection and try again."
                     : "Check the 6-digit code and try again.")
                    .font(t.sans(11)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    // Force a re-run by clearing the dedupe key — same code
                    // typed twice in a row now triggers a fresh lookup.
                    postalGeoFor = nil
                    maybeGeocode()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(t.sans(13, weight: .medium)).foregroundStyle(t.bg)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60).padding(.horizontal, 32)
        } else if let geo = postalGeo {
            let radius = m.searchRadiusM
            let nearbyStops = postalStops(geo: geo, radius: radius)
            VStack(alignment: .leading, spacing: 0) {
                postalSummary(geo: geo, count: nearbyStops.count, radius: radius)
                if nearbyStops.isEmpty {
                    postalEmpty(radius: radius)
                } else {
                    VStack(spacing: 6) {
                        ForEach(nearbyStops) { s in
                            Button {
                                m.addRecent(geo.label)
                                onPick(s.stopCode); onClose()
                            } label: { postalStopRow(s) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func postalStops(geo: GeoPlace, radius: Int) -> [NearbyStop] {
        let r = Double(radius)
        return store.stopByCode.values.compactMap { s -> NearbyStop? in
            let d = haversine(geo.lat, geo.lon, s.Latitude, s.Longitude)
            guard d <= r else { return nil }
            return NearbyStop(
                id: s.BusStopCode,
                stopName: s.Description,
                stopCode: s.BusStopCode,
                distanceM: Int(d.rounded()),
                walkMin: max(1, Int((d / 80).rounded())),
                services: store.servicesFor(s.BusStopCode)
            )
        }
        .sorted { $0.distanceM < $1.distanceM }
    }

    private func postalSummary(geo: GeoPlace, count: Int, radius: Int) -> some View {
        let countLabel = count == 1 ? "STOP" : "STOPS"
        let radiusLabel = radius < 1000 ? "\(radius)M" : "\(Int(radius / 1000))KM"
        return VStack(alignment: .leading, spacing: 4) {
            Text("POSTAL \(geo.postalCode) · \(count) \(countLabel) · \(radiusLabel)")
                .font(t.mono(10, weight: .medium)).tracking(0.8)
                .foregroundStyle(t.dim)
            Text(geo.label)
                .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)
    }

    private func postalStopRow(_ s: NearbyStop) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(s.distanceM)")
                        .font(t.mono(15, weight: .semibold)).foregroundStyle(t.fg)
                    Text("m").font(t.mono(9)).foregroundStyle(t.dim)
                }
                Text("\(s.walkMin) MIN")
                    .font(t.mono(8)).tracking(0.4).foregroundStyle(t.faint)
            }
            .frame(width: 48)
            Rectangle().fill(t.line).frame(width: 1, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.stopName)
                    .font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
                    .lineLimit(1)
                Text("STOP \(s.stopCode)")
                    .font(t.mono(10)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundStyle(t.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))
    }

    private func postalEmpty(radius: Int) -> some View {
        let radiusLabel = radius < 1000 ? "\(radius) m" : "\(Int(radius / 1000)) km"
        return VStack(spacing: 6) {
            Text("No bus stops within \(radiusLabel)")
                .font(t.sans(13, weight: .semibold)).foregroundStyle(t.fg)
            Text("Try a larger search radius in Settings.")
                .font(t.sans(11)).foregroundStyle(t.dim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

// ═══ Variant B — Ambitious ══════════════════════════════════
struct SearchSheetB: View {
    let t: Theme
    let dark: Bool
    let onClose: () -> Void
    let onPick: (String) -> Void

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var q = ""
    @FocusState private var focused: Bool

    private var buses: [LTABusServiceDTO] { store.searchServices(q) }
    private var stops: [LTABusStop] { store.searchStops(q) }
    private var total: Int { buses.count + stops.count }
    private var detected: DetectedKind { detectQueryKind(q) }

    private var kindColor: Color {
        switch detected.kind {
        case "bus": return t.live
        case "stopcode": return t.accent
        case "postal", "block": return t.warn
        case "text": return t.fg
        default: return t.dim
        }
    }

    private func pickStop(_ code: String) {
        m.addRecent(q.isEmpty ? store.stopName(code) : q); onPick(code); onClose()
    }
    private func pickBus(_ no: String) {
        Task { if let s = await store.originStop(ofService: no) {
            m.addRecent(no); onPick(s.BusStopCode); onClose() } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SEARCH").font(t.mono(11)).tracking(1.4).foregroundStyle(t.dim)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(t.fg)
                        .frame(width: 32, height: 32)
                        .background(t.surface, in: Circle())
                        .overlay(Circle().stroke(t.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

            HStack {
                TextField("What are you looking for?", text: $q)
                    .focused($focused)
                    .font(t.sans(36, weight: .medium)).foregroundStyle(t.fg)
                    .autocorrectionDisabled()
                if !q.isEmpty {
                    Button { q = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 18)).foregroundStyle(t.dim)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(q.isEmpty ? t.dim : kindColor).frame(width: 5, height: 5)
                    Text(q.isEmpty ? "WAITING" : (detected.label.isEmpty ? "ANYTHING" : detected.label.uppercased()))
                }
                .font(t.mono(11)).tracking(0.8)
                .foregroundStyle(q.isEmpty ? t.dim : kindColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background((q.isEmpty ? t.dim : kindColor).opacity(q.isEmpty ? 0.06 : 0.13), in: Capsule())
                .overlay(Capsule().stroke(q.isEmpty ? t.line : kindColor.opacity(0.33), lineWidth: 1))
                if !q.isEmpty && total > 0 {
                    Text("\(total) MATCH\(total == 1 ? "" : "ES")").font(t.mono(11)).foregroundStyle(t.dim)
                }
                Spacer()
                Image(systemName: "qrcode").font(.system(size: 16)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)

            ScrollView { if q.isEmpty { emptyStateB } else { resultsB } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((dark ? Color(hex: "0a0907") : Color(hex: "FBF8F0")).ignoresSafeArea())
        .onAppear { focused = true }
    }

    @ViewBuilder private var emptyStateB: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onClose(); m.setTab(.nearby) } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 11).fill(t.bg.opacity(0.13))
                        .frame(width: 42, height: 42)
                        .overlay(Image(systemName: "location.fill").foregroundStyle(t.bg))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HERE").font(t.mono(11)).tracking(0.8).opacity(0.6)
                        Text("Stops within walking distance").font(t.sans(15, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 16))
                }
                .foregroundStyle(t.bg).padding(16)
                .background(t.fg, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).padding(.bottom, 16)

            if !m.recents.isEmpty {
                Text("RECENT").font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim).padding(.bottom, 4)
                ForEach(m.recents, id: \.self) { r in
                    Button { q = r } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(t.dim)
                            Text(r).font(t.sans(14)).foregroundStyle(t.fg)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Divider().overlay(t.line) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 32)
    }

    @ViewBuilder private var resultsB: some View {
        VStack(alignment: .leading, spacing: 0) {
            if total == 0 {
                VStack(spacing: 4) {
                    Text("Nothing matches that.").font(t.sans(14)).foregroundStyle(t.fg)
                    Text("I look up bus services and bus stops.").font(t.sans(12)).foregroundStyle(t.dim)
                }.frame(maxWidth: .infinity).padding(48)
            }
            if !buses.isEmpty {
                srGroupB("Buses", t.live) {
                    ForEach(buses.prefix(20), id: \.ServiceNo) { b in
                        richRow(lead: .bus(b.ServiceNo),
                                title: b.LoopDesc?.isEmpty == false ? "Loop · \(b.LoopDesc!)" : "Service \(b.ServiceNo)",
                                sub: (b.Operator ?? "")) { pickBus(b.ServiceNo) }
                    }
                }
            }
            if !stops.isEmpty {
                srGroupB("Stops", t.accent) {
                    ForEach(stops.prefix(30), id: \.BusStopCode) { s in
                        richRow(lead: .icon("smallcircle.filled.circle", t.accent),
                                title: s.Description, sub: "STOP \(s.BusStopCode) · \(s.RoadName)") {
                            pickStop(s.BusStopCode)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func srGroupB<C: View>(_ label: String, _ accent: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(label.uppercased()).font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim)
                Rectangle().fill(t.line).frame(height: 1)
            }
            .padding(.horizontal, 18).padding(.bottom, 8)
            VStack(spacing: 6) { c() }.padding(.horizontal, 12)
        }
        .padding(.top, 18)
    }

    private enum Lead { case bus(String), icon(String, Color) }
    private func richRow(lead: Lead, title: String, sub: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                switch lead {
                case .bus(let no):
                    Text(no).font(t.mono(15, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 56, minHeight: 38)
                        .background(t.live, in: RoundedRectangle(cornerRadius: 8))
                case .icon(let name, let c):
                    RoundedRectangle(cornerRadius: 11).fill(c.opacity(0.13))
                        .frame(width: 42, height: 42)
                        .overlay(Image(systemName: name).font(.system(size: 17)).foregroundStyle(c))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg).lineLimit(1)
                    Text(sub).font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ─── Shared compact row (variant A) ───────────────────────
struct SRRow: View {
    let t: Theme
    enum Lead { case bus(String), icon(String, Color) }
    let leading: Lead
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                switch leading {
                case .bus(let no):
                    Text(no).font(t.mono(13, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 48, minHeight: 32)
                        .background(t.live, in: RoundedRectangle(cornerRadius: 7))
                case .icon(let name, let c):
                    RoundedRectangle(cornerRadius: 9).fill(c.opacity(0.09))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: name).font(.system(size: 15)).foregroundStyle(c))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg).lineLimit(1)
                    Text(sub).font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

/// Single-line scrolling chip strip for recent searches. The previous
/// LazyVGrid layout wrapped long entries (e.g. a postal-code address
/// like "338 Clementi Avenue 2") onto three lines, blowing up the pill's
/// height and making the row look ragged. A horizontal ScrollView with
/// `lineLimit(1)` keeps every pill exactly one row tall — the user
/// scrolls sideways to see older items.
struct FlowChips: View {
    let items: [String]
    let t: Theme
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { onTap(item) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(t.dim)
                            Text(item)
                                .font(t.sans(12, weight: .medium))
                                .foregroundStyle(t.fg)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t.surface, in: Capsule())
                        .overlay(Capsule().stroke(t.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Lets the *first* chip sit flush with the section's leading
            // edge without an extra row of padding around the ScrollView.
            .padding(.trailing, 16)
        }
        // ScrollView fights to fill height in a VStack; cap it so the
        // chip row stays a single pill-height tall.
        .frame(height: 38)
    }
}
