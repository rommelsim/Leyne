// WhereSia — Service info (screen 6).
//
// Route tile + destination + operator/category, a direction segmented control,
// then first/last bus (weekday/Sat/Sun-PH) and frequency bands (AM peak / midday
// / PM peak / evening). There is no fixed minute timetable — the copy says so.
// Wired to DataStore.serviceRoute (first/last) + WSServiceFreqStore (frequency).
//
// Soft Blue "4b" pass (docs/soft-blue-design.md): the nav-bar chrome
// (`wsHeaderBar` + `WSHairButton`) and `RouteTile` are shared system/line-
// identity components and stay exactly as-is — only the content below is
// ported. Sections become `SoftCard`, the direction toggle is restyled
// in-place as soft pills (white/ink-selected, matching WSHomeView's
// softChip pattern) without changing its behavior, and the background
// switches to `SoftBlue.bg`.

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
                    directionToggle
                        .padding(.horizontal, 22)
                }
                firstLastCard
                frequencyCard
                Text("Buses run at these intervals — there’s no fixed minute timetable. For exact times, check live arrivals.")
                    .font(ws.sans(11.5, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    .lineSpacing(3)
                    .padding(.horizontal, 24).padding(.top, 2)
                Color.clear.frame(height: 16)
            }
        }
        .wsEntrance(delay: 0.28)   // wait out the push slide, else the entrance plays unseen
        .background(SoftBlue.bg)
        .wsHeaderBar(eyebrow: "Service info", onBack: onBack) {
            WSHairButton(glyph: m.isFavService(no: serviceNo, stop: fromStop) ? .bookmarkFilled : .bookmark,
                         label: m.isFavService(no: serviceNo, stop: fromStop)
                            ? "Unfavourite bus \(serviceNo)" : "Favourite bus \(serviceNo)") {
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
                Text(destTitle).font(ws.sans(18, weight: .heavy)).foregroundStyle(SoftBlue.ink)
                Text(subtitle).font(ws.mono(11.5)).tracking(0.3).foregroundStyle(SoftBlue.sub)
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

    // MARK: direction toggle
    //
    // Same `dir` binding / behavior as the old `WSSegmented` — restyled
    // in-place as soft pills (per WSHomeView's softChip pattern): selected =
    // ink fill + white text, unselected = white fill + sub text, both with
    // the one shadow recipe (§4 of the soft-blue spec: an unselected chip
    // without the shadow reads as flat/disabled, which this isn't).
    private var directionToggle: some View {
        HStack(spacing: 8) {
            ForEach(directions.indices, id: \.self) { i in
                let on = i == dir
                Button { dir = i } label: {
                    Text("To \(shortName(directions[i].destinationName))")
                        .font(ws.sans(13, weight: .semibold))
                        .foregroundStyle(on ? .white : SoftBlue.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(on ? SoftBlue.ink : SoftBlue.card))
                        .shadow(color: SoftBlue.shadow, radius: 5, y: 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
            }
        }
    }

    // MARK: first & last

    private var firstLastCard: some View {
        let w = selected?.firstLast
        return SoftCard(title: fromStop != nil ? "First & last bus · this stop" : "First & last bus · from origin") {
            if let w {
                VStack(spacing: 0) {
                    firstLastRow("Weekdays", w.firstWD, w.lastWD)
                    firstLastRow("Saturday", w.firstSat, w.lastSat)
                    firstLastRow("Sun / P.H.", w.firstSun, w.lastSun, last: true)
                }
            } else {
                Text(loading ? "Loading…" : "First/last times weren’t published for this stop.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 22)
    }

    private func firstLastRow(_ key: String, _ first: String?, _ last: String?, last isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(ws.sans(13, weight: .semibold)).foregroundStyle(SoftBlue.sub)
                Spacer()
                (Text(WSFmt.firstLast(first, use24h: m.use24h)).foregroundStyle(SoftBlue.ink)
                 + Text(" – ").foregroundStyle(SoftBlue.sub)
                 + Text(WSFmt.firstLast(last, use24h: m.use24h)).foregroundStyle(SoftBlue.ink))
                    .font(ws.mono(14, weight: .bold))
            }
            .padding(.vertical, 11)
            if !isLast { SoftRowDivider(inset: 0) }
        }
    }

    // MARK: frequency

    private var frequencyCard: some View {
        SoftCard(title: "How often it runs") {
            if let f = freq {
                VStack(spacing: 0) {
                    softKV("AM peak · 0630–0830", WSServiceFreq.band(f.amPeak))
                    softKV("Midday · 0831–1659", WSServiceFreq.band(f.amOffpeak))
                    softKV("PM peak · 1700–1900", WSServiceFreq.band(f.pmPeak))
                    softKV("Evening · after 1900", WSServiceFreq.band(f.pmOffpeak), last: true)
                }
            } else {
                Text(loading ? "Loading frequency…" : "Frequency unavailable right now.")
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 22)
    }

    private func softKV(_ key: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(ws.sans(13, weight: .semibold)).foregroundStyle(SoftBlue.sub)
                Spacer()
                Text(value).font(ws.mono(14, weight: .bold)).foregroundStyle(SoftBlue.ink)
            }
            .padding(.vertical, 11)
            if !last { SoftRowDivider(inset: 0) }
        }
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
