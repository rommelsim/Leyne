// Home Screen widget: live next-bus times for a pinned stop.
// Self-contained — the widget extension can't import the app module. It reads
// the user's pinned stops from the shared App Group and fetches arrivals
// directly from LTA DataMall (same live source as the app, no mock data).

import WidgetKit
import SwiftUI
import AppIntents

// ─── Palette (matches the app / Live Activity) ────────────
private let wInk   = Color(red: 0x14/255, green: 0x11/255, blue: 0x0f/255)
private let wPaper = Color(red: 0xF2/255, green: 0xEF/255, blue: 0xE8/255)
private let wGreen = Color(red: 0x5B/255, green: 0xC0/255, blue: 0x7A/255)
private let wDim   = Color(red: 0x9a/255, green: 0x94/255, blue: 0x8a/255)

// ─── Shared App Group (pins published by the app) ─────────
private enum WGroup {
    static let id = "group.com.leyne"        // must match LyneWidgets.entitlements
    static let pinsKey = "lyne.pins.shared"
}

private struct WPinnedStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String
}

private func loadPinnedStops() -> [WPinnedStop] {
    guard let d = UserDefaults(suiteName: WGroup.id)?.data(forKey: WGroup.pinsKey),
          let s = try? JSONDecoder().decode([WPinnedStop].self, from: d)
    else { return [] }
    return s
}

// ─── Widget configuration intent (pick which pinned stop) ─
struct StopChoice: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pinned Stop"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Stop \(id)")
    }
    static var defaultQuery = StopChoiceQuery()
}

struct StopChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StopChoice] {
        loadPinnedStops().filter { identifiers.contains($0.id) }
            .map { StopChoice(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [StopChoice] {
        loadPinnedStops().map { StopChoice(id: $0.id, name: $0.name) }
    }
    func defaultResult() async -> StopChoice? {
        loadPinnedStops().first.map { StopChoice(id: $0.id, name: $0.name) }
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Stop"
    static var description = IntentDescription("Pick which pinned stop to show.")

    @Parameter(title: "Pinned stop")
    var stop: StopChoice?
}

// ─── Self-contained LTA Bus Arrival v3 client ─────────────
enum WLTA {
    static let key = "+6zJ3XstTqOcDkvczHttWA=="
    static let base = URL(string: "https://datamall2.mytransport.sg/ltaodataservice")!

    private struct Resp: Decodable { let Services: [Svc] }
    private struct Svc: Decodable {
        let ServiceNo: String
        let NextBus: Bus
        let NextBus2: Bus
    }
    private struct Bus: Decodable { let EstimatedArrival: String? }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static func mins(_ s: String?) -> Int? {
        guard let s, !s.isEmpty, let d = iso.date(from: s) ?? isoFrac.date(from: s)
        else { return nil }
        return max(0, Int((d.timeIntervalSinceNow / 60).rounded()))
    }

    struct Row: Identifiable { let id: String; let eta1: Int?; let eta2: Int? }

    static func arrivals(stop: String) async -> [Row] {
        var c = URLComponents(url: base.appendingPathComponent("v3/BusArrival"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "BusStopCode", value: stop)]
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "AccountKey")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Resp.self, from: data)
        else { return [] }
        return decoded.Services
            .map { Row(id: $0.ServiceNo, eta1: mins($0.NextBus.EstimatedArrival),
                       eta2: mins($0.NextBus2.EstimatedArrival)) }
            .sorted { ($0.eta1 ?? 999) < ($1.eta1 ?? 999) }
    }
}

// ─── Timeline ─────────────────────────────────────────────
struct StopEntry: TimelineEntry {
    let date: Date
    let stopName: String?      // nil → no stop pinned/selected
    let stopCode: String?
    let rows: [WLTA.Row]
}

struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(date: .now, stopName: "Bishan Int", stopCode: "53009",
                  rows: [.init(id: "88", eta1: 3, eta2: 12),
                         .init(id: "13", eta1: 7, eta2: 19),
                         .init(id: "851", eta1: 11, eta2: 24)])
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context)
        async -> Timeline<StopEntry> {
        let e = await entry(for: configuration)
        // Live arrivals — refresh roughly every minute (system may throttle).
        let next = Date().addingTimeInterval(60)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for configuration: SelectStopIntent) async -> StopEntry {
        let chosen = configuration.stop
            ?? loadPinnedStops().first.map { StopChoice(id: $0.id, name: $0.name) }
        guard let chosen else {
            return StopEntry(date: .now, stopName: nil, stopCode: nil, rows: [])
        }
        let rows = await WLTA.arrivals(stop: chosen.id)
        return StopEntry(date: .now, stopName: chosen.name,
                         stopCode: chosen.id, rows: rows)
    }
}

// ─── Views ────────────────────────────────────────────────
private func etaLabel(_ m: Int?) -> String {
    guard let m else { return "—" }
    return m <= 0 ? "Arr" : "\(m)"
}

private struct ServiceRow: View {
    let row: WLTA.Row
    let showSecond: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(row.id)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(wGreen, in: RoundedRectangle(cornerRadius: 5))
                .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(etaLabel(row.eta1))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(wPaper)
                Text("min").font(.system(size: 9)).foregroundStyle(wDim)
            }
            if showSecond {
                Text(etaLabel(row.eta2))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(wDim)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

private struct StopWidgetView: View {
    let entry: StopEntry
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = entry.stopName {
                HStack(spacing: 5) {
                    Image(systemName: "bus.fill").font(.system(size: 10))
                        .foregroundStyle(wGreen)
                    Text(name).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(wPaper).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if entry.rows.isEmpty {
                    Spacer()
                    Text("No buses right now")
                        .font(.system(size: 11)).foregroundStyle(wDim)
                    Spacer()
                } else {
                    VStack(spacing: family == .systemSmall ? 5 : 7) {
                        ForEach(Array(entry.rows.prefix(maxRows))) { r in
                            ServiceRow(row: r, showSecond: family != .systemSmall)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(entry.date, style: .time)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(wDim)
                }
            } else {
                Spacer()
                Text("Pin a stop in Leyne")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(wPaper)
                Text("Long-press to choose it here")
                    .font(.system(size: 10)).foregroundStyle(wDim)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(wInk, for: .widget)
    }
}

struct LyneStopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.lyne.Lyne.StopWidget",
                               intent: SelectStopIntent.self,
                               provider: StopProvider()) { entry in
            StopWidgetView(entry: entry)
        }
        .configurationDisplayName("Pinned Stop")
        .description("Live bus arrivals for a stop you pinned in Leyne.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
