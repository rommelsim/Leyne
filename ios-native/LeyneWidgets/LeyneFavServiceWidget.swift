// Favourite Service widget (Medium). Pins one favourited bus service at a
// specific stop and shows its nearest arrival. The user picks which favourite
// via the widget's edit sheet; favourites are published by the app (with the
// stop name + route destination pre-resolved, since the extension has no
// route/stop database). Arrivals for the service are fetched live here and
// filtered to the chosen service number.

import WidgetKit
import SwiftUI
import AppIntents

// ─── Configuration intent ────────────────────────────────
struct FavChoice: AppEntity {
    let id: String          // "<no>#<stopCode>"
    let no: String
    let stopCode: String
    let stopName: String
    let dest: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Favourite Service"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(no) · \(stopName)")
    }
    static var defaultQuery = FavChoiceQuery()

    init(id: String, no: String, stopCode: String, stopName: String, dest: String) {
        self.id = id; self.no = no; self.stopCode = stopCode
        self.stopName = stopName; self.dest = dest
    }
    init(_ f: WFavService) {
        self.init(id: f.id, no: f.no, stopCode: f.stopCode, stopName: f.stopName, dest: f.dest)
    }
}

struct FavChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavChoice] {
        loadFavs().filter { identifiers.contains($0.id) }.map(FavChoice.init)
    }
    func suggestedEntities() async throws -> [FavChoice] {
        loadFavs().map(FavChoice.init)
    }
    func defaultResult() async -> FavChoice? {
        loadFavs().first.map(FavChoice.init)
    }
}

struct SelectFavIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pick favourite service"
    static var description = IntentDescription(
        "Choose which favourited service this widget shows. Favourite a service in WhereSia to add it here."
    )

    @Parameter(title: "Service")
    var fav: FavChoice?
}

// ─── Timeline ────────────────────────────────────────────
struct FavEntry: TimelineEntry {
    let date: Date
    let fav: WFavService?
    let row: WLTA.Row?       // the chosen service's arrivals at the stop
}

struct FavProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavEntry {
        FavEntry(date: .now,
                 fav: .init(no: "186", stopCode: "11389",
                            stopName: "Farrer Rd Stn Exit B", dest: "St. Michael's Ter"),
                 row: .init(id: "186", eta1: 2, eta2: 18, eta3: 35))
    }

    func snapshot(for configuration: SelectFavIntent, in context: Context) async -> FavEntry {
        await entry(configuration)
    }

    func timeline(for configuration: SelectFavIntent, in context: Context) async -> Timeline<FavEntry> {
        let e = await entry(configuration)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60)))
    }

    private func entry(_ configuration: SelectFavIntent) async -> FavEntry {
        let favs = loadFavs()
        // The configured fav (resolved against the current list so a renamed
        // stop stays correct), falling back to the first published favourite.
        let chosen = configuration.fav.flatMap { c in favs.first { $0.id == c.id } }
            ?? favs.first
        guard let fav = chosen else { return FavEntry(date: .now, fav: nil, row: nil) }
        let row = await WLTA.arrivals(stop: fav.stopCode).first { $0.id == fav.no }
        return FavEntry(date: .now, fav: fav, row: row)
    }
}

// ─── View ────────────────────────────────────────────────
private struct FavWidgetView: View {
    let entry: FavEntry

    var body: some View {
        Group {
            if let fav = entry.fav {
                content(fav)
            } else {
                EmptyFavView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(wBg, for: .widget)
    }

    private func content(_ fav: WFavService) -> some View {
        let arriving = (entry.row?.mon1 ?? false) && (entry.row?.eta1 ?? 99) <= 1
        return VStack(alignment: .leading, spacing: 0) {
            // Header: route tile + destination + favourite star.
            HStack(spacing: 10) {
                WServiceBadge(no: fav.no)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TOWARDS").font(wMono(8.5)).kerning(0.8).foregroundStyle(wDim)
                    Text(fav.dest.isEmpty ? fav.stopName : fav.dest)
                        .font(wSans(14, .bold))
                        .foregroundStyle(wFg).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(wFaint)
                    .widgetAccentable()
            }

            Rectangle().fill(wLine).frame(height: 1).padding(.vertical, 10)

            // Board section header — with the LIVE mark when the reading is
            // GPS-monitored (the word explains itself; no legend needed).
            HStack(spacing: 8) {
                Text("NEXT ARRIVAL")
                    .font(wSans(9, .heavy)).kerning(1.1)
                    .foregroundStyle(wDim)
                if entry.row?.mon1 == true { WLiveBadge() }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fav.stopName)
                    .font(wSans(13.5, .semibold))
                    .foregroundStyle(wFg).lineLimit(1)
                Spacer(minLength: 4)
                if let row = entry.row {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(schedPrefix(row.mon1, row.eta1) + etaLabel(row.eta1))
                            .font(wMono(etaLabel(row.eta1) == "Arr" ? 24 : 32,
                                        arriving ? .bold : .medium))
                            .foregroundStyle(arriving ? wAccentSoft : wFg)
                            .widgetAccentable(arriving)
                            .contentTransition(.numericText(countsDown: true))
                        if etaLabel(row.eta1) != "Arr" {
                            Text("min").font(wMono(10.5)).foregroundStyle(wDim)
                        }
                    }
                } else {
                    Text("—").font(wMono(24)).foregroundStyle(wFaint)
                }
            }
            .padding(.top, 4)

            // Following two arrivals — the quiet "then 12 · 24 min" line.
            if let row = entry.row, row.eta2 != nil || row.eta3 != nil {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("then " + [row.eta2, row.eta3].compactMap { $0 }.prefix(2)
                        .map { $0 <= 0 ? "Arr" : "\($0)" }.joined(separator: " · ") + " min")
                        .font(wMono(10.5))
                        .foregroundStyle(wFaint)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .widgetURL(serviceURL(fav.no, stop: fav.stopCode))
    }
}

private struct EmptyFavView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "star.slash").font(.system(size: 18)).foregroundStyle(wDim)
            Text("Favourite a service in WhereSia")
                .font(wSans(12, .semibold)).foregroundStyle(wFg)
            Text("Tap the star on a bus to add it here")
                .font(wSans(10, .medium)).foregroundStyle(wDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─── Widget ──────────────────────────────────────────────
struct LeyneFavServiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.leyne.Leyne.FavServiceWidget",
                               intent: SelectFavIntent.self,
                               provider: FavProvider()) { entry in
            FavWidgetView(entry: entry)
        }
        .configurationDisplayName("Favourite Service")
        .description("Live arrivals for a service you favourited in WhereSia.")
        .supportedFamilies([.systemMedium])
    }
}
