// WhereSia — Search (screens 2 & 3).
//
// Presented modally over Home. Empty state: "Search near me" + a Recent list.
// Typing: results grouped by type (MRT stations / Bus stops / Bus services) with
// the query term bolded and type filter chips. Wired to DataStore.searchStops/
// searchServices + MrtGeo.stations(matching:).

import SwiftUI

struct WSSearchView: View {
    var onSelect: (WSRoute) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.ws) private var ws

    @State private var query = ""
    @State private var filter = 0     // 0 All · 1 Bus · 2 MRT · 3 Stops
    @State private var nearMe = false
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            field
            if trimmed.isEmpty && !nearMe {
                emptyState
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
                    Text("Search stop, bus or MRT").foregroundStyle(ws.dim))
                    .font(ws.sans(15, weight: .semibold))
                    .foregroundStyle(ws.text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = ""; nearMe = false } label: {
                        WSIcon(glyph: .close, size: 11, color: ws.dim)
                            .frame(width: 20, height: 20)
                            .background(ws.panel2)
                            .overlay(Circle().stroke(ws.rule, lineWidth: 1))
                            .clipShape(Circle())
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

    // MARK: empty state (near me + recent)

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {
                    location.requestPermission()
                    nearMe = true
                    store.prefetchNearbyArrivals()
                } label: {
                    HStack(spacing: 13) {
                        iconWell(.scope)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Search near me").font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                            Text("USE CURRENT LOCATION").font(ws.mono(10)).tracking(0.4).foregroundStyle(ws.dim)
                        }
                        Spacer()
                        WSIcon(glyph: .chevron, size: 18, color: ws.faint)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(ws.panel)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(ws.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
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
                        Button { query = r; nearMe = false } label: {
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

    // MARK: results

    private var stations: [MrtGeoStation] { nearMe ? [] : MrtGeo.stations(matching: trimmed) }
    private var stops: [LTABusStop] {
        if nearMe { return store.nearby.compactMap { store.stopByCode[$0.stopCode] } }
        return store.searchStops(trimmed)
    }
    private var services: [LTABusServiceDTO] { nearMe ? [] : store.searchServices(trimmed) }

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
                    Text("No matches for “\(trimmed)”.")
                        .font(ws.sans(14, weight: .medium)).foregroundStyle(ws.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 30)
                }
                Color.clear.frame(height: 24)
            }
        }
    }

    private var noResults: Bool {
        !nearMe && !trimmed.isEmpty
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
        .foregroundColor(ws.text)
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
