// WhereSia — Track bus (screen 7).
//
// A live card (route, destination, "reaching your stop in N min", crowd) over a
// vertical route timeline. Long routes collapse with "N earlier/more stops"
// chips. The moving bus is a pulsing node between stops; MRT-interchange stops
// are flagged; the user's stop is highlighted. CTA: "Alert me 1 stop before".
//
// Position is APPROXIMATE — LTA gives coords + ETAs for the next buses only, so
// per-stop minute times are not invented (only the your-stop ETA is real).

import SwiftUI

struct WSTrackBusView: View {
    let stopCode: String
    let serviceNo: String
    var onBack: () -> Void

    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var route: RouteInfo?
    @State private var busIndex: Int?

    private var service: Service? { store.servicesFor(stopCode).first { $0.no == serviceNo } }
    private var isAlerted: Bool {
        m.alert(kind: .arrival, busNo: serviceNo, stopCode: stopCode) != nil
    }

    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            WSHeaderBar(eyebrow: "Track bus", onBack: onBack) {
                Button {
                    push(.serviceInfo(no: serviceNo, fromStop: stopCode))
                } label: {
                    WSIcon(glyph: .info, size: 19)
                        .frame(width: 38, height: 38)
                        .background(ws.panel)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
            }

            liveCard

            ScrollView { timeline.padding(.top, 4) }

            cta
        }
        .background(ws.bg)
        .onAppear {
            store.ensureArrivals(stop: stopCode, force: true)
            Task { await loadRoute() }
        }
        .refreshable {
            await store.refreshArrivals(stop: stopCode)
            await loadRoute()
        }
    }

    // MARK: live card

    private var liveCard: some View {
        let eta = service.map { fmtETA(wsLiveETASec($0)) }
        return HStack(spacing: 0) {
            Rectangle().fill(ws.text).frame(width: 4)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    RouteTile(text: serviceNo, size: .large)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bus toward").font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim)
                        Text(service?.dest ?? destName).font(ws.sans(16, weight: .heavy)).foregroundStyle(ws.text)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    WSIcon(glyph: .live, size: 15, color: ws.dim, pulse: true)
                    if let eta {
                        (Text("Reaching your stop in ").font(ws.sans(13, weight: .semibold)).foregroundColor(ws.text)
                         + Text(eta.big == "Arr" ? "now" : "\(eta.big) min").font(ws.mono(13, weight: .bold)).foregroundColor(ws.text))
                    } else {
                        Text("Waiting for the next bus…").font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim)
                    }
                    Spacer()
                    if let load = service?.load {
                        HStack(spacing: 7) {
                            Text(load.wsWord).font(ws.sans(12, weight: .bold)).foregroundStyle(ws.text)
                            CrowdGauge(fraction: load.wsFraction, width: 34)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ws.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 22).padding(.top, 14)
    }

    private var destName: String {
        route?.stops.last?.name ?? "—"
    }

    // MARK: timeline

    @ViewBuilder private var timeline: some View {
        if let r = route, !r.stops.isEmpty {
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            let start = busIndex.map { min($0, you) } ?? max(0, you - 6)
            let end = min(r.stops.count - 1, you + 1)
            VStack(alignment: .leading, spacing: 0) {
                if start > 0 {
                    collapseChip("\(start) earlier stop\(start == 1 ? "" : "s") · from \(r.stops.first?.name ?? "")")
                }
                ForEach(start...end, id: \.self) { i in
                    stepRow(r, index: i, you: you)
                    if busIndex == i && i < end {
                        vehicleRow(r)
                    }
                }
                let more = (r.stops.count - 1) - end
                if more > 0 {
                    collapseChip("\(more) more stop\(more == 1 ? "" : "s") to \(r.stops.last?.name ?? "")")
                }
            }
            .padding(.horizontal, 22)
        } else {
            Text("Loading route…")
                .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                .padding(.horizontal, 22).padding(.top, 20)
        }
    }

    private func stepRow(_ r: RouteInfo, index i: Int, you: Int) -> some View {
        let stop = r.stops[i]
        let passed = busIndex.map { i < $0 } ?? false
        let isYou = i == you
        let ic = wsInterchange(forStopName: stop.name)
        return HStack(alignment: .top, spacing: 15) {
            // rail
            VStack(spacing: 0) {
                Circle()
                    .fill(isYou ? ws.text : (passed ? ws.faint : ws.bg))
                    .frame(width: isYou ? 15 : 13, height: isYou ? 15 : 13)
                    .overlay(Circle().stroke(isYou || passed ? ws.text : ws.faint, lineWidth: isYou ? 3 : 2.5))
                    .padding(.top, 4)
                Rectangle().fill(passed ? ws.text : ws.rule).frame(width: 3)
            }
            .frame(width: 24)

            if isYou {
                youBody(stop, ic: ic)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.name)
                        .font(ws.sans(14.5, weight: .bold))
                        .foregroundStyle(passed ? ws.faint : ws.text)
                    if let ic { interchangeFlag("MRT", ic.codes) }
                }
                .padding(.bottom, 18)
            }
        }
    }

    private func youBody(_ stop: RouteStopLive, ic: (name: String, codes: [String])?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ic != nil ? "YOUR STOP · MRT INTERCHANGE" : "YOUR STOP")
                .font(ws.sans(9.5, weight: .heavy)).tracking(1.2).foregroundStyle(ws.dim)
            Text(stop.name).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
            if let eta = service.map({ fmtETA(wsLiveETASec($0)) }) {
                Text(eta.big == "Arr" ? "Arriving now" : "~\(eta.big) min")
                    .font(ws.mono(11.5)).foregroundStyle(ws.dim)
            }
            if let ic { interchangeFlag("CHANGE FOR", ic.codes) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
        .overlay(alignment: .leading) { Rectangle().fill(ws.text).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.bottom, 18)
    }

    private func interchangeFlag(_ label: String, _ codes: [String]) -> some View {
        HStack(spacing: 7) {
            WSIcon(glyph: .train, size: 15, color: ws.dim)
            Text(label).font(ws.mono(9)).tracking(0.5).foregroundStyle(ws.dim)
            ForEach(codes.prefix(3), id: \.self) { LineBullet(code: $0) }
        }
        .padding(.top, 2)
    }

    private func vehicleRow(_ r: RouteInfo) -> some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(spacing: 0) {
                Text(serviceNo)
                    .font(ws.mono(12, weight: .bold)).foregroundStyle(ws.text)
                    .frame(width: 34, height: 30)
                    .background(ws.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ws.text, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Rectangle().fill(ws.rule).frame(width: 3)
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bus en route").font(ws.sans(12, weight: .bold)).foregroundStyle(ws.text)
                Text("between stops · \(service?.load.wsWord.lowercased() ?? "on the way")")
                    .font(ws.mono(11)).foregroundStyle(ws.dim)
            }
            .padding(.top, 5).padding(.bottom, 18)
        }
    }

    private func collapseChip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 2)
                    .overlay(
                        Rectangle().fill(ws.faint)
                            .frame(width: 2)
                            .mask(VStack(spacing: 6) { ForEach(0..<6, id: \.self) { _ in
                                Rectangle().frame(height: 3) } })
                    )
            }
            .frame(width: 24)
            HStack(spacing: 8) {
                WSIcon(glyph: .chevronDown, size: 14, color: ws.dim)
                Text(text).font(ws.mono(11)).foregroundStyle(ws.dim)
            }
            .padding(.vertical, 6)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    // MARK: CTA

    private var cta: some View {
        Button {
            let name = store.stopName(stopCode)
            m.toggleArrivalAlert(busNo: serviceNo, stopCode: stopCode,
                                 stopName: name, dest: service?.dest ?? "")
        } label: {
            HStack(spacing: 9) {
                WSIcon(glyph: isAlerted ? .bellRing : .alerts, size: 19, color: ws.bg)
                Text(isAlerted ? "Alert set · tap to cancel" : "Alert me 1 stop before")
                    .font(ws.sans(15, weight: .heavy)).foregroundStyle(ws.bg)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(ws.text)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.vertical, 12)
    }

    // MARK: data

    private func loadRoute() async {
        guard let r = await store.route(service: serviceNo, stopCode: stopCode) else { return }
        route = r
        // Approximate the bus's position from its live coord → nearest upstream stop.
        if let coord = await store.liveBus(service: serviceNo, stopCode: stopCode) {
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            var best: (idx: Int, d: Double)? = nil
            for i in 0...you {
                let s = r.stops[i]
                let d = haversine(coord.latitude, coord.longitude, s.lat, s.lon)
                if best == nil || d < best!.d { best = (i, d) }
            }
            busIndex = best?.idx
        } else {
            busIndex = nil
        }
    }
}
