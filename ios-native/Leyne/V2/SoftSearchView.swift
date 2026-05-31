// SoftSearchView — Leyne 3.0 Search: its own focused "Find" surface (not a
// Home clone) — a prominent field, tap-to-fill example chips, and results
// auto-split into Services + Bus stops. Input kind is auto-detected (no
// mode tabs), mirroring the prototype; a 6-digit query geocodes via OneMap
// and lists nearby stops. All the real search logic is preserved.

import SwiftUI

struct SoftSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var query = ""
    let onClose: () -> Void
    let onOpenStop: (String) -> Void

    @FocusState private var focused: Bool

    // Postal-code geocode state (stale-safe).
    @State private var postalGeo: GeoPlace?
    @State private var postalGeoFor: String?
    @State private var postalLoading = false
    @State private var postalFailed = false

    private var t: Theme { m.t }

    private let examples: [(value: String, kind: String)] = [
        ("17179", "code"), ("120338", "postal"), ("Clementi", "place"), ("96", "bus"),
    ]

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isPostal: Bool { detectQueryKind(trimmed).kind == "postal" }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Find", t: t).padding(.leading, 2)
                fieldRow
                exampleChips

                ScrollView {
                    resultsContent.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in maybeGeocode() }
    }

    // MARK: Field + examples

    private var fieldRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(query.isEmpty ? t.dim : t.accent)
                TextField("Stop code, postal code, or place", text: $query)
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
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(query.isEmpty ? t.line : t.accent.opacity(0.6), lineWidth: 1))

            Button { fb.select(); onClose() } label: {
                Text("Cancel")
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.accent)
            }.buttonStyle(.plain)
        }
    }

    private var exampleChips: some View {
        HStack(spacing: 7) {
            ForEach(examples, id: \.value) { ex in
                Button { fb.tap(); query = ex.value } label: {
                    HStack(spacing: 5) {
                        Text(ex.value)
                            .font(t.mono(12.5, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(ex.kind.uppercased())
                            .font(t.mono(9, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(t.faint)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 29)
                    .background(t.surface, in: Capsule())
                    .overlay(Capsule().stroke(t.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Results

    @ViewBuilder private var resultsContent: some View {
        if trimmed.isEmpty {
            EmptyView()
        } else if isPostal {
            postalResults
        } else {
            let services = ds.searchServices(query)
            let stops = ds.searchStops(query)
            if services.isEmpty && stops.isEmpty {
                emptyHint("Nothing matches “\(trimmed)”",
                          "Try a stop name, a 5-digit stop code, a 6-digit postal code, or a bus number.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !services.isEmpty {
                        sectionLabel("Services")
                        ForEach(services, id: \.ServiceNo) { svc in svcRow(svc) }
                    }
                    if !stops.isEmpty {
                        sectionLabel("Bus stops").padding(.top, services.isEmpty ? 0 : 6)
                        ForEach(stops, id: \.BusStopCode) { stop in stopRow(stop: stop) }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Eyebrow(text: s, t: t).padding(.leading, 2).padding(.bottom, 2)
    }

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

    private func svcRow(_ svc: LTABusServiceDTO) -> some View {
        Button {
            fb.select()
            Task {
                if let s = await ds.originStop(ofService: svc.ServiceNo) {
                    await MainActor.run { m.addRecent(svc.ServiceNo); onOpenStop(s.BusStopCode) }
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
