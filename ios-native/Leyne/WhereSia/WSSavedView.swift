// WhereSia — Saved (screen 9).
//
// Saved Stops (each with an optional HOME/WORK/GYM tag) + saved MRT stations,
// and saved Lines, showing live next-arrival + crowd inline. Wired to
// AppModel.pins / savedMrtStations / favServices.

import SwiftUI

struct WSSavedView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    stopsSection
                    linesSection
                    Color.clear.frame(height: 24)
                }
            }
        }
        .background(ws.bg)
        .onAppear {
            for p in m.pins { store.ensureArrivals(stop: p.code) }
            for f in m.favServices { if let s = f.stop { store.ensureArrivals(stop: s) } }
            store.ensureRoutes()
            store.wsWarmCrowd(for: m.savedMrtStations)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 11).fill(ws.panel)
                    .frame(width: 38, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
                    .overlay(WSIcon(glyph: .bookmarkFilled, size: 18, color: ws.text))
                VStack(alignment: .leading, spacing: 1) {
                    Text("YOUR PLACES").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                    Text("Saved").font(ws.sans(20, weight: .heavy)).foregroundStyle(ws.text)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    // MARK: stops

    private var stopsSection: some View {
        Group {
            WSSectionHeader(label: "Stops",
                            meta: WSFmt.upd(store.newestRefresh(amongst: m.pins.map(\.code)), use24h: m.use24h))
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
            if m.pins.isEmpty && m.savedMrtStations.isEmpty {
                empty("Bookmark a stop or MRT station to see it here.")
            } else {
                ForEach(m.pins, id: \.code) { pin in
                    savedStopRow(pin)
                    WSRowDivider().padding(.horizontal, 22)
                }
                ForEach(m.savedMrtStations) { st in
                    savedStationRow(st)
                    WSRowDivider().padding(.horizontal, 22)
                }
            }
        }
    }

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
                    if !tiles.isEmpty { TileRow(services: tiles).padding(.top, 8) }
                }
                Spacer(minLength: 8)
                if let soonest = wsSoonest(services) {
                    let eta = fmtETA(wsLiveETASec(soonest))
                    VStack(alignment: .trailing, spacing: 5) {
                        (Text(eta.big).font(ws.mono(19, weight: .bold)).foregroundColor(ws.text)
                         + Text(eta.big == "Arr" ? "" : " min").font(ws.mono(11, weight: .semibold)).foregroundColor(ws.dim))
                        HStack(spacing: 6) {
                            Text("Bus \(soonest.no) ·").font(ws.mono(10)).foregroundStyle(ws.dim)
                            CrowdGauge(fraction: soonest.load.wsFraction, width: 24)
                            Text(soonest.load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func savedStationRow(_ st: MrtGeoStation) -> some View {
        Button { push(.mrtStation(st)) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(st.name).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                    HStack(spacing: 5) { ForEach(st.codes.prefix(3), id: \.self) { LineBullet(code: $0) } }
                }
                Spacer(minLength: 8)
                if let crowd = store.wsCrowd(for: st), crowd != .unknown {
                    WSChip(gauge: crowd.wsFraction, text: crowd.wsWord)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: lines

    private var linesSection: some View {
        Group {
            if !m.favServices.isEmpty {
                WSSectionHeader(label: "Lines")
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                ForEach(m.favServices) { fav in
                    lineRow(fav)
                    WSRowDivider().padding(.horizontal, 22)
                }
            }
        }
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
                        (Text(eta.big).font(ws.mono(17, weight: .bold)).foregroundColor(ws.text)
                         + Text(eta.big == "Arr" ? "" : "m").font(ws.mono(10)).foregroundColor(ws.dim))
                        HStack(spacing: 5) {
                            CrowdGauge(fraction: svc.load.wsFraction, width: 24)
                            Text(svc.load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 14)
    }
}
