// Nearest Stop widget (Small only) — a mini WhereSia departure board: the
// closest stop the app last resolved, its next buses LIVE (route tile + mono
// ETA), the LIVE badge, and the code · walk meta line. Tap deep-links into
// the stop's arrivals view.
//
// The app publishes the nearby stop list to the App Group whenever it gets a
// fresh location fix (no location is read in the extension); the widget
// fetches the live arrivals itself via the self-contained WLTA client —
// same source, same 60s cadence as the other live widgets.

import WidgetKit
import SwiftUI

// ─── Entry ───────────────────────────────────────────────
struct NearestEntry: TimelineEntry {
    let date: Date
    /// nil when the app has not yet published any nearby data.
    let stop: WNearbyStop?
    /// Soonest live arrivals at the stop (≤ 2, soonest first).
    var rows: [WLTA.Row] = []
    /// True for the gallery/placeholder preview only. A sample entry must NEVER
    /// deep-link to its (fake) stop code — otherwise tapping the redacted
    /// skeleton opens a non-existent stop in the app.
    var isSample: Bool = false
}

// A representative stop for the gallery preview + redacted placeholder. Only
// ever shown with `isSample: true`, so its code is never used for navigation.
private let sampleStop = WNearbyStop(id: "00000", name: "Opp Blk 123", walkMin: 2)
private let sampleRows: [WLTA.Row] = [.init(id: "48", eta1: 1, eta2: 9),
                                      .init(id: "93", eta1: 4, eta2: 12)]

/// The two soonest arrivals — the widget answers "what can I still catch",
/// so unlike the in-app board (number-sorted, scannable) this tiny cut of it
/// is soonest-first.
private func soonestRows(_ rows: [WLTA.Row]) -> [WLTA.Row] {
    Array(rows.filter { $0.eta1 != nil }
        .sorted { ($0.eta1 ?? 999) < ($1.eta1 ?? 999) }
        .prefix(2))
}

// ─── Provider ────────────────────────────────────────────
struct NearestProvider: TimelineProvider {
    // Placeholder — the brief skeleton before data loads. Use the EMPTY state
    // (not a fake sample) so a redacted/loading frame reads as "no data yet",
    // never bars that look like a real stop.
    func placeholder(in context: Context) -> NearestEntry {
        NearestEntry(date: .now, stop: nil)
    }

    // Snapshot — show the SAMPLE only in the gallery picker (`isPreview`); on
    // the actual home screen show real data or the empty state (never a sample).
    // No network here: snapshots must return fast, so real data appears
    // without rows and the first timeline pass fills them in.
    func getSnapshot(in context: Context, completion: @escaping (NearestEntry) -> Void) {
        if let real = loadNearby().first {
            completion(NearestEntry(date: .now, stop: real))
        } else if context.isPreview {
            completion(NearestEntry(date: .now, stop: sampleStop, rows: sampleRows, isSample: true))
        } else {
            completion(NearestEntry(date: .now, stop: nil))
        }
    }

    // Timeline — the LIVE widget: nearest stop + its soonest arrivals from
    // LTA. Refreshes ~every minute while a stop is known (the system budgets
    // actual cadence); a 30-minute backstop when there's nothing to show.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestEntry>) -> Void) {
        Task {
            let stop = loadNearby().first
            var rows: [WLTA.Row] = []
            if let stop { rows = soonestRows(await WLTA.arrivals(stop: stop.id)) }
            let entry = NearestEntry(date: .now, stop: stop, rows: rows)
            let refresh: TimeInterval = stop == nil ? 30 * 60 : 60
            completion(Timeline(entries: [entry],
                                policy: .after(Date().addingTimeInterval(refresh))))
        }
    }
}

// ─── View ────────────────────────────────────────────────
private struct NearestWidgetView: View {
    let entry: NearestEntry

    var body: some View {
        if let stop = entry.stop {
            filledView(stop, isSample: entry.isSample)
        } else {
            emptyView
        }
    }

    // The mini board: eyebrow + LIVE + rule, stop name, service rows
    // (route tile ⟷ big mono ETA), code · walk meta line.
    private func filledView(_ stop: WNearbyStop, isSample: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("NEAREST")
                    .font(wSans(9, .heavy))
                    .kerning(1.1)
                    .foregroundStyle(wDim)
                    .lineLimit(1)
                    .fixedSize()
                if entry.rows.contains(where: { $0.mon1 }) { WLiveBadge() }
                Rectangle().fill(wLine).frame(height: 1)
            }

            Text(stop.name)
                .font(wSans(14.5, .bold))
                .foregroundStyle(wFg)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 8)

            Spacer(minLength: 5)

            if entry.rows.isEmpty {
                Text("No live arrivals")
                    .font(wSans(11, .medium))
                    .foregroundStyle(wDim)
                Spacer(minLength: 5)
            } else {
                VStack(spacing: 7) {
                    ForEach(entry.rows) { row in
                        HStack(spacing: 6) {
                            WServiceBadge(no: row.id, compact: true)
                            Spacer(minLength: 4)
                            arrivalText(row)
                        }
                    }
                }
                Spacer(minLength: 6)
            }

            Text(stop.walkMin > 0 ? "\(stop.id) · \(stop.walkMin) MIN WALK" : stop.id)
                .font(wMono(9.5, .medium))
                .kerning(0.3)
                .foregroundStyle(wDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(wBg, for: .widget)
        // A sample preview links to the app base, never its fake stop code.
        .widgetURL(isSample ? URL(string: "lyne://") : stopURL(stop.id))
    }

    /// "1 min" — mono hero, whisper "~" for scheduled-only, live-blue when
    /// the bus is pulling in (quotes the in-app board).
    private func arrivalText(_ row: WLTA.Row) -> some View {
        let arriving = row.mon1 && (row.eta1 ?? 99) <= 1
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(schedPrefix(row.mon1, row.eta1) + etaLabel(row.eta1))
                .font(wMono(16, arriving ? .bold : .medium))
                .foregroundStyle(arriving ? wAccentSoft : wFg)
                .widgetAccentable(arriving)
                .contentTransition(.numericText(countsDown: true))
            if etaLabel(row.eta1) != "Arr" {
                Text("min").font(wMono(9)).foregroundStyle(wDim)
            }
        }
    }

    // Empty state: prompt the user to open the app.
    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 20))
                .foregroundStyle(wDim)
            Text("Open WhereSia to find stops near you")
                .font(wSans(11, .semibold))
                .foregroundStyle(wFg)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(wBg, for: .widget)
        .widgetURL(URL(string: "lyne://"))
    }
}

// ─── Widget ──────────────────────────────────────────────
struct LeyneNearbyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.leyne.Leyne.NearbyWidget",
                            provider: NearestProvider()) { entry in
            NearestWidgetView(entry: entry)
        }
        .configurationDisplayName("Nearest Stop")
        .description("The stop you're at, with its next buses live.")
        .supportedFamilies([.systemSmall])
    }
}
