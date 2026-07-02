// WhereSia — Service info (screen 6, new).
//
// Route tile + destination + operator/category, a direction segmented control,
// then first/last bus (weekday/Sat/Sun-PH) and frequency bands (AM peak / midday
// / PM peak / evening). There is no fixed minute timetable — the copy says so.
// Wired to DataStore.serviceRoute (first/last) + WSServiceFreqStore (frequency).

import SwiftUI

struct WSServiceInfoView: View {
    let serviceNo: String
    let fromStop: String?
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws

    @State private var route: ServiceRoute?
    @State private var freq: WSServiceFreq?
    @State private var dir = 0
    @State private var loading = true

    private var directions: [RouteDirection] { route?.directions ?? [] }
    private var selected: RouteDirection? {
        guard dir < directions.count else { return directions.first }
        return directions[dir]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleRow.padding(.top, 12)
                if directions.count > 1 {
                    WSSegmented(options: directions.map { "To \(shortName($0.destinationName))" },
                                selection: $dir)
                        .padding(.horizontal, 22)
                }
                firstLastCard
                frequencyCard
                Text("Buses run at these intervals — there’s no fixed minute timetable. For exact times, check live arrivals.")
                    .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                    .lineSpacing(3)
                    .padding(.horizontal, 24).padding(.top, 2)
                Color.clear.frame(height: 16)
            }
        }
        .wsEntrance()
        .background(ws.bg)
        .wsHeaderBar(eyebrow: "Service info", onBack: onBack) {
            WSHairButton(glyph: m.isFavService(no: serviceNo, stop: fromStop) ? .bookmarkFilled : .bookmark) {
                m.toggleFavService(no: serviceNo, stop: fromStop)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: m.isFavService(no: serviceNo, stop: fromStop))
        .task { await load() }
    }

    // MARK: title

    private var titleRow: some View {
        HStack(spacing: 13) {
            RouteTile(text: serviceNo, size: .large)
            VStack(alignment: .leading, spacing: 3) {
                Text(destTitle).font(ws.sans(18, weight: .heavy)).foregroundStyle(ws.text)
                Text(subtitle).font(ws.mono(11.5)).tracking(0.3).foregroundStyle(ws.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var destTitle: String {
        if let d = selected?.destinationName, !d.isEmpty { return d }
        return "Bus \(serviceNo)"
    }
    private var subtitle: String {
        let cat = freq?.category?.uppercased() ?? categoryFallback
        return cat.isEmpty ? "BUS SERVICE" : cat
    }
    private var categoryFallback: String { "" }

    // MARK: first & last

    private var firstLastCard: some View {
        let w = selected?.firstLast
        return WSCard(title: fromStop != nil ? "First & last bus · this stop" : "First & last bus · from origin") {
            if let w {
                VStack(spacing: 0) {
                    firstLastRow("Weekdays", w.firstWD, w.lastWD)
                    firstLastRow("Saturday", w.firstSat, w.lastSat)
                    firstLastRow("Sun / P.H.", w.firstSun, w.lastSun, last: true)
                }
            } else {
                Text(loading ? "Loading…" : "First/last times weren’t published for this stop.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 22)
    }

    private func firstLastRow(_ key: String, _ first: String?, _ last: String?, last isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer()
                (Text(WSFmt.firstLast(first)).foregroundStyle(ws.text)
                 + Text(" – ").foregroundStyle(ws.dim)
                 + Text(WSFmt.firstLast(last)).foregroundStyle(ws.text))
                    .font(ws.mono(14, weight: .bold))
            }
            .padding(.vertical, 11)
            if !isLast { WSRowDivider() }
        }
    }

    // MARK: frequency

    private var frequencyCard: some View {
        WSCard(title: "How often it runs") {
            if let f = freq {
                VStack(spacing: 0) {
                    WSKV(key: "AM peak · 0630–0830", value: WSServiceFreq.band(f.amPeak))
                    WSKV(key: "Midday · 0831–1659", value: WSServiceFreq.band(f.amOffpeak))
                    WSKV(key: "PM peak · 1700–1900", value: WSServiceFreq.band(f.pmPeak))
                    WSKV(key: "Evening · after 1900", value: WSServiceFreq.band(f.pmOffpeak), last: true)
                }
            } else {
                Text(loading ? "Loading frequency…" : "Frequency unavailable right now.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: load

    private func load() async {
        store.ensureRoutes()
        // Resolve a reference stop so first/last populates: the opened-from stop,
        // else the origin of the initial direction.
        var ref = fromStop
        if ref == nil, let probe = await store.serviceRoute(service: serviceNo, stopCode: nil) {
            ref = probe.directions[safe: probe.initialIndex]?.stops.first?.code
        }
        if let r = await store.serviceRoute(service: serviceNo, stopCode: ref) {
            route = r
            dir = r.initialIndex
        }
        freq = await WSServiceFreqStore.shared.freq(for: serviceNo)
        loading = false
    }

    private func shortName(_ s: String) -> String {
        // Keep the segmented labels tight.
        let trimmed = s.replacingOccurrences(of: " Int", with: "")
                       .replacingOccurrences(of: " Stn", with: "")
        return trimmed.count > 12 ? String(trimmed.prefix(12)) + "…" : trimmed
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
