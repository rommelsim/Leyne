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
    @Environment(\.wsPush) private var push
    @Environment(\.scenePhase) private var scenePhase

    @State private var refreshTick = false
    @State private var titleCollapsed = false

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
                HStack(spacing: 9) {
                    if case .loaded = store.arrivals[code] { WSLiveBadge() }
                    Text(metaline)
                        .font(ws.mono(12)).tracking(0.3).foregroundStyle(ws.dim)
                }
                .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)

                if let ic = interchange { interchangeCard(ic).padding(.bottom, 8) }

                servicesSection
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
            if let ic = interchange, let st = MrtGeo.station(forCode: ic.codes.first ?? "") {
                store.wsWarmCrowd(for: [st])
            }
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
        if !road.isEmpty { parts.append(road.uppercased()) }
        parts.append(WSFmt.upd(store.lastRefresh(code), use24h: m.use24h))
        return parts.joined(separator: " · ")
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }

    // MARK: interchange card

    /// One dense row — bullets · name/eyebrow · crowd · chevron. The old
    /// two-row layout left the middle of the card mostly empty.
    private func interchangeCard(_ ic: (name: String, codes: [String])) -> some View {
        let station = MrtGeo.station(forCode: ic.codes.first ?? "")
        return Button {
            if let station { push(.mrtStation(station)) }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(ic.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ic.name).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    Text("MRT AT THIS STOP").font(ws.mono(9)).tracking(0.6).foregroundStyle(ws.dim)
                }
                Spacer(minLength: 8)
                if let station, let crowd = store.wsCrowd(for: station), crowd != .unknown {
                    WSChip(gauge: crowd.wsFraction, text: crowd.wsWord)
                }
                WSIcon(glyph: .chevron, size: 17, color: ws.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(ws.panel)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
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

    /// One glanceable line per service: number · destination on the left,
    /// the NEXT bus big on the right with its crowd, and later buses as a
    /// quiet "then 12 · 24 min" — replacing the wall of three boxed pills
    /// (each with its own gauge + word) the owner flagged as messy. Track
    /// Bus keeps the full per-bus detail.
    ///
    /// Icons carry information only when they say something: the double-decker
    /// glyph appears only on double-deckers (the default single deck shows
    /// nothing), wheelchair only when accessible — so no legend is needed.
    private func serviceBlock(_ svc: Service) -> some View {
        let sched = !svc.monitored
        let entries = pillEntries(svc)
        let later = entries.dropFirst().map(\.eta.big)
        let arrivingNow = !sched && (entries.first?.eta.big == "Arr")
        return Button { push(.trackBus(stopCode: code, no: svc.no)) } label: {
            HStack(alignment: .center, spacing: 13) {
                RouteTile(text: svc.no, size: .large)
                // Two shared rows so left and right columns actually line up:
                // destination ⟷ ETA on one text baseline, icons/"then" ⟷ crowd
                // on the second. (Two independent VStacks centred against each
                // other put "1 min" visibly above the stop name — owner-flagged.)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(svc.dest).font(ws.sans(15.5, weight: .bold)).foregroundStyle(ws.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if arrivingNow {
                            // The "this bus is pulling in" mark: a solid blue
                            // capsule (the sanctioned live-accent exception).
                            // Static — the pulsing ping read as distracting
                            // (owner feedback); the row tint + capsule carry it.
                            Text("ARRIVING")
                                .font(ws.mono(11, weight: .bold)).tracking(0.8)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(ws.accent)
                                .clipShape(Capsule())
                        } else if let next = entries.first {
                            // Scheduled-only ETA: whisper-quiet "~", full-strength
                            // numeral (timeliness is the promise — never dim a row).
                            (Text(sched ? "~" : "")
                                .font(ws.mono(15, weight: .semibold)).foregroundStyle(ws.dim)
                             + Text(next.eta.big).font(ws.mono(19, weight: .bold)).foregroundStyle(ws.text)
                             + Text(next.eta.big == "Arr" ? "" : " min")
                                .font(ws.mono(11, weight: .semibold)).foregroundStyle(ws.dim))
                        } else {
                            Text("—").font(ws.mono(19, weight: .bold)).foregroundStyle(ws.dim)
                        }
                    }
                    HStack(spacing: 7) {
                        if svc.deck == .DD { WSIcon(glyph: .busDouble, size: 15, color: ws.dim) }
                        else if svc.deck == .BD { WSIcon(glyph: .busBendy, size: 15, color: ws.dim) }
                        if svc.wab { WSIcon(glyph: .wheelchair, size: 15, color: ws.dim) }
                        if !later.isEmpty {
                            Text("then \(later.joined(separator: " · ")) min")
                                .font(ws.mono(11)).foregroundStyle(ws.dim)
                        }
                        Spacer(minLength: 8)
                        if let load = entries.first?.load, !sched {
                            CrowdGauge(fraction: load.wsFraction, width: 24)
                            Text(load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
                        }
                    }
                }
                WSIcon(glyph: .chevron, size: 16, color: ws.faint)
            }
            .padding(.horizontal, 22).padding(.vertical, 13)
            // Contained highlight card, inset from the screen edges — a
            // full-bleed fill read as the colour "bleeding out" past the row.
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(arrivingNow ? ws.accentSoft.opacity(0.08) : Color.clear)
                    .padding(.horizontal, 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Long-press: set the arrival alert or favourite the service without
        // drilling into Track Bus first.
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
        .accessibilityHint(arrivingNow ? "Bus \(svc.no) is arriving now" : "")
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

    // No footer: the metaline under the stop name already carries LIVE +
    // "Updated h:mm", and users don't care where the data comes from
    // (owner, 2026-07-02) — the legend went earlier for the same reason.
}
