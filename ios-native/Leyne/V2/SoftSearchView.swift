// SoftSearchView — Leyne Glance Phase 4: Search + Trip results.
//
// Layout when empty:
//   "Where to?" field (always focused-ready)
//   → "Plan a trip" row (opens TripResultsView sheet)
//   → saved-places quick row (Home / Work / Add — placeholder; no places model yet)
//   → recents list with swipe-to-remove
//   → NEARBY NOW board: compact DepartureCard rows for the closest stop's services
//
// Layout while querying:
//   → segmented type filter (All / Stops / Buses / MRT)
//   → rich typed result rows:
//       stop  — mappin glyph + name + code + live next-ETA chip
//       bus   — ServiceBadge leading + terminus
//       MRT   — MrtCodePill(s) + station name
//
// Postal code (6 digits): geocodes via OneMap → nearby stops within radius.
// All real search logic, recents, and result navigation preserved from Phase 3.
//
// IMPORTANT: the "Where to?" destination field and TripResultsView are UI-complete
// shells. The app has no routing engine. TripResultsView drives plausible derived
// itineraries built from real nearby stops and lines but those are NOT real journey
// plans. See TripResultsView.swift for the explicit shell notice.

import SwiftUI

struct SoftSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var query = ""
    let onClose: () -> Void
    let onOpenStop: (String) -> Void
    /// Called when the user taps a service result. Receives (originStopCode, serviceNo).
    var onOpenBus: ((String, String) -> Void)?
    /// Called when the user taps an MRT station result.
    var onOpenMrtStation: ((MrtGeoStation) -> Void)?

    @FocusState private var focused: Bool

    // Category filter — only active during non-postal text search.
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

    // Trip results sheet destination.
    @State private var tripDestination: String? = nil
    @State private var showTrip = false

    // Analytics guard — one event per distinct search session.
    @State private var loggedSearchSession = false

    private var t: Theme { m.t }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isPostal: Bool { detectQueryKind(trimmed).kind == "postal" }

    // MARK: Body

    var body: some View {
        ZStack {
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
                .scrollDismissesKeyboard(.interactively)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            ds.ensureRoutes()
        }
        .onChange(of: query) { _, newVal in
            maybeGeocode()
            if searchFilter != .all { searchFilter = .all }
            let hasQuery = !newVal.trimmingCharacters(in: .whitespaces).isEmpty
            if hasQuery, !loggedSearchSession {
                loggedSearchSession = true
                AnalyticsService.log(.searchPerformed)
            } else if !hasQuery {
                loggedSearchSession = false
            }
        }
        .sheet(isPresented: $showTrip) {
            TripResultsView(
                destination: tripDestination ?? "Destination",
                nearbyStops: ds.nearby,
                onOpenStop: { code in
                    showTrip = false
                    onOpenStop(code)
                },
                onOpenBus: { stopCode, svcNo in
                    showTrip = false
                    onOpenBus?(stopCode, svcNo)
                }
            )
            .environmentObject(m)
            .environmentObject(fb)
            .environmentObject(ds)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Search")
                .font(t.sans(30, weight: .bold))
                .foregroundStyle(t.fg)
            Spacer(minLength: 8)
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

            TextField("Search stops, services or places", text: $query)
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

    private var fieldFill: AnyShapeStyle {
        if #available(iOS 26.0, *) {
            AnyShapeStyle(.regularMaterial)
        } else {
            AnyShapeStyle(t.surface)
        }
    }

    // MARK: Results router

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

                    if showBuses && services.isEmpty && searchFilter == .buses {
                        emptyHint("No buses match", "Try a different bus number or switch to All.")
                    }
                    if showStops && stops.isEmpty && searchFilter == .stops {
                        emptyHint("No stops match", "Try a stop name, a 5-digit stop code, or switch to All.")
                    }
                    if showMrt && mrtStations.isEmpty && searchFilter == .mrt {
                        emptyHint("No MRT stations match", "Try a station name or switch to All.")
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

    // MARK: Segmented filter

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

    // MARK: Empty state (no query)

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Plan a trip" row — opens TripResultsView shell
            planTripRow
                .padding(.bottom, 12)

            // Saved-places quick row: Home / Work / Add
            // NOTE: No saved-places model exists in AppModel yet. These are
            // affordance-only placeholders that open the trip planner. When a
            // places model ships, swap these with real saved Place data.
            savedPlacesRow
                .padding(.bottom, 18)

            // Recents section
            if !m.recents.isEmpty {
                recentsSection
                    .padding(.bottom, 18)
            }

            // Nearby board
            nearbyNowBoard
        }
        .padding(.top, 4)
    }

    // "Plan a trip" trigger row (prototype .whereto)
    private var planTripRow: some View {
        Button {
            fb.tap()
            tripDestination = nil
            showTrip = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surfaceHi)
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.brand)
                }
                .frame(width: 36, height: 36)

                Text("Plan a trip — pick a destination")
                    .font(t.sans(15, weight: .medium))
                    .foregroundStyle(t.dim)

                Spacer(minLength: 0)

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

    // Prototype .places row: Home / Work / Add
    private var savedPlacesRow: some View {
        HStack(spacing: 10) {
            placePill(icon: "house.fill", label: "Home") {
                tripDestination = "Home"
                showTrip = true
            }
            placePill(icon: "briefcase.fill", label: "Work") {
                tripDestination = "Work"
                showTrip = true
            }
            placePill(icon: "plus", label: "Add", dashed: true) {
                // Placeholder — no places model yet; tapping is intentionally inert.
            }
        }
    }

    private func placePill(icon: String, label: String, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { fb.tap(); action() }) {
            VStack(spacing: 6) {
                ZStack {
                    if dashed {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                            .foregroundStyle(t.line)
                    } else {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(t.surface)
                            .shadow(color: Color(white: 0.04, opacity: 0.05), radius: 1, x: 0, y: 1)
                            .shadow(color: Color(white: 0.04, opacity: 0.06), radius: 10, x: 0, y: 6)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(dashed ? t.faint : t.brand)
                }
                .frame(width: 52, height: 52)

                Text(label)
                    .font(t.sans(12, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: Recents

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            case "postal", "block", "text": return "location"
            default: return "clock.arrow.circlepath"
            }
        }()

        return Button {
            fb.tap()
            query = recent
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surfaceHi)
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

    // MARK: Nearby Now board (live departures from closest stop)

    @ViewBuilder private var nearbyNowBoard: some View {
        // Only show when GPS has resolved at least one stop. (A @ViewBuilder
        // property can't early-return, so this is an `if let`, not a `guard`.)
        if let closest = ds.nearby.first {
            let arrivals = ds.arrivals[closest.stopCode]
            let feed = Freshness.from(ds.lastRefresh(closest.stopCode))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Nearby now", t: t)
                    Spacer(minLength: 0)
                    // Walk time chip
                    Text("\(closest.walkMin) min walk")
                        .font(t.sans(12, weight: .semibold))
                        .foregroundStyle(t.brand)
                }
                .padding(.leading, 2)

                // Show up to 3 live departure cards from the nearest stop.
                switch arrivals {
                case .loaded(let services):
                    let shown = services.prefix(3)
                    ForEach(Array(shown), id: \.id) { svc in
                        DepartureCard(
                            t: t,
                            service: svc,
                            stopCode: closest.stopCode,
                            feed: feed,
                            tick: m.tick,
                            followingEtas: followingEtas(for: svc),
                            onTap: {
                                fb.select()
                                onOpenBus?(closest.stopCode, svc.no)
                            }
                        )
                    }
                    if services.isEmpty {
                        nearbyEmptyHint
                    }

                case .loading, nil:
                    ForEach(0..<2, id: \.self) { _ in DepartureCardSkeleton(t: t) }

                case .empty, .error:
                    nearbyEmptyHint
                }
            }
            .onAppear {
                ds.ensureArrivals(stop: closest.stopCode)
            }
        }
    }

    /// Extract the 2nd and 3rd-bus ETA seconds from the same stop's arrivals,
    /// for the DepartureCard "then X · Y min" sub-row.
    private func followingEtas(for svc: Service) -> [Int] {
        var result: [Int] = []
        if svc.followingSec > 0 { result.append(svc.followingSec) }
        if let third = svc.thirdDate.map({ Int($0.timeIntervalSinceNow) }), third > 0 {
            result.append(third)
        }
        return result
    }

    private var nearbyEmptyHint: some View {
        Text("No departures right now")
            .font(t.sans(13))
            .foregroundStyle(t.dim)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    // MARK: Section label

    private func sectionLabel(_ s: String) -> some View {
        Eyebrow(text: s, t: t).padding(.leading, 2).padding(.bottom, 2)
    }

    // MARK: Rich result rows — Stop

    private func stopRow(stop: LTABusStop) -> some View {
        // Warm arrivals so the next-ETA chip can populate as the user browses.
        let _ = { ds.ensureArrivals(stop: stop.BusStopCode, silent: true) }()
        let arrivals = ds.arrivals[stop.BusStopCode]
        let nextEtaText: String? = {
            if case .loaded(let svcs) = arrivals, let first = svcs.first {
                let e = fmtETA(first.etaSec)
                return e.big == "Arr" ? "Arr" : "\(e.big) min"
            }
            return nil
        }()

        return Button {
            fb.select()
            m.addRecent(query)
            onOpenStop(stop.BusStopCode)
        } label: {
            HStack(spacing: 12) {
                // Pin tile
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surfaceHi)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.fg)
                }
                .frame(width: 34, height: 34)

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

                // Live next-ETA chip when available
                if let eta = nextEtaText {
                    Text(eta)
                        .font(t.rounded(12, .bold).monospacedDigit())
                        .foregroundStyle(eta == "Arr" ? t.go : t.fg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (eta == "Arr" ? t.go.opacity(0.12) : t.surfaceHi),
                            in: Capsule()
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Rich result rows — MRT station

    private func mrtStationRow(_ station: MrtGeoStation) -> some View {
        Button {
            fb.select()
            m.addRecent(station.name)
            onOpenMrtStation?(station)
        } label: {
            HStack(spacing: 12) {
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

    // MARK: Rich result rows — Bus service
    //
    // The route badge IS the leading element (prototype spec: "bus: route badge
    // leading + terminus"). ServiceBadge(.sm) — 36×36 ink square.

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
                            onOpenStop(s.BusStopCode)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Badge IS the leading icon (prototype spec)
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

    // MARK: Postal results

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

    // MARK: Geocode trigger

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
