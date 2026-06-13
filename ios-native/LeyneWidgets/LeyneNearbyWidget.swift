// Nearest Stop widget (Small only). Shows the single closest stop the app
// last resolved from the user's location — its name and stop code — with a
// tap that deep-links into that stop's arrivals view.
//
// No location is read in the extension and no arrivals are fetched here.
// The app publishes the nearby snapshot to the App Group whenever it gets a
// fresh location fix and calls WidgetCenter.reloadAllTimelines(), so this
// widget stays current without ever doing its own network or GPS work.

import WidgetKit
import SwiftUI

// ─── Entry ───────────────────────────────────────────────
struct NearestEntry: TimelineEntry {
    let date: Date
    /// nil when the app has not yet published any nearby data.
    let stop: WNearbyStop?
    /// True for the gallery/placeholder preview only. A sample entry must NEVER
    /// deep-link to its (fake) stop code — otherwise tapping the redacted
    /// skeleton opens a non-existent stop in the app.
    var isSample: Bool = false
}

// A representative stop for the gallery preview + redacted placeholder. Only
// ever shown with `isSample: true`, so its code is never used for navigation.
private let sampleStop = WNearbyStop(id: "00000", name: "Opp Blk 123", walkMin: 2)

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
    func getSnapshot(in context: Context, completion: @escaping (NearestEntry) -> Void) {
        if let real = loadNearby().first {
            completion(NearestEntry(date: .now, stop: real))
        } else if context.isPreview {
            completion(NearestEntry(date: .now, stop: sampleStop, isSample: true))
        } else {
            completion(NearestEntry(date: .now, stop: nil))
        }
    }

    // Timeline — the LIVE widget. Real nearest stop or nil (→ empty state).
    // Never a sample. The app's reloadAllTimelines() on location change is the
    // primary refresh; a 30-minute backstop avoids permanent staleness.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestEntry>) -> Void) {
        let entry = NearestEntry(date: .now, stop: loadNearby().first)
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
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

    // Normal state: stop name + code.
    private func filledView(_ stop: WNearbyStop, isSample: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow: pin glyph + "NEAREST STOP" label
            HStack(spacing: 5) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(wDim)
                    .widgetAccentable()
                Text("NEAREST STOP")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(wDim)
                    .kerning(0.5)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 8)

            // Stop name — bold, scales down for long names.
            Text(stop.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(wFg)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: false)

            Spacer(minLength: 6)

            // Stop code — subtle, monospaced digits.
            Text("Stop \(stop.id)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(wDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(wBg, for: .widget)
        // A sample preview links to the app base, never its fake stop code.
        .widgetURL(isSample ? URL(string: "lyne://") : stopURL(stop.id))
    }

    // Empty state: prompt the user to open the app.
    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 20))
                .foregroundStyle(wDim)
            Text("Open Leyne to find stops near you")
                .font(.system(size: 11, weight: .medium))
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
        .description("The bus stop you're at — tap to see its arrivals.")
        .supportedFamilies([.systemSmall])
    }
}
