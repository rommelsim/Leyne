// Nearest Stop widget — the closest stop the app last resolved, restyled to
// the "soft blue 4b" board: white/pale-blue-tint card, tinted-blue chips +
// glow on the soonest bus, crowd dots+word. Tap deep-links into the stop's
// arrivals view.
//
// Medium (.systemMedium) ONLY — the widget lineup is exactly one widget in
// one size (owner directive, 2026-07-24). The rich live board: up to three
// full-width arrival lines (bus · crowd · next · the two after it) plus an
// honest "updated Xs/min ago" caption, so the ETAs it DOES show are always
// paired with how fresh they are.
//
// The app publishes the nearby stop list to the App Group whenever it gets a
// fresh location fix (no location is read in the extension); the widget
// fetches the live arrivals itself via the self-contained WLTA client —
// same source, same 60s cadence as the other live widgets.

import WidgetKit
import SwiftUI
import CoreLocation

// ─── Entry ───────────────────────────────────────────────
struct NearestEntry: TimelineEntry {
    let date: Date
    /// nil when the app has not yet published any nearby data.
    let stop: WNearbyStop?
    /// Soonest live arrivals at the stop (≤ 3, soonest first).
    var rows: [WLTA.Row] = []
    /// True for the gallery/placeholder preview only. A sample entry must NEVER
    /// deep-link to its (fake) stop code — otherwise tapping the redacted
    /// skeleton opens a non-existent stop in the app.
    var isSample: Bool = false
}

// A representative stop for the gallery preview + redacted placeholder. Only
// ever shown with `isSample: true`, so its code is never used for navigation.
private let sampleStop = WNearbyStop(id: "00000", name: "Opp Blk 123",
                                     walkMin: 2, distanceM: 180)
private let sampleRows: [WLTA.Row] = [.init(id: "48", eta1: 1, eta2: 9, mon1: true, load1: .seats),
                                      .init(id: "93", eta1: 4, eta2: 12, mon1: true, load1: .standing),
                                      .init(id: "17", eta1: 11, eta2: 22, mon1: true, load1: .packed)]

/// The soonest arrivals — the widget answers "what can I still catch", so
/// unlike the in-app board (number-sorted, scannable) this tiny cut of it is
/// soonest-first. Medium shows up to 3 tiles; Small doesn't render any.
private func soonestRows(_ rows: [WLTA.Row]) -> [WLTA.Row] {
    Array(rows.filter { $0.eta1 != nil }
        .sorted { ($0.eta1 ?? 999) < ($1.eta1 ?? 999) }
        .prefix(3))
}

// ─── Which stop is "nearest" ─────────────────────────────
// Location first, app snapshot second.
//
// The widget used to take `loadNearby().first` — the stop the APP last
// resolved. That only ever changes while Departly is open with a location
// fix, so travelling somewhere new without launching the app left the widget
// pinned to the stop you'd left, still refreshing real arrivals for it
// (owner 2026-07-26). Now the extension resolves the nearest stop from its
// own fix against the shared directory, and only falls back to the app's
// snapshot when it has no location (permission off, no fix in time) or the
// directory hasn't been published yet — i.e. the old behaviour is the floor,
// never the ceiling.

/// Async path — used by the timeline, where we can afford to wait for a fix.
private func resolvedStop() async -> WNearbyStop? {
    if let loc = await WLocator.shared.current() {
        let index = loadStopIndex()
        if let nearest = wNearestStop(to: loc, in: index) { return nearest }
    }
    return loadNearby().first
}

/// Synchronous path for `getSnapshot`, which must return fast: use a cached
/// fix if one is already sitting there, otherwise the app's snapshot.
private func resolvedStopFast() -> WNearbyStop? {
    if let loc = WLocator.shared.cachedLocation(maxAge: 600),
       let nearest = wNearestStop(to: loc, in: loadStopIndex()) {
        return nearest
    }
    return loadNearby().first
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
        if let real = resolvedStopFast() {
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
            let stop = await resolvedStop()
            var rows: [WLTA.Row] = []
            if let stop { rows = soonestRows(await WLTA.arrivals(stop: stop.id)) }
            let entry = NearestEntry(date: .now, stop: stop, rows: rows)
            let refresh: TimeInterval = stop == nil ? 30 * 60 : 60
            completion(Timeline(entries: [entry],
                                policy: .after(Date().addingTimeInterval(refresh))))
        }
    }
}

// ─── Medium — live board: header + up to 3 arrival lines ──

/// "· 2 min walk · 180m". The metres are dropped, not faked, when the entry
/// came from an older app payload that never carried them.
private func metaLine(_ stop: WNearbyStop) -> String {
    var s = "· \(stop.walkMin) min walk"
    if let m = stop.distanceM { s += " · \(wFmtDistance(m))" }
    return s
}

private struct MediumNearestView: View {
    let entry: NearestEntry

    var body: some View {
        if let stop = entry.stop {
            VStack(alignment: .leading, spacing: 9) {
                // The stop name is the widget's identity — it was 12pt grey,
                // quieter than the ETAs it labels, and carried no sign it was
                // a BUS stop (owner 2026-07-25). Now: the app's bus glyph, the
                // name in full ink, freshness stays the faint trailing caption.
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "bus.doubledecker")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(wChipInk)
                    Text(stop.name)
                        .font(wSans(13.5, .bold))
                        .foregroundStyle(wFg)
                        .lineLimit(1)
                        .layoutPriority(1)
                    // Walk time AND metres — the other half of "can I still
                    // catch it", in the app's own order and format (Saved and
                    // the stop screen both read "N min walk · Xm"). Sits in
                    // what used to be empty slack between the name and the
                    // freshness caption.
                    //
                    // Lower layout priority than the name and allowed to
                    // shrink: on a long stop name the metrics give way, the
                    // identity never truncates.
                    Text(metaLine(stop))
                        .font(wSans(10.5, .medium))
                        .foregroundStyle(wDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(0.5)
                    Spacer(minLength: 6)
                    WUpdatedCaption(date: entry.date)
                }

                if entry.rows.isEmpty {
                    Text("No live arrivals")
                        .font(wSans(12, .medium)).foregroundStyle(wDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    // Fills the remaining height so the board IS the card —
                    // the three lines split it between them, no dead band.
                    WArrivalBoard(rows: entry.rows)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .wCardChrome()
            .containerBackground(wBgGradient, for: .widget)
            .widgetURL(entry.isSample ? URL(string: "lyne://") : stopURL(stop.id))
        } else {
            EmptyNearestView()
        }
    }
}

// ─── Empty state ───────────────────────────────────────────
private struct EmptyNearestView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 20))
                .foregroundStyle(wDim)
            Text("Open Departly to find stops near you")
                .font(wSans(11, .semibold))
                .foregroundStyle(wFg)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wCardChrome()
        .containerBackground(wBgGradient, for: .widget)
        .widgetURL(URL(string: "lyne://"))
    }
}

// ─── Top-level widget view ─────────────────────────────────
// Medium-only lineup — no family switch needed.
private struct NearestWidgetView: View {
    let entry: NearestEntry

    var body: some View {
        MediumNearestView(entry: entry)
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
        .description("The stop you're at, with its live next buses.")
        .supportedFamilies([.systemMedium])
        // The card owns its own 16/15 padding via `.wCardChrome()` — turn
        // off the system's automatic content margins so they don't stack.
        .contentMarginsDisabled()
    }
}
