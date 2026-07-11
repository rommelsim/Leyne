// WhereSia — Saved (screen 9).
//
// A native List in WhereSia clothes: saved stops (optional HOME/WORK tag),
// saved MRT stations and saved lines, each with live next-arrival + crowd
// inline and a code · road / line subline. Swipe left to remove; EDIT (or a
// long drag) reorders — mutations persist via AppModel's didSet observers.
// Wired to AppModel.pins / savedMrtStations / favServices.

import SwiftUI

struct WSSavedView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var editMode: EditMode = .inactive

    private var isEmpty: Bool {
        m.pins.isEmpty && m.savedMrtStations.isEmpty && m.favServices.isEmpty
    }

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            header
            if isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(ws.bg)
        .sensoryFeedback(.impact(weight: .light),
                         trigger: m.pins.count + m.savedMrtStations.count + m.favServices.count)
        .onAppear {
            for p in m.pins { store.ensureArrivals(stop: p.code) }
            for f in m.favServices { if let s = f.stop { store.ensureArrivals(stop: s) } }
            store.ensureRoutes()
            store.wsWarmCrowd(for: m.savedMrtStations)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR PLACES").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                Text("Saved").font(ws.sans(26, weight: .heavy)).foregroundStyle(ws.text)
            }
            Spacer()
            if !isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {
                    Text(editMode == .active ? "Done" : "Edit")
                        .font(ws.sans(13, weight: .bold))
                        .foregroundStyle(ws.text)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: editMode)
            }
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    // MARK: list

    private var list: some View {
        List {
            // Stops — only when there are saved stops (was showing over saved
            // stations, mislabelling them).
            if !m.pins.isEmpty {
                headerRow(WSSectionHeader(
                    label: "Stops",
                    meta: WSFmt.upd(store.newestRefresh(amongst: m.pins.map(\.code)), use24h: m.use24h)))
                ForEach(m.pins, id: \.code) { pin in
                    row { savedStopRow(pin) }
                }
                .onDelete { m.pins.remove(atOffsets: $0) }
                .onMove { m.pins.move(fromOffsets: $0, toOffset: $1) }
            }

            // Stations — its own header now, not folded under Stops.
            if !m.savedMrtStations.isEmpty {
                headerRow(WSSectionHeader(label: "Stations"))
                ForEach(m.savedMrtStations) { st in
                    row { savedStationRow(st) }
                }
                .onDelete { m.savedMrtStations.remove(atOffsets: $0) }
                .onMove { m.savedMrtStations.move(fromOffsets: $0, toOffset: $1) }
            }

            // One native ad per screen, between the places and Lines sections.
            // Renders nothing until a creative loads; pinned out of edit mode.
            NativeAdCard()
                .listRowSeparator(.hidden)
                .deleteDisabled(true).moveDisabled(true)

            if !m.favServices.isEmpty {
                headerRow(WSSectionHeader(label: "Lines"))
                ForEach(m.favServices) { fav in
                    row { lineRow(fav) }
                }
                .onDelete { m.favServices.remove(atOffsets: $0) }
                .onMove { m.favServices.move(fromOffsets: $0, toOffset: $1) }
            }

            Color.clear.frame(height: 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .deleteDisabled(true).moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .wsEntrance()
    }

    /// Non-editable header line rendered as a list row (keeps pixel-exact
    /// WhereSia styling instead of the plain-list sticky header's).
    private func headerRow(_ header: WSSectionHeader) -> some View {
        header
            .padding(.top, 18).padding(.bottom, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .deleteDisabled(true)
            .moveDisabled(true)
    }

    /// Shared row chrome: each saved item is an inset rounded card on the panel
    /// surface (replacing the old edge-to-edge hairline rows) so the sections
    /// read as grouped cards in the app's card grammar. Swipe-to-delete and
    /// EDIT reorder still work — listRowBackground preserves both.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ws.panel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: rows

    private func savedStopRow(_ pin: Pin) -> some View {
        let services = store.servicesFor(pin.code)
        let tiles = store.servicesAtStop(pin.code).isEmpty ? services.map(\.no) : store.servicesAtStop(pin.code)
        return Button { push(.busStop(code: pin.code)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if !pin.nickname.isEmpty {
                        Text(pin.nickname.uppercased())
                            .font(ws.sans(10.5, weight: .heavy)).tracking(1.2).foregroundStyle(ws.dim)
                            .padding(.bottom, 3)
                    }
                    Text(store.stopName(pin.code)).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(stopSubline(pin.code))
                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    if !tiles.isEmpty { TileRow(services: tiles).padding(.top, 8) }
                }
                Spacer(minLength: 8)
                if let soonest = wsSoonest(services) {
                    let sec = wsLiveETASec(soonest)
                    VStack(alignment: .trailing, spacing: 4) {
                        etaText(sec)
                        HStack(spacing: 6) {
                            Text("Bus \(soonest.no)")
                                .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                            Circle()
                                .fill(soonest.load.wsDotColor)
                                .frame(width: 6, height: 6)
                            Text(soonest.load.wsWord)
                                .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wsZoomSource(id: wsStopZoomID(pin.code))
    }

    /// The right-hand ETA in the departure-row grammar: "Now" or "N min".
    private func etaText(_ sec: Int) -> some View {
        Group {
            if sec < 60 {
                Text("Now").font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
            } else {
                (Text("\(max(1, sec / 60))")
                    .font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
                 + Text(" min")
                    .font(ws.sans(11, weight: .semibold)).foregroundStyle(ws.dim))
            }
        }
        .contentTransition(.numericText(countsDown: true))
    }

    private func stopSubline(_ code: String) -> String {
        let road = store.roadName(code)
        return road.isEmpty ? code : "\(code)  ·  \(road)"
    }

    private func savedStationRow(_ st: MrtGeoStation) -> some View {
        Button { push(.mrtStation(st)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(wsLineNames(from: st.codes))
                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                    HStack(spacing: 5) { ForEach(st.codes.prefix(3), id: \.self) { LineBullet(code: $0) } }
                        .padding(.top, 6)
                }
                Spacer(minLength: 8)
                if let crowd = store.wsCrowd(for: st), crowd != .unknown {
                    HStack(spacing: 6) {
                        CrowdGauge(fraction: crowd.wsFraction, width: 22)
                        Text(crowd.wsWord)
                            .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Zoom source for the station screen (anim spec: matched geometry).
        .wsZoomSource(id: wsMrtZoomID(st))
    }

    private func lineRow(_ fav: FavService) -> some View {
        let svc = fav.stop.flatMap { code in store.servicesFor(code).first { $0.no == fav.no } }
        return Button {
            if let stop = fav.stop { push(.trackBus(stopCode: stop, no: fav.no)) }
            else { push(.serviceInfo(no: fav.no, fromStop: nil)) }
        } label: {
            HStack(spacing: 13) {
                RouteTile(text: fav.no, size: .large)
                VStack(alignment: .leading, spacing: 3) {
                    Text(svc?.dest ?? "Bus \(fav.no)").font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(fav.stop.map { "at \(store.stopName($0))" } ?? "Anywhere near you")
                        .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                }
                Spacer()
                if let svc {
                    let sec = wsLiveETASec(svc)
                    VStack(alignment: .trailing, spacing: 4) {
                        etaText(sec)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(svc.load.wsDotColor)
                                .frame(width: 6, height: 6)
                            Text(svc.load.wsWord)
                                .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wsZoomSource(id: fav.stop.map { wsBusZoomID(stopCode: $0, no: fav.no) } ?? "line-\(fav.no)")
    }

    // MARK: empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            WSIcon(glyph: .bookmark, size: 30, color: ws.faint)
            Text("Nothing saved yet")
                .font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
            Text("Tap the bookmark on a stop, station or bus\nto keep it one tap away.")
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.bottom, 60)
    }
}
