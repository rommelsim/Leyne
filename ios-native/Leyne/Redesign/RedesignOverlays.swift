// Overlays drawn above the app content (iOS): the full-screen Search sheet, the
// Live Update glass tracking card, and the Toast snackbar.

import SwiftUI
import MapKit

// =================================================================== SEARCH

struct RDSearchOverlay: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore
    @State private var query = ""
    // Building/place hits (MapKit) + a "focused location" (a tapped place or a
    // geocoded postal code) whose nearby stops/stations we then list.
    @State private var places: [MKMapItem] = []
    @State private var focusTitle: String? = nil
    @State private var focusLat: Double = 0
    @State private var focusLon: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button(action: { m.closeSearch() }) { RDSym("arrow.left", size: 23, color: t.onSurface) }
                    .buttonStyle(.plain)
                TextField("Stops · buses · MRT · postal · places", text: $query)
                    .focused($focused)
                    .font(rdFont(16, .medium))
                    .foregroundStyle(t.onSurface)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button(action: { query = ""; places = []; focusTitle = nil }) {
                        RDSym("xmark", size: 22, color: t.onVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 54)
            .background(t.scHigh).clipShape(Capsule())
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    let q = query.trimmingCharacters(in: .whitespaces)
                    if q.isEmpty { hint } else { results(q) }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(t.surface.ignoresSafeArea())
        .onAppear { focused = true }
        .task(id: query) { await runSearch() }
    }

    /// A 6-digit postal code geocodes straight to a focused location; anything
    /// else runs a MapKit place/building search (biased to Singapore). Cancels
    /// automatically as the query changes (via `.task(id:)`), so it debounces.
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        focusTitle = nil
        guard q.count >= 3 else { places = []; return }
        if q.count == 6, q.allSatisfy(\.isNumber) {
            places = []
            if let c = try? await CLGeocoder().geocodeAddressString("Singapore \(q)").first?.location?.coordinate {
                focusTitle = "Postal \(q)"; focusLat = c.latitude; focusLon = c.longitude
            }
            return
        }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
                                        span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7))
        if let resp = try? await MKLocalSearch(request: req).start() {
            places = Array(resp.mapItems.prefix(6))
        } else {
            places = []
        }
    }

    /// Bus stops within ~700 m of a coordinate, nearest first.
    private func stopsNear(_ lat: Double, _ lon: Double, limit: Int = 8) -> [LTABusStop] {
        store.stopByCode.values
            .map { ($0, haversine(lat, lon, $0.Latitude, $0.Longitude)) }
            .filter { $0.1 <= 700 }
            .sorted { $0.1 < $1.1 }
            .prefix(limit).map { $0.0 }
    }

    private var hint: some View {
        VStack(spacing: 8) {
            RDSym("magnifyingglass", size: 30, color: t.outline)
            Text("Search for a stop, bus number or MRT station")
                .font(rdFont(13, .medium)).foregroundStyle(t.onVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 40)
    }

    @ViewBuilder private func results(_ q: String) -> some View {
        if let title = focusTitle {
            nearResults(title: title, lat: focusLat, lon: focusLon)
        } else {
            let services = store.searchServices(q)
            let stations = MrtGeo.stations(matching: q)
            let stops = store.searchStops(q)
            if services.isEmpty && stations.isEmpty && stops.isEmpty && places.isEmpty {
                Text("No matches for “\(q)”")
                    .font(rdFont(13, .medium)).foregroundStyle(t.onVariant)
                    .frame(maxWidth: .infinity).padding(.top, 50)
            } else {
                if !services.isEmpty {
                    label("BUSES")
                    ForEach(services.prefix(6), id: \.ServiceNo) { svc in
                        resultRow(t.primaryContainer, t.onPrimaryContainer, "bus.fill",
                                  "Bus ", svc.ServiceNo, "Tap to see the route") { openBus(svc.ServiceNo) }
                    }
                }
                if !stations.isEmpty {
                    label("MRT / LRT")
                    ForEach(Array(stations.prefix(6))) { st in
                        let code = st.codes.first ?? ""
                        resultRow(mrtLineColorFor(code), rdMrtBadgeFg(code), "tram.fill",
                                  st.name, "", st.codes.joined(separator: " · ")) { m.openStation(named: st.name) }
                    }
                }
                if !stops.isEmpty {
                    label("STOPS")
                    ForEach(stops.prefix(10), id: \.BusStopCode) { s in
                        resultRow(t.busContainer, t.onBusContainer, "signpost.right.fill",
                                  s.Description, "", "\(s.RoadName) · \(s.BusStopCode)") { m.openStop(code: s.BusStopCode) }
                    }
                }
                if !places.isEmpty {
                    label("PLACES")
                    ForEach(places, id: \.self) { item in placeRow(item) }
                }
            }
        }
    }

    /// A building / place hit — tapping it drills into the stops near it.
    private func placeRow(_ item: MKMapItem) -> some View {
        let name = item.name ?? "Place"
        let c = item.placemark.coordinate
        return resultRow(t.amberContainer, t.onAmberContainer, "building.2.fill",
                         name, "", item.placemark.title ?? "See nearby stops") {
            focusTitle = name; focusLat = c.latitude; focusLon = c.longitude
        }
    }

    /// "Near <place/postal>" — the bus stops and MRT stations around a focused
    /// location (a tapped place or a geocoded postal code).
    @ViewBuilder private func nearResults(title: String, lat: Double, lon: Double) -> some View {
        Button(action: { focusTitle = nil }) {
            HStack(spacing: 6) {
                RDSym("chevron.left", size: 15, color: t.primary)
                Text("Near \(title)").font(rdFont(13, .bold)).foregroundStyle(t.primary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        let stops = stopsNear(lat, lon)
        let stations = MrtGeo.nearestStations(
            to: CLLocationCoordinate2D(latitude: lat, longitude: lon), limit: 3, withinMeters: 1000)
        if stops.isEmpty && stations.isEmpty {
            Text("No stops within walking distance")
                .font(rdFont(13, .medium)).foregroundStyle(t.onVariant)
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            if !stops.isEmpty {
                label("BUS STOPS")
                ForEach(stops, id: \.BusStopCode) { s in
                    let d = Int(haversine(lat, lon, s.Latitude, s.Longitude).rounded())
                    resultRow(t.busContainer, t.onBusContainer, "signpost.right.fill",
                              s.Description, "", "\(max(1, d / 80)) min walk · \(s.RoadName)") { m.openStop(code: s.BusStopCode) }
                }
            }
            if !stations.isEmpty {
                label("MRT / LRT")
                ForEach(stations, id: \.station.id) { item in
                    let st = item.station; let code = st.codes.first ?? ""
                    resultRow(mrtLineColorFor(code), rdMrtBadgeFg(code), "tram.fill",
                              st.name, "", "\(item.walkMin) min walk") { m.openStation(named: st.name) }
                }
            }
        }
    }

    private func openBus(_ svc: String) {
        Task {
            let origin = await store.originStop(ofService: svc)
            await MainActor.run { m.openBus(service: svc, stopCode: origin?.BusStopCode) }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(rdFont(12, .bold)).foregroundStyle(t.onVariant)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
    }

    private func resultRow(_ iconBg: Color, _ iconColor: Color, _ symbol: String,
                           _ bold: String, _ rest: String, _ sub: String,
                           _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 13) {
                RDSym(symbol, size: 20, color: iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconBg).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    (Text(bold).font(rdFont(15, .bold)) + Text(rest).font(rdFont(15, .semibold)))
                        .foregroundStyle(t.onSurface).lineLimit(1)
                    Text(sub).font(rdFont(12, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                }
                Spacer()
                RDSym("arrow.up.left", size: 16, color: t.outline)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ============================================================== LIVE UPDATE

struct RDLiveUpdate: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore
    @State private var live = true

    private let accent = rdHex("9CC0FF")
    private let onAccent = rdHex("10245E")

    private var svc: String { m.activeService ?? "" }
    private var trackedStop: String { m.activeRouteStop.map { store.stopName($0) } ?? "your stop" }
    private var etaLabel: String {
        guard let code = m.activeRouteStop,
              let s = store.servicesFor(code).first(where: { $0.no == svc }) else { return "—" }
        return rdMinLabel(s.etaSec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [rdHex("2C72E6"), rdHex("222A38")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay(HStack(spacing: 0) {
                        RDSym("bus.fill", size: 8, color: .white)
                        RDSym("tram.fill", size: 8, color: .white)
                    })
                Text("SG Transit").font(rdFont(12, .bold)).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 4) {
                    RDDot(color: accent, size: 5).opacity(live ? 1 : 0.3)
                    Text("LIVE").font(rdFont(10, .heavy)).foregroundStyle(accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(accent.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Button(action: { m.dismissLU() }) { RDSym("xmark", size: 18, color: .white.opacity(0.55)) }
                    .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bus \(svc) → your stop").font(rdFont(16, .bold)).foregroundStyle(.white)
                    Text("Approaching \(trackedStop)").font(rdFont(12.5, .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(etaLabel).font(rdFont(36, .black)).foregroundStyle(accent)
                    Text("min").font(rdFont(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 12)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(accent).frame(width: geo.size.width * 0.78, height: 6)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent)
                        .frame(width: 18, height: 18)
                        .overlay(RDSym("bus.fill", size: 11, color: onAccent))
                        .offset(x: geo.size.width * 0.78 - 9)
                }
            }
            .frame(height: 18)
            .padding(.bottom, 14)

            HStack(spacing: 9) {
                Button(action: { m.stopTrack() }) {
                    HStack(spacing: 7) {
                        RDSym("stop.circle", size: 18, color: .white)
                        Text("Stop").font(rdFont(13.5, .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                }.buttonStyle(.plain)
                Button(action: { m.luView() }) {
                    HStack(spacing: 7) {
                        RDSym("map.fill", size: 18, color: onAccent)
                        Text("View route").font(rdFont(13.5, .bold)).foregroundStyle(onAccent)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(accent).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(rdHex("14121C").opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 16)
        .padding(.horizontal, 10).padding(.top, 8)
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever()) { live = false } }
    }
}

// ==================================================================== TOAST

struct RDToast: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens

    var body: some View {
        HStack(spacing: 12) {
            RDSym("bell.fill", size: 21, color: rdHex("9CC0FF"))
            Text(m.toast ?? "").font(rdFont(12.5, .medium)).foregroundStyle(rdHex("E9E5EE"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { m.dismissToast() }) {
                Text("Got it").font(rdFont(13, .bold)).foregroundStyle(rdHex("9CC0FF"))
            }.buttonStyle(.plain)
        }
        .padding(.leading, 15).padding(.trailing, 14).padding(.vertical, 13)
        .background(rdHex("2C2A33"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 17, x: 0, y: 14)
        .padding(.horizontal, 12)
    }
}
