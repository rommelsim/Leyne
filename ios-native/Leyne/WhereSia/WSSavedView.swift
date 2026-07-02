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
                    Text(editMode == .active ? "DONE" : "EDIT")
                        .font(ws.mono(11, weight: .bold)).tracking(0.8)
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
            headerRow(WSSectionHeader(
                label: "Stops",
                meta: WSFmt.upd(store.newestRefresh(amongst: m.pins.map(\.code)), use24h: m.use24h)))
            ForEach(m.pins, id: \.code) { pin in
                row { savedStopRow(pin) }
            }
            .onDelete { m.pins.remove(atOffsets: $0) }
            .onMove { m.pins.move(fromOffsets: $0, toOffset: $1) }

            ForEach(m.savedMrtStations) { st in
                row { savedStationRow(st) }
            }
            .onDelete { m.savedMrtStations.remove(atOffsets: $0) }
            .onMove { m.savedMrtStations.move(fromOffsets: $0, toOffset: $1) }

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

    /// Shared row chrome: WhereSia insets, hairline separator, transparent bg.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(ws.rule)
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
    }

    // MARK: rows

    private func savedStopRow(_ pin: Pin) -> some View {
        let services = store.servicesFor(pin.code)
        let tiles = store.servicesAtStop(pin.code).isEmpty ? services.map(\.no) : store.servicesAtStop(pin.code)
        return Button { push(.busStop(code: pin.code)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if !pin.nickname.isEmpty {
                        Text(pin.nickname.uppercased()).font(ws.mono(10)).tracking(1.2).foregroundStyle(ws.dim)
                            .padding(.bottom, 3)
                    }
                    Text(store.stopName(pin.code)).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(stopSubline(pin.code))
                        .font(ws.mono(11)).tracking(0.2).foregroundStyle(ws.dim)
                    if !tiles.isEmpty { TileRow(services: tiles).padding(.top, 8) }
                }
                Spacer(minLength: 8)
                if let soonest = wsSoonest(services) {
                    let eta = fmtETA(wsLiveETASec(soonest))
                    VStack(alignment: .trailing, spacing: 5) {
                        (Text(eta.big).font(ws.mono(19, weight: .bold)).foregroundStyle(ws.text)
                         + Text(eta.big == "Arr" ? "" : " min").font(ws.mono(11, weight: .semibold)).foregroundStyle(ws.dim))
                        HStack(spacing: 6) {
                            Text("Bus \(soonest.no) ·").font(ws.mono(10)).foregroundStyle(ws.dim)
                            CrowdGauge(fraction: soonest.load.wsFraction, width: 24)
                            Text(soonest.load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stopSubline(_ code: String) -> String {
        let road = store.roadName(code)
        return road.isEmpty ? code : "\(code) · \(road.uppercased())"
    }

    private func savedStationRow(_ st: MrtGeoStation) -> some View {
        Button { push(.mrtStation(st)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    Text(wsLineNames(from: st.codes).uppercased())
                        .font(ws.mono(11)).tracking(0.2).foregroundStyle(ws.dim)
                    HStack(spacing: 5) { ForEach(st.codes.prefix(3), id: \.self) { LineBullet(code: $0) } }
                        .padding(.top, 6)
                }
                Spacer(minLength: 8)
                if let crowd = store.wsCrowd(for: st), crowd != .unknown {
                    WSChip(gauge: crowd.wsFraction, text: crowd.wsWord)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .font(ws.mono(11)).foregroundStyle(ws.dim)
                }
                Spacer()
                if let svc {
                    let eta = fmtETA(wsLiveETASec(svc))
                    VStack(alignment: .trailing, spacing: 5) {
                        (Text(eta.big).font(ws.mono(17, weight: .bold)).foregroundStyle(ws.text)
                         + Text(eta.big == "Arr" ? "" : "m").font(ws.mono(10)).foregroundStyle(ws.dim))
                        HStack(spacing: 5) {
                            CrowdGauge(fraction: svc.load.wsFraction, width: 24)
                            Text(svc.load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
