// Nearby Stops widget (Small / Medium). Shows the closest stops the app last
// resolved from the user's location, each with its walking time and the
// soonest service + ETA. The stop list + walk distance come from the App
// Group (the extension has no stop DB to compute them); arrivals are fetched
// live by the widget itself, same as the Stop widget.
//
// No location is read in the extension — the app publishes the nearby
// snapshot whenever it has a fresh fix, so the widget stays honest without
// requesting its own location authorization.

import WidgetKit
import SwiftUI

// ─── Timeline ────────────────────────────────────────────
struct NearbyRow: Hashable {
    let stop: WNearbyStop
    let top: WLTA.Row?       // soonest service at this stop (nil = none live)
}

struct NearbyEntry: TimelineEntry {
    let date: Date
    let rows: [NearbyRow]
}

struct NearbyProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearbyEntry {
        NearbyEntry(date: .now, rows: [
            NearbyRow(stop: .init(id: "1", name: "Opp Tempco Mfg", walkMin: 4),
                      top: .init(id: "91", eta1: 2, eta2: 12, eta3: 24)),
            NearbyRow(stop: .init(id: "2", name: "Tempco Mfg", walkMin: 4),
                      top: .init(id: "91", eta1: 6, eta2: 16, eta3: 28)),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyEntry) -> Void) {
        Task { completion(await entry(context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyEntry>) -> Void) {
        Task {
            let e = await entry(context.family)
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60))))
        }
    }

    private func entry(_ family: WidgetFamily) async -> NearbyEntry {
        let count = family == .systemMedium ? 3 : 2
        let stops = Array(loadNearby().prefix(count))
        // Fetch every stop's arrivals concurrently.
        let rows = await withTaskGroup(of: (Int, WLTA.Row?).self) { group -> [NearbyRow] in
            for (i, s) in stops.enumerated() {
                group.addTask { (i, await WLTA.arrivals(stop: s.id).first) }
            }
            var tops = Array<WLTA.Row?>(repeating: nil, count: stops.count)
            for await (i, r) in group { tops[i] = r }
            return zip(stops, tops).map { NearbyRow(stop: $0, top: $1) }
        }
        // Soonest bus first, not closest stop — on the Home Screen the
        // commuter's question is "which bus can I still catch?", and the
        // walk time is printed on each row anyway.
        return NearbyEntry(date: .now,
                           rows: rows.sorted { ($0.top?.eta1 ?? .max) < ($1.top?.eta1 ?? .max) })
    }
}

// ─── Row ─────────────────────────────────────────────────
private struct NearbyStopRow: View {
    let row: NearbyRow
    private var arriving: Bool { (row.top?.mon1 ?? false) && (row.top?.eta1 ?? 99) <= 1 }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.stop.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(wFg).lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk").font(.system(size: 9))
                    Text("\(row.stop.walkMin) min walk").font(.system(size: 10))
                }
                .foregroundStyle(wDim)
            }

            Spacer(minLength: 4)

            if let top = row.top {
                WServiceBadge(no: top.id, compact: true)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(schedPrefix(top.mon1, top.eta1) + etaLabel(top.eta1))
                        .font(.system(size: etaLabel(top.eta1) == "Arr" ? 18 : 24,
                                      weight: .medium, design: .monospaced))
                        .foregroundStyle(arriving ? wLive : wFg)
                        .widgetAccentable(arriving)
                        .contentTransition(.numericText(countsDown: true))
                    if etaLabel(top.eta1) != "Arr" {
                        Text("min").font(.system(size: 9)).foregroundStyle(wDim)
                    }
                }
            } else {
                Text("—").font(.system(size: 18, design: .monospaced)).foregroundStyle(wFaint)
            }
        }
        .widgetURL(stopURL(row.stop.id))
    }
}

// ─── View ────────────────────────────────────────────────
private struct NearbyWidgetView: View {
    let entry: NearbyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10)).foregroundStyle(wLive)
                    .widgetAccentable()
                Text("Nearby Stops")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(wFg)
                Spacer(minLength: 0)
            }

            if entry.rows.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "location.slash").font(.system(size: 16)).foregroundStyle(wDim)
                    Text("Open Leyne nearby")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(wFg)
                    Text("to find stops around you")
                        .font(.system(size: 9)).foregroundStyle(wDim)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Rectangle().fill(wLine).frame(height: 1).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(entry.rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(wLine).frame(height: 1) }
                        NearbyStopRow(row: row).padding(.vertical, 7)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(wBg, for: .widget)
    }
}

// ─── Widget ──────────────────────────────────────────────
struct LeyneNearbyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.leyne.Leyne.NearbyWidget",
                            provider: NearbyProvider()) { entry in
            NearbyWidgetView(entry: entry)
        }
        .configurationDisplayName("Nearby Stops")
        .description("The closest stops around you with live arrivals. Updates as you move (open Leyne to refresh your location).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
