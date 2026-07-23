// WhereSia — Home, MRT mode.
//
// The MRT face of the Home screen (owner mockup, image #1). Selected by the
// Bus/MRT segmented toggle under the living-sky hero, it swaps the nearby-bus
// content for a rail-first stack: the nearest station, its live platform crowd
// + forecast, the two platform directions, station facilities, a short line
// map of neighbouring stations, and service status. All from data already in
// the app — crowd/forecast/alerts via DataStore, the line sequence DERIVED
// from station codes (EW21→EW22→EW23…), so no new endpoint is needed (the LTA
// DataMall guide confirms sequence only exists as a static code list).

import SwiftUI
import CoreLocation

// MARK: - Line-sequence helpers (derived from station codes)

/// Split a station code like "EW23" into its line prefix ("EW") and index (23).
func wsCodeParts(_ code: String) -> (prefix: String, num: Int)? {
    let letters = code.prefix { $0.isLetter }
    let digits = code.drop { $0.isLetter }
    guard !letters.isEmpty, let n = Int(digits) else { return nil }
    return (String(letters).uppercased(), n)
}

/// Every station on a line prefix, ordered by code index. Each entry is the
/// code on THIS line, the index, and the station name.
func wsLineSequence(prefix: String) -> [(code: String, num: Int, name: String)] {
    var seq: [(code: String, num: Int, name: String)] = []
    for st in MrtGeo.all {
        for c in st.codes {
            if let p = wsCodeParts(c), p.prefix == prefix {
                seq.append((c, p.num, st.name)); break
            }
        }
    }
    return seq.sorted { $0.num < $1.num }
}

/// The neighbouring stations around `station` on its primary heavy-rail line
/// (±`radius`), plus which line prefix they belong to. nil for LRT-only stops.
func wsLineNeighbors(around station: MrtGeoStation, radius: Int = 2)
    -> (prefix: String, items: [(code: String, name: String, current: Bool)])? {
    guard let code = station.codes.first(where: { wsLine(forStationCode: $0) != nil }),
          let (prefix, num) = wsCodeParts(code) else { return nil }
    let seq = wsLineSequence(prefix: prefix)
    guard let idx = seq.firstIndex(where: { $0.num == num }) else { return nil }
    let lo = max(0, idx - radius), hi = min(seq.count - 1, idx + radius)
    let items = seq[lo...hi].map { ($0.code, $0.name, $0.num == num) }
    return (prefix, Array(items))
}

/// The two platform directions for a station's primary line — "Towards
/// <first-station>" / "Towards <last-station>" derived from the line's ends.
func wsPlatformDirections(for station: MrtGeoStation) -> (a: String, b: String)? {
    guard let code = station.codes.first(where: { wsLine(forStationCode: $0) != nil }),
          let (prefix, _) = wsCodeParts(code) else { return nil }
    let seq = wsLineSequence(prefix: prefix)
    guard let first = seq.first, let last = seq.last, first.num != last.num else { return nil }
    return (last.name, first.name)   // ascending-index platform first (mockup order)
}

// MARK: - Shared station facilities grid

/// The 3×2 amenity grid — network-standard MRT facilities, greyscale chrome.
/// Shared by Home MRT mode and the pushed station screen so they never drift.
struct WSStationFacilitiesGrid: View {
    @Environment(\.ws) private var ws

    private struct Facility: Identifiable {
        let id = UUID(); let glyph: WSGlyph; let label: String
    }
    private let facilities: [Facility] = [
        .init(glyph: .restroom,   label: "Toilets"),
        .init(glyph: .lift,       label: "Lift"),
        .init(glyph: .wheelchair, label: "Accessible"),
        .init(glyph: .escalator,  label: "Escalator"),
        .init(glyph: .card,       label: "Top-up"),
        .init(glyph: .bag,        label: "Retail"),
    ]

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(facilities) { f in
                VStack(spacing: 8) {
                    WSIcon(glyph: f.glyph, size: 20, weight: .regular, color: ws.text)
                        .frame(height: 24)
                    Text(f.label)
                        .font(ws.sans(11.5, weight: .medium)).foregroundStyle(ws.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(ws.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - MRT-mode content

struct WSMrtHomeContent: View {
    let station: MrtGeoStation
    let distanceM: Int
    let walkMin: Int

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var forecast: [WSMrtStationView.ForecastPoint] = []

    private var crowdNow: CrowdLevel { store.wsCrowd(for: station) ?? .unknown }

    private var lines: [MRTLine] {
        var out: [MRTLine] = []
        for c in station.codes { if let l = wsLine(forStationCode: c), !out.contains(l) { out.append(l) } }
        return out
    }

    private var disrupted: Bool {
        station.codes.contains { code in
            store.trainAlerts.contains { $0.line == wsLine(forStationCode: code) }
        }
    }

    var body: some View {
        let _ = m.tick
        // Home keeps only what is LIVE and decision-relevant: the nearest
        // station, its platform crowd now + forecast, and a one-line service
        // status. Platforms, facilities and the line map are static and
        // already live on the station screen one tap away — stacking them
        // here was information overload (owner, 2026-07-19).
        VStack(spacing: 14) {
            stationCard.wsEntrance(delay: 0.06)
            crowdCard.wsEntrance(delay: 0.12)
            statusLine.wsEntrance(delay: 0.16)
        }
        .padding(.horizontal, 22)
        .onAppear {
            store.wsWarmCrowd(for: [station])
            for l in lines { store.refreshForecast(line: l) }
            loadForecast()
        }
        .onChange(of: station) { _, _ in
            store.wsWarmCrowd(for: [station]); loadForecast()
        }
    }

    // Nearest station — the hero of MRT mode: big bullet, name, line name,
    // walk line, a save toggle. Taps into the full station screen.
    private var stationCard: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            push(.mrtStation(station))
        } label: {
            HStack(alignment: .top, spacing: 14) {
                if let code = station.codes.first { LineBullet(code: code) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    Text("\(wsLineNames(from: station.codes)) Line")
                        .font(ws.sans(13.5, weight: .semibold))
                        .foregroundStyle(WSLine.color(forStationCode: station.codes.first ?? ""))
                    WalkLineMRT(distanceM: distanceM, walkMin: walkMin).padding(.top, 6)
                }
                Spacer(minLength: 8)
                WSHairButton(glyph: m.isMrtSaved(station) ? .bookmarkFilled : .bookmark) {
                    m.toggleMrtSaved(station)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ws.panel)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(WSCompressStyle())
        .wsZoomSource(id: wsMrtZoomID(station))
    }

    // Live platform crowd now + today's 30-min forecast bars.
    private var crowdCard: some View {
        WSCard(title: "Platform crowd forecast", glyph: .clock) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crowdNow == .unknown ? "—" : crowdNow.wsWord)
                            .font(ws.sans(17, weight: .heavy)).foregroundStyle(ws.text)
                        Text(crowdNow == .unknown ? "Live reading unavailable"
                                                  : sentenceCase(crowdNow.wsHint))
                            .font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
                    }
                    Spacer()
                    if crowdNow != .unknown { WSLiveBadge() }
                }
                .padding(.top, 6)

                if !forecast.isEmpty {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(forecast) { p in
                            ForecastBar(fraction: p.fraction, time: p.time, isNow: p.isNow)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // Service status, compressed to one quiet line — a whole card headlined
    // "Normal service" said nothing most of the time. Disruptions still get
    // their words; details live on the Alerts screen.
    private var statusLine: some View {
        // Amber = delay is pre-learned transit grammar (transit-color-
        // semantics): a disruption is the ONE thing on Home allowed to use
        // the warn tier — colour + word together, never colour alone.
        HStack(spacing: 10) {
            WSIcon(glyph: disrupted ? .bellRing : .live, size: 15, weight: .regular,
                   color: disrupted ? ws.warn : ws.now)
            Text(disrupted ? "Delays reported on this line — see Alerts"
                           : "Normal service on all lines")
                .font(ws.sans(13.5, weight: disrupted ? .semibold : .medium))
                .foregroundStyle(disrupted ? ws.warn : ws.dim)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(disrupted ? ws.warnFill : ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: disrupted)
        .accessibilityElement(children: .combine)
    }

    private func sentenceCase(_ s: String) -> String {
        s.prefix(1).uppercased() + s.lowercased().dropFirst()
    }

    // Forecast fetch — same shape as the station screen's loader.
    private func loadForecast() {
        guard let line = lines.first else { return }
        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
        Task {
            guard let intervals = try? await LTAService.shared.stationForecast(trainLine: line.pcdLineCode)
            else { return }
            let now = Date()
            let mine = intervals.filter { $0.station == code }.sorted { $0.start < $1.start }
            if let last = mine.last, now >= last.start.addingTimeInterval(30 * 60) {
                await MainActor.run { forecast = [] }; return
            }
            let upcomingIdx = mine.firstIndex { $0.start >= now } ?? max(0, mine.count - 1)
            let start = max(0, upcomingIdx - 1)
            let window = Array(mine[start..<min(mine.count, start + 6)])
            let pts = window.map { iv -> WSMrtStationView.ForecastPoint in
                let level = CrowdLevel.from(iv.crowdLevel)
                let isNow = iv.start <= now && (mine.first { $0.start > iv.start }?.start ?? .distantFuture) > now
                return .init(time: isNow ? "now" : WSFmt.clock(iv.start, use24h: m.use24h),
                             fraction: level.wsFraction, isNow: isNow, level: level)
            }
            await MainActor.run { forecast = pts }
        }
    }
}

/// Walk line for MRT mode (icon + "5 min walk · 420 m").
private struct WalkLineMRT: View {
    let distanceM: Int; let walkMin: Int
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 8) {
            WSIcon(glyph: .walk, size: 13, weight: .medium, color: ws.dim)
            Text(text)
                .font(ws.sans(13.5, weight: .medium)).foregroundStyle(ws.dim)
        }
    }
    /// Same sanity clamp as Home's bus WalkLine: no walk minutes beyond a
    /// plausible walk, no astronomical numbers from a far-off/stale GPS fix.
    private var text: String {
        guard distanceM > 0 else { return "Nearby" }
        if distanceM > 50_000 { return "Far from here" }
        guard walkMin <= 60 else { return "\(fmtDistance(distanceM)) away" }
        return "\(walkMin) min walk  ·  \(fmtDistance(distanceM))"
    }
}
