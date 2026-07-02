// WhereSia — MRT station (screen 5).
//
// Station name + line bullets + service state, then three dense cards:
// STATION CROWD (live gauge + word; per-line platform rows only when the
// station is an interchange — for single-line stations they'd duplicate the
// headline reading), BUS STOPS AT THIS STATION (nearest stops ≤ 400 m with
// their live soonest arrival — tap through), and CROWD FORECAST (LTA's real
// PCDForecast 30-min series — NOT mocked — with a "busiest around…" note).

import SwiftUI
import CoreLocation

struct WSMrtStationView: View {
    let station: MrtGeoStation
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var forecast: [ForecastPoint] = []
    @State private var titleCollapsed = false

    struct ForecastPoint: Identifiable {
        let id = UUID()
        let time: String
        let fraction: CGFloat
        let isNow: Bool
        let level: CrowdLevel
    }

    private var lines: [MRTLine] {
        var out: [MRTLine] = []
        for c in station.codes { if let l = wsLine(forStationCode: c), !out.contains(l) { out.append(l) } }
        return out
    }

    private var status: String {
        let disrupted = station.codes.contains { code in
            store.trainAlerts.contains { $0.line == wsLine(forStationCode: code) }
        }
        return disrupted ? "SERVICE DISRUPTED" : "NORMAL SERVICE"
    }

    private var crowdNow: CrowdLevel { store.wsCrowd(for: station) ?? .unknown }

    var body: some View {
        // titleRow's "UPD h:mm" stamp is `WSFmt.upd(Date(), ...)` — a live
        // wall-clock read, not a stored fetch timestamp — so this view needs
        // a tick dependency to keep advancing under @Observable's
        // per-property tracking (ObservableObject used to refresh it for
        // free via the blanket per-second objectWillChange).
        let _ = m.tick
        ScrollView {
            VStack(spacing: 12) {
                titleRow.padding(.top, 12)
                crowdCard
                busCard
                forecastCard
                Color.clear.frame(height: 12)
            }
            .padding(.bottom, 8)
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 44
        } action: { _, isPast in
            titleCollapsed = isPast
        }
        .wsEntrance()
        .background(ws.bg)
        .wsHeaderBar(eyebrow: "MRT station", title: station.name,
                     collapsed: titleCollapsed, onBack: onBack) {
            WSHairButton(glyph: m.isMrtSaved(station) ? .bookmarkFilled : .bookmark) {
                m.toggleMrtSaved(station)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: m.isMrtSaved(station))
        .onAppear {
            store.wsWarmCrowd(for: [station])
            for l in lines { store.refreshForecast(line: l) }
            for item in nearbyStops { store.ensureArrivals(stop: item.stop.BusStopCode, silent: true) }
            loadForecast()
        }
    }

    /// Bus stops physically at/around the station (≤ 400 m walk).
    private var nearbyStops: [(stop: LTABusStop, distanceM: Int)] {
        store.wsStopsNear(CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), limit: 3)
            .filter { $0.distanceM <= 400 }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name).font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                Text("\(status) · \(WSFmt.upd(Date(), use24h: m.use24h))")
                    .font(ws.mono(11)).tracking(0.3).foregroundStyle(ws.dim)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(station.codes.prefix(3), id: \.self) { LineBullet(code: $0) }
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: station crowd (headline + per-platform rows for interchanges)

    private var crowdCard: some View {
        WSCard(title: "Station crowd · now") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crowdNow.wsWord).font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
                        Text(crowdNow.wsHint).font(ws.mono(10.5)).tracking(0.3).foregroundStyle(ws.dim)
                    }
                    Spacer()
                    if crowdNow != .unknown { WSLiveBadge() }
                }
                .padding(.top, 8)
                // CrowdGauge needs a concrete width up front; a GeometryReader
                // reads the real local container width (respects the card's
                // own padding, rotation, and multitasking/split-view) instead
                // of a hardcoded UIScreen.main.bounds calculation.
                GeometryReader { geo in
                    CrowdGauge(fraction: crowdNow.wsFraction, width: geo.size.width, height: 9)
                }
                .frame(height: 9)

                // Per-line platform readings only where they can differ from
                // the headline — i.e. interchanges. On a single-line station
                // this would repeat the number above (the old "By line" card).
                if lines.count > 1 {
                    WSRowDivider().padding(.top, 6)
                    ForEach(lines.indices, id: \.self) { i in
                        let line = lines[i]
                        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
                        let level = store.crowdByLine[line]?.first { $0.code == code }?.level ?? .unknown
                        HStack(spacing: 10) {
                            LineBullet(code: line.pcdLineCode, isLineCode: true)
                            Text("\(line.displayName) platform")
                                .font(ws.sans(13, weight: .bold)).foregroundStyle(ws.text)
                            Spacer()
                            CrowdGauge(fraction: level.wsFraction, width: 44)
                            Text(level.wsWord).font(ws.mono(10.5)).foregroundStyle(ws.dim)
                        }
                        .padding(.top, 7)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: bus connections

    @ViewBuilder private var busCard: some View {
        let near = nearbyStops
        if !near.isEmpty {
            WSCard(title: "Bus stops at this station") {
                VStack(spacing: 0) {
                    ForEach(near.indices, id: \.self) { i in
                        let item = near[i]
                        Button { push(.busStop(code: item.stop.BusStopCode)) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.stop.Description)
                                        .font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
                                        .lineLimit(1)
                                    Text("\(item.stop.BusStopCode) · \(fmtDistance(item.distanceM).uppercased())")
                                        .font(ws.mono(10.5)).tracking(0.3).foregroundStyle(ws.dim)
                                }
                                Spacer(minLength: 8)
                                if let s = wsSoonest(store.servicesFor(item.stop.BusStopCode)) {
                                    let eta = fmtETA(wsLiveETASec(s))
                                    (Text(eta.big).font(ws.mono(15, weight: .bold)).foregroundStyle(ws.text)
                                     + Text(eta.big == "Arr" ? "" : " min")
                                        .font(ws.mono(10)).foregroundStyle(ws.dim))
                                }
                                WSIcon(glyph: .chevron, size: 15, color: ws.faint)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < near.count - 1 { WSRowDivider() }
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: forecast

    private var forecastCard: some View {
        WSCard(title: "Crowd forecast · today") {
            VStack(alignment: .leading, spacing: 6) {
                if forecast.isEmpty {
                    Text("Forecast unavailable right now.")
                        .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                        .padding(.vertical, 12)
                } else {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(forecast) { p in
                            ForecastBar(fraction: p.fraction, time: p.time, isNow: p.isNow)
                        }
                    }
                    .padding(.top, 6)
                    if let busiest = busiestNote {
                        (Text("Busiest around ").foregroundStyle(ws.dim)
                         + Text(busiest).fontWeight(.bold).foregroundStyle(ws.text)
                         + Text(". Leave a little earlier to beat the crowd.").foregroundStyle(ws.dim))
                            .font(ws.sans(11.5, weight: .medium))
                            .padding(.top, 12)
                    }
                    // No provenance footnote — users don't care where the
                    // data comes from (owner, 2026-07-02); the card title +
                    // time labels say everything.
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private var busiestNote: String? {
        guard let peak = forecast.max(by: { $0.fraction < $1.fraction }), peak.fraction > 0 else { return nil }
        return peak.isNow ? "now" : peak.time
    }

    private func loadForecast() {
        guard let line = lines.first else { return }
        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
        Task {
            guard let intervals = try? await LTAService.shared.stationForecast(trainLine: line.pcdLineCode)
            else { return }
            let now = Date()
            let mine = intervals
                .filter { $0.station == code }
                .sorted { $0.start < $1.start }
            // Take the upcoming window (from the last past interval through the
            // next five), so "now" anchors the chart.
            let upcomingIdx = mine.firstIndex { $0.start >= now } ?? max(0, mine.count - 1)
            let start = max(0, upcomingIdx - 1)
            let window = Array(mine[start..<min(mine.count, start + 6)])
            let pts = window.map { iv -> ForecastPoint in
                let level = CrowdLevel.from(iv.crowdLevel)
                let isNow = iv.start <= now && (mine.first { $0.start > iv.start }?.start ?? .distantFuture) > now
                return ForecastPoint(
                    time: isNow ? "now" : WSFmt.clock(iv.start, use24h: m.use24h),
                    fraction: level.wsFraction, isNow: isNow, level: level)
            }
            await MainActor.run { forecast = pts }
        }
    }
}
