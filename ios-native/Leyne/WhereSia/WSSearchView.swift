// WhereSia — Search (screens 2 & 3).
//
// Presented modally over Home. Empty state: Recent searches. Typing: results
// (MRT stations / Bus stops / Bus services) collapsed into one flat, ranked
// card — station/service/stop matches interleaved by relevance group, the
// query term bolded; misspellings get a quiet "Did you mean …?" row. A
// 6-digit postal code geocodes to the nearest stops + MRT instead.
// Wired to DataStore.searchStops/searchServices + MrtGeo.
//
// Soft Blue "4b" pass (docs/soft-blue-design.md): search is a utility screen
// — NO hero, plain white result rows on the tinted ground. The field becomes
// a white rounded pill (white fill + SoftBlue shadow, not glass); Cancel
// reads in SoftBlue.blue. All search sourcing (stop name/code, bus number,
// postal geocode, recents, spellcheck) is unchanged — only how it's drawn.
// The sheet's own background chrome (.presentationBackground) is owned by
// WSRoot, not this view.

import SwiftUI
import CoreLocation

struct WSSearchView: View {
    var onSelect: (WSRoute) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws

    @State private var query = ""
    @State private var postal = PostalState.idle
    @FocusState private var focused: Bool

    private enum PostalState: Equatable {
        case idle, locating, failed
        case located(lat: Double, lon: Double)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isPostal: Bool { detectQueryKind(trimmed).kind == "postal" }

    // NATIVE search chrome (owner 2026-07-25): the hand-built white pill
    // field, its custom clear dot and the text "Cancel" are replaced by the
    // system `.searchable` bar in a real nav bar. That's the system's own
    // field, clear button, keyboard handling, dictation and scroll behaviour
    // — everything the custom field re-implemented by hand.
    var body: some View {
        NavigationStack {
            Group {
                if trimmed.isEmpty {
                    emptyState
                } else if isPostal {
                    postalResults
                        .task(id: trimmed) { await geocodePostal() }
                } else {
                    results
                }
            }
            .background(SoftBlue.bg.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Stop name, 5-digit code or bus no.")
            .searchFocused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
        }
        .onAppear { focused = true }
    }

    // MARK: empty state — the resting screen GUIDES instead of sitting empty
    // (owner 2026-07-25): recents first (personal), then a "Search by" card
    // teaching each query kind with a real tappable example seeded from the
    // user's surroundings, then the nearest stops for direct one-tap entry.

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !m.recents.isEmpty { recentsSection }
                searchGuide
                aroundYou
                Color.clear.frame(height: 90)
            }
        }
    }

    @ViewBuilder private var recentsSection: some View {
        HStack {
            Text("RECENT")
                .font(ws.sans(11, weight: .bold)).tracking(0.9).foregroundStyle(SoftBlue.sub)
            Spacer()
            Button { m.clearRecents() } label: {
                Text("Clear").font(ws.sans(12, weight: .semibold)).foregroundStyle(SoftBlue.sub)
            }.buttonStyle(SoftPressStyle())
        }
        .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)

        VStack(spacing: 0) {
            ForEach(Array(m.recents.enumerated()), id: \.element) { i, r in
                Button { query = r } label: {
                    HStack(spacing: 12) {
                        glyphTile(.search, tint: SoftBlue.sub)
                        Text(r).font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                        Spacer()
                        WSIcon(glyph: .chevron, size: 14, color: SoftBlue.sub)
                    }
                    .padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(SoftPressStyle())
                if i < m.recents.count - 1 {
                    Rectangle().fill(SoftBlue.hairline).frame(height: 1).padding(.leading, 46)
                }
            }
        }
        .padding(.horizontal, 15)
        .softCard(radius: 18)
        .padding(.horizontal, 18)
    }

    /// The teaching card: one row per query kind, each with a live example
    /// from the user's actual surroundings (falls back to canonical examples
    /// before location/data arrive). Tapping a row runs its example.
    @ViewBuilder private var searchGuide: some View {
        let nearest = store.nearby.first
        let stopName = nearest?.stopName ?? "Orchard Stn Exit 13"
        let stopCode = nearest?.stopCode ?? "09022"
        let busNo = nearest.flatMap { store.servicesAtStop($0.stopCode).first } ?? "174"

        resultsLabel("SEARCH BY")
            .padding(.top, m.recents.isEmpty ? 0 : 14)
        VStack(spacing: 0) {
            guideRow(glyph: .location, title: "Stop or station name",
                     example: stopName, divider: true)
            guideRow(glyph: .busSingle, title: "Bus number",
                     example: busNo, divider: true)
            guideRow(glyph: .scope, title: "5-digit stop code",
                     example: stopCode, divider: true)
            guideRow(glyph: .map, title: "Postal code — stops near an address",
                     example: "018956", divider: false)
        }
        .padding(.horizontal, 15)
        .softCard(radius: 18)
        .padding(.horizontal, 18)
    }

    private func guideRow(glyph: WSGlyph, title: String,
                          example: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            Button { query = example } label: {
                HStack(spacing: 12) {
                    glyphTile(glyph, tint: SoftBlue.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(ws.sans(14, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text("e.g. \(example)")
                            .font(ws.sans(11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(SoftBlue.sub).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("Try")
                        .font(ws.sans(12, weight: .bold)).foregroundStyle(SoftBlue.chipInk)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(SoftBlue.chipBg, in: Capsule())
                }
                .padding(.vertical, 11).contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
            if divider {
                Rectangle().fill(SoftBlue.hairline).frame(height: 1).padding(.leading, 46)
            }
        }
    }

    /// Nearest stops as direct destinations — the search sheet can answer
    /// "the stop in front of me" with zero typing.
    @ViewBuilder private var aroundYou: some View {
        let near = Array(store.nearby.prefix(3))
        if !near.isEmpty {
            resultsLabel("AROUND YOU").padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(near.enumerated()), id: \.element.id) { i, stop in
                    row(divider: i < near.count - 1) {
                        resultRow(stopTile(stop.stopCode), name: stop.stopName,
                                  sub: "\(stop.stopCode) · \(fmtDistance(stop.distanceM))") {
                            select(.busStop(code: stop.stopCode, service: nil), label: stop.stopName)
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .softCard(radius: 18)
            .padding(.horizontal, 18)
        }
    }

    // MARK: postal code → nearby stops + MRT

    private func geocodePostal() async {
        postal = .locating
        // Debounce: don't geocode every keystroke of a 6-digit entry.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let marks = try await CLGeocoder().geocodeAddressString("\(trimmed), Singapore")
            guard !Task.isCancelled else { return }
            if let c = marks.first?.location?.coordinate {
                postal = .located(lat: c.latitude, lon: c.longitude)
            } else {
                postal = .failed
            }
        } catch {
            if !Task.isCancelled { postal = .failed }
        }
    }

    @ViewBuilder private var postalResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch postal {
                case .idle, .locating:
                    hint("Locating \(trimmed)…").padding(.top, 26)
                case .failed:
                    hint("Couldn’t find postal code \(trimmed). Check the six digits and try again.")
                        .padding(.top, 26)
                case .located(let lat, let lon):
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let mrt = MrtGeo.nearestStations(to: coord, limit: 3, withinMeters: 1600)
                    let near = store.wsStopsNear(coord, limit: 8)
                    if mrt.isEmpty && near.isEmpty {
                        hint("Nothing near \(trimmed).").padding(.top, 26)
                    } else {
                        resultsLabel("NEAR \(trimmed.uppercased())")
                        VStack(spacing: 0) {
                            ForEach(Array(mrt.enumerated()), id: \.element.station.id) { i, item in
                                row(divider: i < mrt.count - 1 || !near.isEmpty) {
                                    resultRow(lineTile(item.station.codes.first ?? ""),
                                              name: item.station.name,
                                              sub: "\(fmtDistance(item.distanceM)) · \(item.walkMin) min walk") {
                                        select(.mrtStation(item.station), label: item.station.name)
                                    }
                                }
                            }
                            ForEach(Array(near.enumerated()), id: \.element.stop.BusStopCode) { i, item in
                                row(divider: i < near.count - 1) {
                                    resultRow(stopTile(item.stop.BusStopCode),
                                              name: item.stop.Description,
                                              sub: "\(item.stop.BusStopCode) · \(fmtDistance(item.distanceM))") {
                                        select(.busStop(code: item.stop.BusStopCode, service: nil), label: item.stop.Description)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 15)
                        .softCard(radius: 18)
                        .padding(.horizontal, 18)
                    }
                }
                Color.clear.frame(height: 90)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    // MARK: results (one ranked card: stations → services → stops)

    private var stations: [MrtGeoStation] { MrtGeo.stations(matching: trimmed) }
    private var services: [LTABusServiceDTO] { store.searchServices(trimmed) }
    private var stops: [LTABusStop] { store.searchStops(trimmed) }

    private var resultCount: Int {
        min(stations.count, 12) + min(services.count, 12) + min(stops.count, 30)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if resultCount > 0 {
                    resultsLabel("\(resultCount) RESULT\(resultCount == 1 ? "" : "S")")

                    let stationRows = Array(stations.prefix(12))
                    let serviceRows = Array(services.prefix(12))
                    let stopRows = Array(stops.prefix(30))
                    let total = stationRows.count + serviceRows.count + stopRows.count

                    VStack(spacing: 0) {
                        ForEach(Array(stationRows.enumerated()), id: \.element.id) { i, st in
                            row(divider: i + 1 < total) {
                                resultRow(lineTile(st.codes.first ?? ""), name: st.name,
                                          sub: "MRT station", highlighted: st.name) {
                                    select(.mrtStation(st), label: st.name)
                                }
                            }
                            .transition(.asymmetric(insertion: rise(delay(i)), removal: .opacity))
                        }
                        ForEach(Array(serviceRows.enumerated()), id: \.element.ServiceNo) { i, svc in
                            row(divider: stationRows.count + i + 1 < total) {
                                serviceRow(svc)
                            }
                            .transition(.asymmetric(insertion: rise(delay(stationRows.count + i)), removal: .opacity))
                        }
                        ForEach(Array(stopRows.enumerated()), id: \.element.BusStopCode) { i, stop in
                            let n = stationRows.count + serviceRows.count + i
                            row(divider: n + 1 < total) {
                                resultRow(stopTile(stop.BusStopCode), name: stop.Description,
                                          sub: "\(stop.BusStopCode) · \(stop.RoadName)", highlighted: stop.Description) {
                                    select(.busStop(code: stop.BusStopCode, service: nil), label: stop.Description)
                                }
                            }
                            .transition(.asymmetric(insertion: rise(delay(n)), removal: .opacity))
                        }
                    }
                    .padding(.horizontal, 15)
                    .softCard(radius: 18)
                    .padding(.horizontal, 18)
                    .animation(SoftMotion.flow, value: total)
                }

                if resultCount == 0 {
                    if let suggestion = WSSpell.suggest(for: trimmed, store: store) {
                        Button { query = suggestion } label: {
                            HStack(spacing: 12) {
                                glyphTile(.search, tint: SoftBlue.blue)
                                (Text("Did you mean ")
                                 + Text(suggestion).fontWeight(.bold)
                                 + Text("?"))
                                    .font(ws.sans(14, weight: .medium)).foregroundStyle(SoftBlue.blue)
                                Spacer()
                                WSIcon(glyph: .chevron, size: 14, color: SoftBlue.sub)
                            }
                            .padding(.vertical, 12).padding(.horizontal, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(SoftPressStyle())
                        .softCard(radius: 18)
                        .padding(.horizontal, 18).padding(.top, 20)
                    }
                    Text("Nothing matches “\(trimmed)”.\nTry a stop name, 5-digit code, or bus number.")
                        .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 44).padding(.top, 28)
                }
                Color.clear.frame(height: 90)
            }
        }
    }

    /// Staggered rise+fade for result rows — gated behind Reduce Motion by
    /// the transition itself never firing without an animation driving it.
    private func delay(_ i: Int) -> Double { min(Double(i) * 0.045, 0.24) }
    private func rise(_ delay: Double) -> AnyTransition {
        .opacity.combined(with: .offset(y: 8)).animation(SoftMotion.drift.delay(delay))
    }

    private func resultsLabel(_ text: String) -> some View {
        Text(text)
            .font(ws.sans(11, weight: .bold)).tracking(0.9).foregroundStyle(SoftBlue.sub)
            .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)
    }

    private func select(_ route: WSRoute, label: String) {
        m.addRecent(label)
        onSelect(route)
    }

    // MARK: rows

    private func row<Content: View>(divider: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
            if divider { Rectangle().fill(SoftBlue.hairline).frame(height: 1).padding(.leading, 46) }
        }
    }

    private func resultRow(_ tile: some View, name: String, sub: String?,
                            highlighted: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    if let highlighted {
                        wsHighlight(highlighted, query: trimmed)
                            .font(ws.sans(14.5, weight: .semibold))
                    } else {
                        Text(name).font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                    }
                    if let sub {
                        Text(sub).font(ws.sans(11, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    }
                }
                Spacer()
                WSIcon(glyph: .chevron, size: 14, color: SoftBlue.sub)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func serviceRow(_ svc: LTABusServiceDTO) -> some View {
        let dest = svc.DestinationCode.map { store.stopName($0) } ?? ""
        return Button {
            select(.serviceInfo(no: svc.ServiceNo, fromStop: nil), label: "Bus \(svc.ServiceNo)")
        } label: {
            HStack(spacing: 12) {
                Text(svc.ServiceNo)
                    .font(ws.sans(12.5, weight: .heavy))
                    .foregroundStyle(SoftBlue.chipInk)
                    .frame(width: 34, height: 34)
                    .background(SoftBlue.chipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Bus ") + wsHighlightRaw(svc.ServiceNo, query: trimmed))
                        .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                    Text(dest.isEmpty ? "Service" : "Service · to \(dest)")
                        .font(ws.sans(11, weight: .medium)).foregroundStyle(SoftBlue.sub)
                }
                Spacer()
                WSIcon(glyph: .chevron, size: 14, color: SoftBlue.sub)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    /// 34pt chipBg-tinted tile: the stop's top service number, or a stop
    /// glyph when it doesn't (yet) have live service data.
    private func stopTile(_ code: String) -> some View {
        let top = store.servicesAtStop(code).first
        return Group {
            if let top {
                Text(top).font(ws.sans(11.5, weight: .heavy)).minimumScaleFactor(0.7).lineLimit(1)
            } else {
                WSIcon(glyph: .busSingle, size: 15)
            }
        }
        .foregroundStyle(SoftBlue.chipInk)
        .frame(width: 34, height: 34)
        .background(SoftBlue.chipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 34pt line-coloured tile carrying an "M" mark for MRT results — line
    /// identity colour is unchanged (official MRT line colours are
    /// identity-only, never restyled by a screen's token system).
    private func lineTile(_ code: String) -> some View {
        Text("M")
            .font(ws.sans(13, weight: .heavy))
            .foregroundStyle(WSLine.onLine)
            .frame(width: 34, height: 34)
            .background(WSLine.color(forStationCode: code))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func glyphTile(_ glyph: WSGlyph, tint: Color) -> some View {
        WSIcon(glyph: glyph, size: 15, color: tint)
            .frame(width: 34, height: 34)
            .background(SoftBlue.chipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Query highlighting (bold the matched substring)

func wsHighlight(_ text: String, query: String) -> Text {
    wsHighlightRaw(text, query: query)
        .foregroundStyle(SoftBlue.ink)
}

func wsHighlightRaw(_ text: String, query: String) -> Text {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty,
          let range = text.range(of: q, options: .caseInsensitive) else {
        return Text(text)
    }
    let pre = String(text[text.startIndex..<range.lowerBound])
    let mid = String(text[range])
    let post = String(text[range.upperBound...])
    return Text(pre) + Text(mid).fontWeight(.heavy) + Text(post)
}
