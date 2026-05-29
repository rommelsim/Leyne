// SoftSearchView — Leyne 2.0 Search: pill input + filter chips + result rows.
//
// Each filter chip does what it says (no decorative chips):
//   • Postal  → OneMap geocode the 6-digit code, list bus stops within the
//               Settings search radius, nearest first.
//   • Stop ID → stop-code / name match.
//   • Bus #   → matching bus services; tapping opens the service's origin stop.
//   • Place   → stop name / road match.

import SwiftUI

enum SearchFilter: Hashable { case postal, stopID, busNo, place }

struct SoftSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var query = ""
    @State private var filter: SearchFilter = .stopID
    let onClose: () -> Void
    let onOpenStop: (String) -> Void

    @FocusState private var focused: Bool

    // Postal-code geocode state. `postalGeoFor` is the code the current
    // `postalGeo` resolved for, so re-typing the same code doesn't burn a
    // fresh OneMap request and a stale async result is ignored.
    @State private var postalGeo: GeoPlace?
    @State private var postalGeoFor: String?
    @State private var postalLoading = false
    @State private var postalFailed = false

    private var t: Theme { m.t }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                searchBar
                SortChipRow(t: t, selection: $filter, options: [
                    (.postal, "Postal"),
                    (.stopID, "Stop ID"),
                    (.busNo, "Bus #"),
                    (.place, "Place"),
                ])

                if !query.isEmpty {
                    Text(detectedLine)
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                }

                ScrollView {
                    resultsContent
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in maybeGeocode() }
        .onChange(of: filter) { _, _ in maybeGeocode() }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(t.dim)
                TextField("Postal · Stop ID · Bus# · Place",
                          text: $query)
                    .font(t.mono(14))
                    .foregroundStyle(t.fg)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(t.dim)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                fb.select()
                onClose()
            } label: {
                Text("Cancel")
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.accent)
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Results router

    @ViewBuilder private var resultsContent: some View {
        if query.isEmpty {
            EmptyView()
        } else {
            switch filter {
            case .postal:
                postalResults
            case .busNo:
                busResults
            case .stopID, .place:
                stopResults
            }
        }
    }

    private var detectedLine: String {
        switch filter {
        case .postal: return "Postal · \(query)"
        case .stopID: return "Stop · \(query)"
        case .busNo:  return "Bus · \(query)"
        case .place:  return "Place · \(query)"
        }
    }

    // MARK: - Stop / Place results

    @ViewBuilder private var stopResults: some View {
        let stops = ds.searchStops(query)
        VStack(spacing: 8) {
            if stops.isEmpty {
                emptyHint("Nothing matches “\(query)”",
                          "Try a stop name or 5-digit stop code.")
            }
            ForEach(stops, id: \.BusStopCode) { stop in
                resultRow(stop: stop)
            }
        }
    }

    private func resultRow(stop: LTABusStop) -> some View {
        Button {
            fb.select()
            m.addRecent(query)
            onOpenStop(stop.BusStopCode)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.Description)
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(2)
                    Text("Stop \(stop.BusStopCode) · \(stop.RoadName)")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Bus # results (matching services → origin stop)

    @ViewBuilder private var busResults: some View {
        let services = ds.searchServices(query)
        VStack(spacing: 8) {
            if services.isEmpty {
                emptyHint("No bus service matches “\(query)”",
                          "Enter a service number, e.g. 88 or 970.")
            }
            ForEach(services, id: \.ServiceNo) { svc in
                Button {
                    fb.select()
                    Task {
                        if let s = await ds.originStop(ofService: svc.ServiceNo) {
                            await MainActor.run {
                                m.addRecent(svc.ServiceNo)
                                onOpenStop(s.BusStopCode)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ServiceBadge(svc: svc.ServiceNo, t: t, size: .sm)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Service \(svc.ServiceNo)")
                                .font(t.sans(14, weight: .semibold))
                                .foregroundStyle(t.fg)
                            Text(svc.Operator ?? "Bus service")
                                .font(t.mono(11))
                                .foregroundStyle(t.dim)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(t.dim)
                    }
                    .padding(14)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    // MARK: - Postal results (6-digit code → nearby stops within radius)

    @ViewBuilder private var postalResults: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if detectQueryKind(trimmed).kind != "postal" {
            emptyHint("Enter a 6-digit postal code",
                      "e.g. 120338 — we’ll show the bus stops nearby.")
        } else if postalLoading {
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
                    emptyHint("No bus stops within \(r)",
                              "Widen the search radius in Settings.")
                } else {
                    ForEach(stops) { s in
                        Button {
                            fb.select()
                            m.addRecent(geo.label)
                            onOpenStop(s.stopCode)
                        } label: { postalStopRow(s) }
                            .buttonStyle(PressScaleButtonStyle())
                    }
                }
            }
        } else {
            emptyHint(postalFailed ? "Can’t look up postal codes right now"
                                   : "Couldn’t find postal code \(trimmed)",
                      postalFailed ? "OneMap didn’t respond — check your connection."
                                   : "Check the 6-digit code and try again.")
        }
    }

    private func postalStops(geo: GeoPlace, radius: Int) -> [NearbyStop] {
        let r = Double(radius)
        return ds.stopByCode.values.compactMap { s -> NearbyStop? in
            let d = haversine(geo.lat, geo.lon, s.Latitude, s.Longitude)
            guard d <= r else { return nil }
            return NearbyStop(
                id: s.BusStopCode,
                stopName: s.Description,
                stopCode: s.BusStopCode,
                distanceM: Int(d.rounded()),
                walkMin: max(1, Int((d / 80).rounded())),
                services: ds.servicesFor(s.BusStopCode))
        }
        .sorted { $0.distanceM < $1.distanceM }
    }

    private func postalSummary(geo: GeoPlace, count: Int, radius: Int) -> some View {
        let countLabel = count == 1 ? "STOP" : "STOPS"
        let radiusLabel = radius < 1000 ? "\(radius)M" : "\(radius / 1000)KM"
        return VStack(alignment: .leading, spacing: 4) {
            Text("POSTAL \(geo.postalCode) · \(count) \(countLabel) · \(radiusLabel)")
                .font(t.mono(10, weight: .medium))
                .foregroundStyle(t.dim)
            Text(geo.label)
                .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(t.mono(8)).foregroundStyle(t.faint)
            }
            .frame(width: 48)
            Rectangle().fill(t.line).frame(width: 1, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.stopName)
                    .font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
                    .lineLimit(1)
                Text("Stop \(s.stopCode)")
                    .font(t.mono(10)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundStyle(t.dim)
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyHint(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(t.sans(13, weight: .semibold)).foregroundStyle(t.fg)
                .multilineTextAlignment(.center)
            Text(sub)
                .font(t.sans(11)).foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }

    // MARK: - Geocode trigger

    /// Fire a OneMap lookup when the Postal filter is active and the query is
    /// a fresh 6-digit code. Idempotent and stale-safe.
    private func maybeGeocode() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard filter == .postal,
              detectQueryKind(trimmed).kind == "postal",
              postalGeoFor != trimmed else { return }
        postalGeoFor = trimmed
        postalGeo = nil
        postalFailed = false
        postalLoading = true
        Task {
            let result = await GeocodeService.shared.postalCode(trimmed)
            await MainActor.run {
                guard postalGeoFor == trimmed else { return } // superseded
                postalLoading = false
                if let r = result { postalGeo = r } else { postalFailed = true }
            }
        }
    }
}
