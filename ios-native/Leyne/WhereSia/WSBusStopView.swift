// WhereSia — Bus stop (screen 4).
//
// Big stop name, code · road · updated. If the stop sits at an MRT station, an
// interchange card. Then one block per service: route tile, destination,
// operator, bus-type icon, wheelchair icon, live icon; and up to 3 arrival pills
// (minutes + gauge + word; first highlighted; scheduled dimmed). Footer key
// legend + a "Live from LTA DataMall · refreshes every 20s" status line.

import SwiftUI

struct WSBusStopView: View {
    let code: String
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var refreshTick = false

    private var isPinned: Bool { m.pins.contains { $0.code == code } }
    private var interchange: (name: String, codes: [String])? {
        wsInterchange(forStopName: store.stopName(code))
    }

    var body: some View {
        let _ = m.tick
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.stopName(code))
                    .font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                    .padding(.horizontal, 22).padding(.top, 12)
                Text(metaline)
                    .font(ws.mono(12)).tracking(0.3).foregroundStyle(ws.dim)
                    .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)

                if let ic = interchange { interchangeCard(ic).padding(.bottom, 8) }

                servicesSection
                footer
                Color.clear.frame(height: 20)
            }
        }
        .refreshable {
            await store.refreshArrivals(stop: code)
            refreshTick.toggle()
        }
        .wsEntrance()
        .background(ws.bg)
        .wsHeaderBar(eyebrow: "Bus stop", onBack: onBack) {
            WSHairButton(glyph: isPinned ? .bookmarkFilled : .bookmark, action: togglePin)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPinned)
        .sensoryFeedback(.success, trigger: refreshTick)
        .onAppear {
            store.ensureArrivals(stop: code, force: true)
            store.ensureRoutes()
            if let ic = interchange, let st = MrtGeo.station(forCode: ic.codes.first ?? "") {
                store.wsWarmCrowd(for: [st])
            }
        }
    }

    private var metaline: String {
        let road = store.roadName(code)
        var parts = [code]
        if !road.isEmpty { parts.append(road.uppercased()) }
        parts.append(WSFmt.upd(store.lastRefresh(code), use24h: m.use24h))
        return parts.joined(separator: " · ")
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }

    // MARK: interchange card

    private func interchangeCard(_ ic: (name: String, codes: [String])) -> some View {
        let station = MrtGeo.station(forCode: ic.codes.first ?? "")
        return Button {
            if let station { push(.mrtStation(station)) }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    WSIcon(glyph: .train, size: 17, color: ws.dim)
                    Text(ic.name).font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
                    Text("AT THIS STOP").font(ws.mono(9)).tracking(0.6).foregroundStyle(ws.dim)
                    Spacer()
                    WSIcon(glyph: .chevron, size: 17, color: ws.faint)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        ForEach(ic.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                    }
                    Spacer()
                    if let station, let crowd = store.wsCrowd(for: station), crowd != .unknown {
                        WSChip(gauge: crowd.wsFraction, text: crowd.wsWord)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(ws.panel)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
    }

    // MARK: services

    @ViewBuilder private var servicesSection: some View {
        switch store.arrivals[code] {
        case .loaded(let services):
            ForEach(services) { svc in
                serviceBlock(svc)
                WSRowDivider().padding(.horizontal, 22)
            }
        case .empty:
            stateText("No live arrivals right now. The last bus may have gone.")
        case .error(let msg):
            stateText(msg)
        default:
            stateText("Loading live arrivals…")
        }
    }

    private func stateText(_ s: String) -> some View {
        Text(s).font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 20)
    }

    private func serviceBlock(_ svc: Service) -> some View {
        Button { push(.trackBus(stopCode: code, no: svc.no)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 13) {
                    RouteTile(text: svc.no, size: .large)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(svc.dest).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                        HStack(spacing: 8) {
                            Text(svc.op.wsName).font(ws.mono(11)).foregroundStyle(ws.dim)
                            WSIcon(glyph: svc.deck.wsGlyph, size: 16, color: ws.dim)
                            if svc.wab { WSIcon(glyph: .wheelchair, size: 16, color: ws.dim) }
                            if svc.monitored {
                                WSIcon(glyph: .live, size: 16, color: ws.accentSoft, pulse: true)
                            } else {
                                Text("· scheduled").font(ws.mono(11)).foregroundStyle(ws.dim)
                            }
                        }
                    }
                    Spacer()
                    WSIcon(glyph: .chevron, size: 17, color: ws.faint)
                }
                HStack(spacing: 8) { pills(for: svc) }
            }
            .padding(.horizontal, 22).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func pills(for svc: Service) -> some View {
        let sched = !svc.monitored
        let entries = pillEntries(svc)
        ForEach(entries.indices, id: \.self) { i in
            let e = entries[i]
            ArrivalPill(eta: e.eta, load: e.load,
                        highlighted: i == 0 && !sched, scheduled: sched)
        }
    }

    private func pillEntries(_ svc: Service) -> [(eta: ETA, load: Load?)] {
        var out: [(ETA, Load?)] = []
        let now = Date()
        if let d = svc.arrivalDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.load))
        } else {
            out.append((fmtETA(wsLiveETASec(svc, now: now)), svc.load))
        }
        if let d = svc.followingDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.followingLoad))
        }
        if let d = svc.thirdDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.thirdLoad))
        }
        return out
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            WSRowDivider()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 15) {
                    legend(.busSingle, "Single deck")
                    legend(.busDouble, "Double deck")
                    legend(.wheelchair, "Wheelchair")
                }
                HStack(spacing: 15) {
                    HStack(spacing: 6) { CrowdGauge(fraction: 0.67, width: 16); label("How full") }
                    legend(.live, "Live · else timetable")
                }
            }
            HStack(spacing: 7) {
                WSIcon(glyph: .live, size: 13, color: ws.accentSoft, pulse: true)
                Text("Live from LTA DataMall · \(WSFmt.upd(store.lastRefresh(code), use24h: m.use24h)) · refreshes every 20s")
                    .font(ws.mono(10.5)).tracking(0.3).foregroundStyle(ws.dim)
            }
        }
        .padding(.horizontal, 22).padding(.top, 14)
    }

    private func legend(_ glyph: WSGlyph, _ text: String) -> some View {
        HStack(spacing: 6) { WSIcon(glyph: glyph, size: 13, color: ws.dim); label(text) }
    }
    private func label(_ s: String) -> some View {
        Text(s).font(ws.mono(10)).tracking(0.2).foregroundStyle(ws.dim)
    }
}
