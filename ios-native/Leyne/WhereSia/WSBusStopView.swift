// WhereSia — Bus stop (screen 4).
//
// Big stop name, code · road · updated. If the stop sits at an MRT station, an
// interchange card. Then one glanceable line per service (number-sorted so the
// board is scannable): route tile · destination · icons that stand on their
// own (double-decker only when it IS one; wheelchair when accessible) · the
// next bus big on the right. A bus that's pulling in gets the blue ARRIVING
// capsule + ping — unmissable from arm's length. Scheduled-only ETAs carry a
// whisper-quiet "~" (never a banner — feedback_timely_over_honest). No icon
// legend: if an icon needs a key, the icon is wrong.

import SwiftUI

struct WSBusStopView: View {
    let code: String
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.scenePhase) private var scenePhase

    @State private var refreshTick = false
    @State private var titleCollapsed = false

    private var isPinned: Bool { m.pins.contains { $0.code == code } }

    var body: some View {
        let _ = m.tick
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same card grammar as Home (owner spec 2026-07-08): name +
                // meta head, then the departure rows in one rounded panel.
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.stopName(code))
                        .font(ws.sans(25, weight: .heavy)).foregroundStyle(ws.text)
                    HStack(spacing: 9) {
                        if case .loaded = store.arrivals[code] { WSLiveBadge() }
                        Text(metaline)
                            .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    }
                    .padding(.top, 8)
                    WSRowDivider().padding(.top, 16)
                    servicesSection
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
                .background(ws.panel)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 22).padding(.top, 12)
                .wsEntrance(delay: 0)
                // No "MRT at this stop" card any more — it duplicated the
                // interchange the user can already see on Home / the map and
                // read as a stray row under the board (owner call 2026-07-09).
                Color.clear.frame(height: 20)
            }
        }
        .refreshable {
            await store.refreshArrivals(stop: code)
            refreshTick.toggle()
        }
        // Once the big in-content name scrolls under the bar, hand it to the
        // bar (eyebrow ⇄ title animation); scrolling back up restores "BUS STOP".
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 44
        } action: { _, isPast in
            titleCollapsed = isPast
        }
        .wsDetailAdBanner()
        .wsEntrance()
        .background(ws.bg)
        .wsHeaderBar(eyebrow: "Bus stop", title: store.stopName(code),
                     collapsed: titleCollapsed, onBack: onBack) {
            WSHairButton(glyph: isPinned ? .bookmarkFilled : .bookmark, action: togglePin)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPinned)
        .sensoryFeedback(.success, trigger: refreshTick)
        .onAppear {
            store.ensureArrivals(stop: code, force: true)
            store.ensureRoutes()
        }
        // AppModel's tick loop only keeps pinned/alerted stops fresh — an
        // open unpinned stop never re-fetched (owner: stale until
        // pull-to-refresh). The freshness window + inflight guard inside
        // ensureArrivals make this a no-op on most ticks (~every 25s it
        // actually fetches).
        .onChange(of: m.tick) { _, _ in store.ensureArrivals(stop: code) }
        // Returning from background: the tick loop was paused, so the data
        // can be minutes old — refetch immediately.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.ensureArrivals(stop: code, force: true) }
        }
    }

    private var metaline: String {
        let road = store.roadName(code)
        var parts = [code]
        if !road.isEmpty { parts.append(road) }
        parts.append(WSFmt.upd(store.lastRefresh(code), use24h: m.use24h))
        return parts.joined(separator: "  ·  ")
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }

    // MARK: services

    @ViewBuilder private var servicesSection: some View {
        switch store.arrivals[code] {
        case .loaded(let services):
            // Row reorder springs (anim spec) — keyed by service number so
            // a departed bus's removal moves the rest up naturally.
            VStack(spacing: 0) {
                ForEach(Array(services.enumerated()), id: \.element.no) { index, svc in
                    if index > 0 { WSRowDivider() }
                    WSDepartureRow(service: svc, stopCode: code, showsVehicleIcons: true)
                        // Long-press: set the arrival alert or favourite the
                        // service without drilling into Track Bus first.
                        .contextMenu {
                            let alerted = m.alert(kind: .arrival, busNo: svc.no, stopCode: code) != nil
                            Button {
                                _ = m.toggleArrivalAlert(busNo: svc.no, stopCode: code,
                                                         stopName: store.stopName(code), dest: svc.dest)
                            } label: {
                                Label(alerted ? "Cancel arrival alert" : "Alert me 1 stop before",
                                      systemImage: alerted ? "bell.slash" : "bell")
                            }
                            let fav = m.isFavService(no: svc.no, stop: code)
                            Button { m.toggleFavService(no: svc.no, stop: code) } label: {
                                Label(fav ? "Unfavourite bus \(svc.no)" : "Favourite bus \(svc.no)",
                                      systemImage: fav ? "star.slash" : "star")
                            }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: services.map(\.no))
        case .empty:
            stateText("No live arrivals right now. The last bus may have gone.")
        case .error(let msg):
            stateText(msg)
        default:
            VStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in WSSkeletonRow() }
            }
            .padding(.vertical, 14)
        }
    }

    private func stateText(_ s: String) -> some View {
        Text(s).font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
    }

    // No footer: the metaline under the stop name already carries LIVE +
    // "Updated h:mm", and users don't care where the data comes from
    // (owner, 2026-07-02) — the legend went earlier for the same reason.
}
