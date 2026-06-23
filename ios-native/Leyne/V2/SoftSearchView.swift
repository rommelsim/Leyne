// SoftSearchView — Leyne Search tab: a first-class surface with a large
// "Search" title, a prominent field, a recent-searches list, and results
// auto-split into Services + Bus stops.
// Input kind is auto-detected (no mode tabs); a 6-digit query geocodes
// via OneMap and lists nearby stops. All real search logic is preserved.

import SwiftUI

struct SoftSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var query = ""
    /// When true the view is presented as a bottom card (sheet) raised from the
    /// Home search bar rather than as a full surface: the big "Search" title is
    /// dropped (so there's a single search field, not two), the field autofocuses,
    /// and Cancel dismisses the card via `onClose`.
    var compact: Bool = false
    /// When set, the view renders ONLY its results (no title, no field, no
    /// NavigationStack) and mirrors this host-owned text into its internal query.
    /// Used by Home / MRT to drop the results under their native `.searchable`
    /// bar — one search field (the system bar), all the same results logic.
    var externalText: Binding<String>? = nil
    let onClose: () -> Void
    let onOpenStop: (String) -> Void
    /// Called when the user taps a service result. Receives (originStopCode, serviceNo)
    /// so the root can push SoftBusView directly with fullRoute: true.
    var onOpenBus: ((String, String) -> Void)?
    /// Called when the user taps an MRT station result. Switches to the MRT tab
    /// and pushes the station detail. Nil for callers that pre-date this param.
    var onOpenMrtStation: ((MrtGeoStation) -> Void)?

    @FocusState private var focused: Bool

    /// Drives the native `.searchable` bar in card (compact) mode — set true on
    /// appear so the system search field presents already focused.
    @State private var searchPresented = false

    // Search category filter — only active during normal text-search results.
    enum SearchFilter: String, CaseIterable {
        case all   = "All"
        case stops = "Stops"
        case buses = "Buses"
        case mrt   = "MRT"
    }
    @State private var searchFilter: SearchFilter = .all

    // Postal-code geocode state (stale-safe).
    @State private var postalGeo: GeoPlace?
    @State private var postalGeoFor: String?
    @State private var postalLoading = false
    @State private var postalFailed = false

    // Guards `search_performed` analytics to once per search session (set when the
    // query first becomes non-empty, re-armed when cleared) — see the onChange.
    @State private var loggedSearchSession = false

    private var t: Theme { m.t }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isPostal: Bool { detectQueryKind(trimmed).kind == "postal" }

    var body: some View {
        Group {
            if externalText != nil {
                embeddedResults
            } else if compact {
                nativeSearchBody
            } else {
                customBody
            }
        }
        .onAppear {
            // Warm the large, lazy BusRoutes dataset while the user browses so
            // tapping a bus result opens the route view immediately instead of
            // blocking on a cold fetch (originStop + serviceRoute both need it).
            ds.ensureRoutes()
            if let ext = externalText { query = ext.wrappedValue }
        }
        .onChange(of: query) { _, newVal in
            maybeGeocode()
            // Reset filter to All when the query changes so a stale filter
            // doesn't hide results from a completely different search term.
            if searchFilter != .all { searchFilter = .all }
            // Log one search_performed per search session: fire on the keystroke
            // that first makes the query non-empty, then re-arm once it's cleared.
            // Avoids one analytics event per character while still counting each
            // distinct search.
            let hasQuery = !newVal.trimmingCharacters(in: .whitespaces).isEmpty
            if hasQuery, !loggedSearchSession {
                loggedSearchSession = true
                AnalyticsService.log(.searchPerformed)
            } else if !hasQuery {
                loggedSearchSession = false
            }
        }
    }

    // MARK: Body variants

    /// Embedded presentation: results only, no chrome. The host owns the native
    /// `.searchable` bar; its text is mirrored into the internal `query` that all
    /// the results logic already reads, so there's a single search field.
    private var embeddedResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                resultsContent.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(t.bg)
        .onChange(of: externalText?.wrappedValue ?? "") { _, new in query = new }
    }

    /// Card presentation (iOS 26): the system search bar via `.searchable`
    /// (Liquid Glass material, native focus / Cancel / clear) above the results.
    /// No custom field — that's what made the card read as a non-native, second
    /// search bar.
    private var nativeSearchBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    resultsContent.padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(t.bg)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { fb.select(); onClose() } label: {
                        Text("Done").font(t.sans(15, weight: .semibold))
                    }
                }
            }
            .searchable(text: $query,
                        isPresented: $searchPresented,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search stops, buses, stations")
        }
        // Present the system search field already focused — the user tapped the
        // Home search bar to get here.
        .onAppear { searchPresented = true }
    }

    /// Full-surface presentation (legacy `.search` route): the custom title +
    /// field. Retained for any caller that pushes Search as a full screen.
    private var customBody: some View {
        ZStack {
            // Tapping empty space dismisses the keyboard (there's no Done bar
            // on a plain TextField, so this + scroll-to-dismiss are the ways out).
            t.bg.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focused = false }

            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                fieldRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        resultsContent.padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                }
                // Dragging the results list down sweeps the keyboard away as it
                // goes — the expected "scroll to see more, keyboard hides" gesture.
                .scrollDismissesKeyboard(.interactively)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Search")
                .font(t.sans(30, weight: .bold))
                .foregroundStyle(t.fg)
            Spacer(minLength: 8)
            // Cancel only appears while editing so the user can dismiss the
            // keyboard without clearing the field. onClose is still reachable
            // from Cancel — callers that wire Search as a modal can still close.
            if focused {
                Button {
                    fb.select()
                    focused = false
                    query = ""
                } label: {
                    Text("Cancel")
                        .font(t.sans(14, weight: .medium))
                        .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: focused)
    }

    // MARK: Search field

    private var fieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(query.isEmpty ? t.dim : t.accent)

            TextField("Search for stops, services or places", text: $query)
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.fg)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(t.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Mic: visual affordance only — no speech recognition is wired.
                // Rendered as a plain Image (not a Button) so there is no dead tap target.
                Image(systemName: "mic")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(t.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(fieldFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(query.isEmpty ? t.line : t.accent.opacity(0.6), lineWidth: 1)
        )
    }

    /// iOS 26 Liquid Glass fill for the search field (the same `.regularMaterial`
    /// the tab bar / IOSGlassPill use); opaque surface fallback on iOS 25-.
    private var fieldFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            AnyShapeStyle(.regularMaterial)
        } else {
            AnyShapeStyle(t.surface)
        }
    }

    // MARK: Results / empty state router

    @ViewBuilder private var resultsContent: some View {
        if trimmed.isEmpty {
            emptyState
        } else if isPostal {
            postalResults
        } else {
            let services    = ds.searchServices(query)
            let stops       = ds.searchStops(query)
            let mrtStations = MrtGeo.stations(matching: trimmed)
            if services.isEmpty && stops.isEmpty && mrtStations.isEmpty {
                emptyHint("Nothing matches \"\(trimmed)\"",
                          "Try a stop name, a 5-digit stop code, a 6-digit postal code, a bus number, or an MRT station name.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    searchFilterControl
                        .padding(.bottom, 4)

                    let showBuses = searchFilter == .all || searchFilter == .buses
                    let showStops = searchFilter == .all || searchFilter == .stops
                    let showMrt   = searchFilter == .all || searchFilter == .mrt

                    // Per-filter empty hints when the chosen category has no hits
                    // but another category does. Global empty state is handled above.
                    if showBuses && services.isEmpty && searchFilter == .buses {
                        emptyHint("No buses match",
                                  "Try a different bus number or switch to All.")
                    }
                    if showStops && stops.isEmpty && searchFilter == .stops {
                        emptyHint("No stops match",
                                  "Try a stop name, a 5-digit stop code, or switch to All.")
                    }
                    if showMrt && mrtStations.isEmpty && searchFilter == .mrt {
                        emptyHint("No MRT stations match",
                                  "Try a station name or switch to All.")
                    }

                    if showBuses && !services.isEmpty {
                        sectionLabel("Services")
                        ForEach(services, id: \.ServiceNo) { svc in svcRow(svc) }
                    }
                    if showStops && !stops.isEmpty {
                        let topPad: CGFloat = (showBuses && !services.isEmpty) ? 6 : 0
                        sectionLabel("Bus stops").padding(.top, topPad)
                        ForEach(stops, id: \.BusStopCode) { stop in stopRow(stop: stop) }
                    }
                    if showMrt && !mrtStations.isEmpty {
                        let topPad: CGFloat = ((showBuses && !services.isEmpty) ||
                                               (showStops && !stops.isEmpty)) ? 6 : 0
                        sectionLabel("MRT stations").padding(.top, topPad)
                        ForEach(mrtStations) { station in mrtStationRow(station) }
                    }
                }
            }
        }
    }

    // MARK: Search filter segmented control

    private var searchFilterControl: some View {
        HStack(spacing: 0) {
            ForEach(SearchFilter.allCases, id: \.self) { filter in
                searchFilterPill(filter)
            }
        }
        .padding(3)
        .background(
            t.glassSurface()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
    }

    private func searchFilterPill(_ filter: SearchFilter) -> some View {
        let active = searchFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { searchFilter = filter }
        } label: {
            Text(filter.rawValue)
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

    // MARK: Empty state — recent searches (no Browse grid)

    @ViewBuilder private var emptyState: some View {
        if m.recents.isEmpty {
            searchPrompt
        } else {
            VStack(alignment: .leading, spacing: 24) {
                recentsSection
            }
            .padding(.top, 4)
        }
    }

    /// Quiet empty-state prompt shown when there are no recent searches. The
    /// Browse grid was removed — its tiles seeded hard-coded example queries
    /// (17179 / 96 / Clementi) that read as placeholder data.
    private var searchPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(t.faint)
                .padding(.bottom, 6)
            Text("Find a stop, bus or place")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
                .multilineTextAlignment(.center)
            Text("Search by stop name, 5-digit stop code, bus number, or 6-digit postal code.")
                .font(t.sans(12))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, 24)
    }

    // MARK: Recent searches — vertical list with swipe-to-remove

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: "Recent searches" + "Clear" button
            HStack {
                Eyebrow(text: "Recent searches", t: t)
                Spacer(minLength: 8)
                Button {
                    fb.tap()
                    withAnimation(.easeOut(duration: 0.2)) { m.clearRecents() }
                } label: {
                    Text("Clear")
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(t.meBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 2)

            VStack(spacing: 6) {
                ForEach(m.recents, id: \.self) { recent in
                    recentRow(recent)
                }
            }
        }
    }

    private func recentRow(_ recent: String) -> some View {
        let kind = detectQueryKind(recent).kind
        let icon: String = {
            switch kind {
            case "bus":      return "bus.fill"
            case "stopcode": return "mappin"
            case "postal",
                 "block",
                 "text":     return "location"
            default:         return "clock.arrow.circlepath"
            }
        }()

        return Button {
            fb.tap()
            query = recent
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.surfaceHi)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
                .frame(width: 32, height: 32)

                Text(recent)
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    fb.tap()
                    withAnimation(.easeOut(duration: 0.18)) { m.removeRecent(recent) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.faint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Section label

    private func sectionLabel(_ s: String) -> some View {
        Eyebrow(text: s, t: t).padding(.leading, 2).padding(.bottom, 2)
    }

    // MARK: Stop result row

    // Slim icon-led stop row — a square stop-pin tile distinguishes it from
    // Home's chunky StopCards.
    private func stopRow(stop: LTABusStop) -> some View {
        Button {
            fb.select(); m.addRecent(query); onOpenStop(stop.BusStopCode)
        } label: {
            HStack(spacing: 12) {
                stopTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.Description)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    Text(stop.RoadName.isEmpty ? "Stop \(stop.BusStopCode)"
                                               : "\(stop.BusStopCode) · \(stop.RoadName)")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private var stopTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surfaceHi)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(t.fg)
        }
        .frame(width: 34, height: 34)
    }

    // MARK: MRT station result row

    private func mrtStationRow(_ station: MrtGeoStation) -> some View {
        Button {
            fb.select()
            m.addRecent(station.name)
            onOpenMrtStation?(station)
        } label: {
            HStack(spacing: 12) {
                // Tram tile
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surfaceHi)
                    Image(systemName: "tram.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.fg)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    // Line-code pills
                    HStack(spacing: 4) {
                        ForEach(station.codes, id: \.self) { code in
                            Text(code)
                                .font(t.mono(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(mrtLineColorFor(code), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Service result row

    private func svcRow(_ svc: LTABusServiceDTO) -> some View {
        Button {
            fb.select()
            Task {
                if let s = await ds.originStop(ofService: svc.ServiceNo) {
                    await MainActor.run {
                        m.addRecent(svc.ServiceNo)
                        if let openBus = onOpenBus {
                            openBus(s.BusStopCode, svc.ServiceNo)
                        } else {
                            // Fallback: open the origin stop (legacy behaviour for
                            // callers that haven't wired onOpenBus yet).
                            onOpenStop(s.BusStopCode)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                ServiceBadge(svc: svc.ServiceNo, t: t, size: .sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service \(svc.ServiceNo)")
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(svc.Operator ?? "Bus service")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Postal results (6-digit → nearby stops within radius)

    @ViewBuilder private var postalResults: some View {
        if postalLoading {
            VStack(spacing: 10) {
                ProgressView().tint(t.dim)
                Text("Finding postal code \(trimmed)…")
                    .font(t.sans(13)).foregroundStyle(t.dim)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if let geo = postalGeo {
            let radius = m.searchRadiusM
            let stops = postalStops(geo: geo, radius: radius)
            VStack(alignment: .leading, spacing: 10) {
                postalSummary(geo: geo, count: stops.count, radius: radius)
                if stops.isEmpty {
                    let r = radius < 1000 ? "\(radius) m" : "\(radius / 1000) km"
                    emptyHint("No bus stops within \(r)", "Widen the search radius in Settings.")
                } else {
                    ForEach(stops) { s in
                        Button {
                            fb.select(); m.addRecent(geo.label); onOpenStop(s.stopCode)
                        } label: { postalStopRow(s) }
                            .buttonStyle(PressScaleButtonStyle())
                    }
                }
            }
        } else {
            emptyHint(postalFailed ? "Can't look up postal codes right now"
                                   : "Couldn't find postal code \(trimmed)",
                      postalFailed ? "OneMap didn't respond — check your connection."
                                   : "Check the 6-digit code and try again.")
        }
    }

    private func postalStops(geo: GeoPlace, radius: Int) -> [NearbyStop] {
        let r = Double(radius)
        return ds.stopByCode.values.compactMap { s -> NearbyStop? in
            let d = haversine(geo.lat, geo.lon, s.Latitude, s.Longitude)
            guard d <= r else { return nil }
            return NearbyStop(id: s.BusStopCode, stopName: s.Description, stopCode: s.BusStopCode,
                              distanceM: Int(d.rounded()), walkMin: max(1, Int((d / 80).rounded())),
                              services: ds.servicesFor(s.BusStopCode))
        }
        .sorted { $0.distanceM < $1.distanceM }
    }

    private func postalSummary(geo: GeoPlace, count: Int, radius: Int) -> some View {
        let countLabel = count == 1 ? "STOP" : "STOPS"
        let radiusLabel = radius < 1000 ? "\(radius)M" : "\(radius / 1000)KM"
        return VStack(alignment: .leading, spacing: 4) {
            Text("POSTAL \(geo.postalCode) · \(count) \(countLabel) · \(radiusLabel)")
                .font(t.mono(10, weight: .medium)).foregroundStyle(t.dim)
            Text(geo.label)
                .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func postalStopRow(_ s: NearbyStop) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(s.distanceM)").font(t.mono(15, weight: .semibold)).foregroundStyle(t.fg)
                    Text("m").font(t.mono(9)).foregroundStyle(t.dim)
                }
                Text("\(s.walkMin) MIN").font(t.mono(8)).foregroundStyle(t.faint)
            }
            .frame(width: 48)
            Rectangle().fill(t.line).frame(width: 1, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.stopName).font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg).lineLimit(1)
                Text("Stop \(s.stopCode)").font(t.mono(10)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(t.dim)
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyHint(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(t.sans(13, weight: .semibold)).foregroundStyle(t.fg)
                .multilineTextAlignment(.center)
            Text(sub).font(t.sans(11)).foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }

    // MARK: Geocode trigger — fires when the query is a fresh 6-digit code.

    private func maybeGeocode() {
        guard isPostal, postalGeoFor != trimmed else { return }
        postalGeoFor = trimmed
        postalGeo = nil
        postalFailed = false
        postalLoading = true
        Task {
            let result = await GeocodeService.shared.postalCode(trimmed)
            await MainActor.run {
                guard postalGeoFor == trimmed else { return }
                postalLoading = false
                if let r = result { postalGeo = r } else { postalFailed = true }
            }
        }
    }
}
