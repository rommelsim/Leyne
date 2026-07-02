// WhereSia — Search (screens 2 & 3).
//
// Presented modally over Home. Empty state: Recent searches. Typing: results
// grouped by type (MRT stations / Bus stops / Bus services) with the query
// term bolded and type filter chips; misspellings get a "Did you mean …?"
// row. A 6-digit postal code geocodes to the nearest stops + MRT instead.
// Wired to DataStore.searchStops/searchServices + MrtGeo.

import SwiftUI
import CoreLocation

struct WSSearchView: View {
    var onSelect: (WSRoute) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws

    @State private var query = ""
    @State private var filter = 0     // 0 All · 1 Bus · 2 MRT · 3 Stops
    @State private var postal = PostalState.idle
    @FocusState private var focused: Bool

    private enum PostalState: Equatable {
        case idle, locating, failed
        case located(lat: Double, lon: Double)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isPostal: Bool { detectQueryKind(trimmed).kind == "postal" }

    var body: some View {
        VStack(spacing: 0) {
            field
            if trimmed.isEmpty {
                emptyState
            } else if isPostal {
                postalResults
                    .task(id: trimmed) { await geocodePostal() }
            } else {
                WSFilterChips(options: ["All", "Bus", "MRT", "Stops"], selection: $filter)
                    .padding(.horizontal, 22).padding(.top, 14)
                results
            }
        }
        .background(ws.bg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    // MARK: search field

    private var field: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                WSIcon(glyph: .search, size: 18, color: ws.dim)
                TextField("", text: $query, prompt:
                    Text("Stop, bus, MRT or postal code").foregroundStyle(ws.dim))
                    .font(ws.sans(15, weight: .semibold))
                    .foregroundStyle(ws.text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        WSIcon(glyph: .close, size: 11, color: ws.dim)
                            .frame(width: 20, height: 20)
                            .background(ws.panel2)
                            .overlay(Circle().stroke(ws.rule, lineWidth: 1))
                            .clipShape(Circle())
                            // Visual stays a tight 20×20 dot; tap target grows to 44×44.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(ws.input)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.text, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(action: onClose) {
                Text("Cancel").font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.dim)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 14)
    }

    // MARK: empty state (recent searches)

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Try a stop name, bus number, MRT station or postal code.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 16)

                if !m.recents.isEmpty {
                    HStack {
                        WSSectionHeader(label: "Recent")
                        Button { m.clearRecents() } label: {
                            Text("CLEAR").font(ws.mono(11)).tracking(0.6).foregroundStyle(ws.dim)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)

                    ForEach(m.recents, id: \.self) { r in
                        Button { query = r } label: {
                            HStack(spacing: 13) {
                                iconWell(.search)
                                Text(r).font(ws.sans(15, weight: .bold)).foregroundStyle(ws.text)
                                Spacer()
                                WSIcon(glyph: .chevron, size: 18, color: ws.faint)
                            }
                            .padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .padding(.horizontal, 22)
                        WSRowDivider().padding(.horizontal, 22)
                    }
                }
            }
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
            LazyVStack(spacing: 0) {
                switch postal {
                case .idle, .locating:
                    hint("Locating \(trimmed)…")
                case .failed:
                    hint("Couldn’t find postal code \(trimmed). Check the six digits and try again.")
                case .located(let lat, let lon):
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let mrt = MrtGeo.nearestStations(to: coord, limit: 3, withinMeters: 1600)
                    let near = store.wsStopsNear(coord, limit: 8)
                    if mrt.isEmpty && near.isEmpty {
                        hint("Nothing near \(trimmed).")
                    }
                    if !mrt.isEmpty {
                        WSSectionHeader(label: "MRT near \(trimmed)")
                            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                        ForEach(mrt, id: \.station.id) { item in
                            resultRow(icon: .train, name: item.station.name,
                                      sub: "\(fmtDistance(item.distanceM).uppercased()) · \(item.walkMin) MIN WALK",
                                      codes: item.station.codes) {
                                select(.mrtStation(item.station), label: item.station.name)
                            }
                        }
                    }
                    if !near.isEmpty {
                        WSSectionHeader(label: "Bus stops near \(trimmed)")
                            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                        ForEach(near, id: \.stop.BusStopCode) { item in
                            resultRow(icon: .busSingle, name: item.stop.Description,
                                      sub: "\(item.stop.BusStopCode) · \(item.stop.RoadName.uppercased()) · \(fmtDistance(item.distanceM).uppercased())",
                                      codes: []) {
                                select(.busStop(code: item.stop.BusStopCode), label: item.stop.Description)
                            }
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(ws.sans(14, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 30)
    }

    // MARK: results

    private var stations: [MrtGeoStation] { MrtGeo.stations(matching: trimmed) }
    private var stops: [LTABusStop] { store.searchStops(trimmed) }
    private var services: [LTABusServiceDTO] { store.searchServices(trimmed) }

    private var showStations: Bool { filter == 0 || filter == 2 }
    private var showStops: Bool { filter == 0 || filter == 3 }
    private var showServices: Bool { filter == 0 || filter == 1 }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if showStations && !stations.isEmpty {
                    WSSectionHeader(label: "MRT stations")
                        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                    ForEach(stations.prefix(12)) { st in
                        resultRow(icon: .train, name: st.name, sub: nil, codes: st.codes) {
                            select(.mrtStation(st), label: st.name)
                        }
                    }
                }
                if showServices && !services.isEmpty {
                    WSSectionHeader(label: "Bus services")
                        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                    ForEach(services.prefix(12), id: \.ServiceNo) { svc in
                        serviceRow(svc)
                    }
                }
                if showStops && !stops.isEmpty {
                    WSSectionHeader(label: "Bus stops", meta: "\(stops.count)")
                        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                    ForEach(stops.prefix(30), id: \.BusStopCode) { stop in
                        resultRow(icon: .busSingle, name: stop.Description,
                                  sub: "\(stop.BusStopCode) · \(stop.RoadName.uppercased())", codes: []) {
                            select(.busStop(code: stop.BusStopCode), label: stop.Description)
                        }
                    }
                }
                if noResults {
                    if let suggestion = WSSpell.suggest(for: trimmed, store: store) {
                        Button { query = suggestion } label: {
                            HStack(spacing: 13) {
                                iconWell(.search)
                                (Text("Did you mean ")
                                 + Text(suggestion).fontWeight(.heavy)
                                 + Text("?"))
                                    .font(ws.sans(15, weight: .medium)).foregroundStyle(ws.text)
                                Spacer()
                                WSIcon(glyph: .chevron, size: 18, color: ws.faint)
                            }
                            .padding(.vertical, 13).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 22).padding(.top, 12)
                        WSRowDivider().padding(.horizontal, 22)
                    }
                    Text("No matches for “\(trimmed)”.")
                        .font(ws.sans(14, weight: .medium)).foregroundStyle(ws.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 16)
                }
                Color.clear.frame(height: 24)
            }
        }
    }

    private var noResults: Bool {
        !trimmed.isEmpty
            && (!showStations || stations.isEmpty)
            && (!showStops || stops.isEmpty)
            && (!showServices || services.isEmpty)
    }

    private func select(_ route: WSRoute, label: String) {
        m.addRecent(label)
        onSelect(route)
    }

    // MARK: rows

    private func resultRow(icon: WSGlyph, name: String, sub: String?,
                           codes: [String], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                iconWell(icon)
                VStack(alignment: .leading, spacing: 3) {
                    wsHighlight(name, query: trimmed, ws: ws)
                        .font(ws.sans(15, weight: .bold))
                    if let sub {
                        Text(sub).font(ws.mono(11)).tracking(0.2).foregroundStyle(ws.dim)
                    }
                    if !codes.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                        }.padding(.top, 1)
                    }
                }
                Spacer()
                WSIcon(glyph: .chevron, size: 18, color: ws.faint)
            }
            .padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) { WSRowDivider().padding(.horizontal, 22) }
    }

    private func serviceRow(_ svc: LTABusServiceDTO) -> some View {
        let dest = svc.DestinationCode.map { store.stopName($0) } ?? ""
        return Button {
            select(.serviceInfo(no: svc.ServiceNo, fromStop: nil), label: "Bus \(svc.ServiceNo)")
        } label: {
            HStack(spacing: 13) {
                Text(svc.ServiceNo).font(ws.mono(14, weight: .bold)).foregroundStyle(ws.text)
                    .frame(width: 38, height: 38)
                    .background(ws.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    (Text("Bus ") + wsHighlightRaw(svc.ServiceNo, query: trimmed))
                        .font(ws.sans(15, weight: .bold)).foregroundStyle(ws.text)
                    Text(dest.isEmpty ? "SERVICE" : "SERVICE · TO \(dest.uppercased())")
                        .font(ws.mono(11)).tracking(0.2).foregroundStyle(ws.dim)
                }
                Spacer()
                WSIcon(glyph: .chevron, size: 18, color: ws.faint)
            }
            .padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) { WSRowDivider().padding(.horizontal, 22) }
    }

    private func iconWell(_ glyph: WSGlyph) -> some View {
        WSIcon(glyph: glyph, size: 20, color: ws.dim)
            .frame(width: 38, height: 38)
            .background(ws.panel2)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

// MARK: - Query highlighting (bold the matched substring)

func wsHighlight(_ text: String, query: String, ws: WSTheme) -> Text {
    wsHighlightRaw(text, query: query)
        .foregroundStyle(ws.text)
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
