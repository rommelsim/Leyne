// Nearest Stop — the one Home Screen widget. Shows the closest bus stop's
// name (no ETAs; the widget is a doorway, not a board). The app publishes
// the nearest stop to the App Group whenever location resolves
// (DataStore.mirrorNearestToWidget); the widget just displays the snapshot.
// Tap → lyne://stop/<code> → the app's Stop view (RootView.onOpenURL).
//
// Hierarchy (2026-07-13 HIG pass): walk time is the actionable fact so it
// owns the bold footer + the accent; the stop code is reference data and
// rides along as a faint caption with the freshness stamp. The kicker is
// greyscale — colour is reserved for data, per the app's colour discipline.

import WidgetKit
import SwiftUI
import CoreLocation

// ─── App Group snapshot (published by the app) ───────────────────────
// Decodes SharedNearestStop from DataStore.swift — same fields, same key.
// Fallback only: the widget prefers its own location fix (below).
struct WNearestStop: Codable {
    let id: String      // bus stop code
    let name: String
    let road: String?
    let walkMin: Int
    let asOf: Date      // when the app last confirmed this from live location
}

func loadNearestStop() -> WNearestStop? {
    guard let d = UserDefaults(suiteName: "group.com.leyne")?
            .data(forKey: "leyne.nearest.shared") else { return nil }
    return try? JSONDecoder().decode(WNearestStop.self, from: d)
}

// ─── Self-locating nearest stop ──────────────────────────────────────
// NSWidgetWantsLocation (widget Info.plist) lets the extension take a
// one-shot fix at each WidgetKit refresh — no 24/7 tracking, and it rides
// on the app's existing when-in-use authorization. The app publishes the
// full stop directory (SharedLiteStop in DataStore.swift) so the widget can
// resolve "nearest" itself even when the app hasn't run for days.

/// Mirrors SharedLiteStop — same short keys, same file.
struct WLiteStop: Codable {
    let c: String       // bus stop code
    let n: String       // name
    let r: String       // road
    let la: Double
    let lo: Double
}

func loadStopDirectory() -> [WLiteStop] {
    guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.leyne"),
          let d = try? Data(contentsOf: dir.appendingPathComponent("stops.widget.json")),
          let v = try? JSONDecoder().decode([WLiteStop].self, from: d)
    else { return [] }
    return v
}

/// One-shot location for a timeline reload. Resolves nil (→ snapshot
/// fallback) when the widget isn't authorized or the fix times out.
final class WOneShotLocation: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    func fix() async -> CLLocation? {
        let status = mgr.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              mgr.isAuthorizedForWidgetUpdates else { return nil }
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // A cached fix a couple of minutes old is plenty for "nearest stop"
        // and avoids burning the extension's short runtime on GPS warm-up.
        if let loc = mgr.location, loc.timestamp > .now.addingTimeInterval(-180) {
            return loc
        }
        return await withCheckedContinuation { c in
            cont = c
            mgr.requestLocation()
        }
    }
    private func finish(_ loc: CLLocation?) {
        cont?.resume(returning: loc)
        cont = nil
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        finish(locs.first)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}

private func haversineM(_ lat1: Double, _ lon1: Double,
                        _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}

/// Nearest stop from the widget's own fix; nil when location or the
/// directory is unavailable. Walk time mirrors the app: ~80 m/min, min 1.
func resolveNearestStop() async -> WNearestStop? {
    let stops = loadStopDirectory()
    guard !stops.isEmpty, let loc = await WOneShotLocation().fix() else { return nil }
    let here = loc.coordinate
    guard let best = stops.min(by: {
        haversineM(here.latitude, here.longitude, $0.la, $0.lo)
            < haversineM(here.latitude, here.longitude, $1.la, $1.lo)
    }) else { return nil }
    let d = haversineM(here.latitude, here.longitude, best.la, best.lo)
    return WNearestStop(id: best.c, name: best.n,
                        road: best.r.isEmpty ? nil : best.r,
                        walkMin: max(1, Int((d / 80).rounded())),
                        asOf: .now)
}

// ─── Timeline ────────────────────────────────────────────────────────
struct NearestEntry: TimelineEntry {
    let date: Date
    let stop: WNearestStop?     // nil = app hasn't published yet (fresh install)
    var isSample = false        // gallery preview / placeholder
}

struct NearestProvider: TimelineProvider {
    static let sample = WNearestStop(id: "83139", name: "Blk 662", road: "Ubi Ave 1",
                                     walkMin: 2, asOf: .now)

    func placeholder(in context: Context) -> NearestEntry {
        NearestEntry(date: .now, stop: Self.sample, isSample: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (NearestEntry) -> Void) {
        if context.isPreview {
            completion(NearestEntry(date: .now, stop: Self.sample, isSample: true))
        } else {
            completion(NearestEntry(date: .now, stop: loadNearestStop()))
        }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestEntry>) -> Void) {
        // Each reload takes its own location fix and resolves the nearest
        // stop right here, so the widget tracks the user automatically. The
        // app-published snapshot is the fallback (widget location off,
        // directory not yet published, or no fix). A short refresh window
        // keeps it current; WidgetKit also reloads on significant-location
        // change for location-using widgets, and the app still pushes a
        // reload whenever it sees the nearest stop change.
        Task {
            let stop = await resolveNearestStop() ?? loadNearestStop()
            let entry = NearestEntry(date: .now, stop: stop)
            completion(Timeline(entries: [entry],
                                policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

// ─── View ────────────────────────────────────────────────────────────
struct NearestStopView: View {
    let entry: NearestEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let stop = entry.stop {
                content(stop)
                    .widgetURL(entry.isSample ? URL(string: "lyne://")
                                              : URL(string: "lyne://stop/\(stop.id)"))
            } else {
                empty
                    .widgetURL(URL(string: "lyne://"))
            }
        }
        .containerBackground(wBg, for: .widget)
    }

    /// The road line is only worth its row when it adds information —
    /// "Farrer Rd Stn Exit B / Farrer Rd" just repeats itself.
    private func usefulRoad(_ stop: WNearestStop) -> String? {
        guard let road = stop.road, !road.isEmpty,
              !stop.name.localizedCaseInsensitiveContains(road) else { return nil }
        return road
    }

    private var isMedium: Bool { family == .systemMedium }

    private func content(_ stop: WNearestStop) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kicker — greyscale: it's a label, not data.
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("NEAREST STOP").font(wMono(8.5, .bold)).kerning(1.0)
            }
            .foregroundStyle(wDim)

            // Name block sits right under the kicker — the old floating gap
            // was the widget's biggest visual element.
            Text(stop.name)
                .font(wSans(isMedium ? 22 : 17, .bold))
                .foregroundStyle(wFg)
                .lineLimit(isMedium ? 1 : 2)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
                .padding(.top, 6)

            if let road = usefulRoad(stop) {
                Text(road)
                    .font(wSans(isMedium ? 13 : 11))
                    .foregroundStyle(wDim)
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            Spacer(minLength: 4)

            // Footer — walk time is the actionable fact: bold, accented.
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: isMedium ? 13 : 11, weight: .semibold))
                Text("\(stop.walkMin) min walk")
                    .font(wSans(isMedium ? 15 : 13, .semibold))
            }
            .foregroundStyle(wAccentSoft)
            .widgetAccentable()

            // Reference caption: stop code in a quiet pill (so it reads as a
            // code, distinct from the walk line) + freshness stamp.
            HStack(spacing: 5) {
                Text(stop.id)
                    .font(wMono(isMedium ? 10 : 9, .medium))
                    .foregroundStyle(wDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(wPanel2, in: Capsule())
                    .overlay(Capsule().stroke(wLine, lineWidth: 1))
                Text("Updated \(stop.asOf.formatted(date: .omitted, time: .shortened))")
                    .font(wSans(isMedium ? 10 : 9))
                    .foregroundStyle(wFaint)
                    .lineLimit(1)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Fresh install / location never resolved: point at the app instead of
    // showing a fake stop (no-mock-data rule).
    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "location.slash")
                    .font(.system(size: 8, weight: .bold))
                Text("NEAREST STOP").font(wMono(8.5, .bold)).kerning(1.0)
            }
            .foregroundStyle(wDim)
            Spacer(minLength: 0)
            Text("Open the app once to find your nearest stop")
                .font(wSans(12, .medium))
                .foregroundStyle(wDim)
                .widgetAccentable()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// ─── Widget ──────────────────────────────────────────────────────────
struct LeyneNearestStopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.leyne.Leyne.NearestStopWidget",
                            provider: NearestProvider()) { entry in
            NearestStopView(entry: entry)
        }
        .configurationDisplayName("Nearest Stop")
        .description("Your closest bus stop — tap to see its departures.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
