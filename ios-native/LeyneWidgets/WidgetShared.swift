// Shared foundation for every Home Screen widget in the extension. The
// extension can't import the app module, so the palette, the fonts (SF, same
// as the app — see the Fonts section), the App Group readers, the
// self-contained LTA client, and the common UI atoms all live here once
// instead of being copy-pasted per widget.
//
// "Soft blue 4b" (branch design-greendark, restyled off the app's soft-blue
// pass): a fixed LIGHT board — white/pale-blue-tint surfaces, dark ink text,
// and a single blue accent family for everything live (a darker #2E8FE0 on
// light surfaces, a lighter #5CB8F2 on the Dynamic Island, which the system
// always renders on black chrome regardless of app styling). This is a LOCAL
// palette, intentionally decoupled from Leyne/WhereSia/WSSoftTheme.swift (a
// different, app-owned surface) — the widget extension can't import that
// module anyway, and the widget target keeps its own copy of the tokens.
//
// Fixed-light, not colorScheme-adaptive: same call as the previous (dark)
// pass, just flipped — the design spec hands us one set of hex values, not a
// light/dark pair, so every widget/Live Activity surface renders as the
// light board regardless of the device's light/dark setting. (Product call,
// not an oversight.)

import WidgetKit
import SwiftUI
import UIKit
import CoreLocation

func wHex(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
    Color(red: Double((hex & 0xFF0000) >> 16) / 255,
          green: Double((hex & 0x00FF00) >> 8) / 255,
          blue: Double(hex & 0x0000FF) / 255,
          opacity: alpha)
}

// ─── Palette — fixed light, soft-blue accent ──────────────────────────

// bg — widget card background, top → bottom gradient stops. White surface
// with a whisper of the app's pale-blue "ground" tint at the bottom edge.
let wBgTop    = Color.white
let wBgBottom = wHex(0xEAF3FC)
/// Flat fill for call sites that need a single Color (e.g. Live Activity's
/// `activityBackgroundTint`, which the system blurs — no gradient support
/// there). A near-white, faintly blue-tinted surface.
let wBg       = wHex(0xF2F8FD, alpha: 0.94)
/// The gradient itself, for `.containerBackground` on Home Screen widgets.
let wBgGradient = LinearGradient(colors: [wBgTop, wBgBottom],
                                 startPoint: .top, endPoint: .bottom)

// text — primary ink (matches WSSoftTheme's #1B2430).
let wFg     = wHex(0x1B2430)

// dim — secondary text (#7A8794).
let wDim    = wHex(0x7A8794)

// faint — captions / tertiary, a shade lighter than dim.
let wFaint  = wHex(0x93A0AC)

// rule — hairline borders (neutral tiles / dividers) on light surfaces.
let wLine   = Color.black.opacity(0.07)

// accent — the blue family. wAccentBlue is the primary #2E8FE0, used on
// every light surface (widget card + Live Activity lock screen). wIslandBlue
// is the lighter #5CB8F2, reserved for the Dynamic Island, which the system
// always renders on black chrome regardless of the app's own light styling.
let wAccentBlue  = wHex(0x2E8FE0)
let wIslandBlue  = wHex(0x5CB8F2)

// island text — white/light-grey pair for the Dynamic Island's non-accent
// copy (dest, stop name, footer labels), since that chrome is always dark.
let wIslandFg   = Color.white
let wIslandDim  = wHex(0xB9C6D3)

/// Lock Screen Live Activity surface. DARK on purpose, unlike the Home Screen
/// widget: the system renders Lock Screen activities in `.accented`/`.vibrant`
/// as often as `.fullColor`, and in those modes it throws our colours away and
/// re-derives everything from luminance. A near-white card has almost no
/// luminance headroom left, so every tier flattened into the background and
/// the card became unreadable (owner photographed it twice — 2026-07-25 and
/// 2026-07-26). Light copy on a dark surface keeps its separation in all
/// three modes, and it is what the Lock Screen's own widgets do.
let wLockBg  = wHex(0x121A24, alpha: 0.96)

// chip — the tinted service-number chip pair (spec tokens exactly): a pale
// blue fill with a saturated blue ink, used by WServiceBadge.
let wChipBg  = wHex(0xE4F1FC)
let wChipInk = wHex(0x1F74C0)

// amber / red — semantic-only crowd-severity colours (disruption/standing,
// severe/packed), used ONLY inside crowd dots+word — never a general accent.
let wAmber = wHex(0xE8960C)
let wCrowdRed = wHex(0xD9483B)

// ─── Fonts — SF, matching the app exactly ─────────────────────────────
//
// These used to be bundled Inter + IBM Plex Mono, left over from the earlier
// "WhereSia departure board" pass. The APP moved to SF throughout (see
// WSTheme.sans/mono — "Departly is SF throughout"), so the widget and the
// Live Activity were the last surfaces still rendering in a different
// typeface: a Departly widget sitting next to the Departly app on the same
// Home Screen was visibly not the same product (owner 2026-07-25, "widget
// font type incorrect"). Same signatures, same call sites — only the face
// changes.
//
// Deliberately NOT run through UIFontMetrics the way the in-app WSTheme
// versions are: widget layouts are fixed-size boards with no room to reflow,
// so `fixedSize` here matches the previous behaviour.

/// SF — UI text. Mirrors the app's `WSTheme.sans`.
func wSans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
}

/// SF with the monospaced design — every numeral, code and time. Mirrors the
/// app's `WSTheme.mono`: tabular figures, so a ticking ETA never shifts its
/// neighbours.
func wMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

// ─── Shared App Group (published by the app) ─────────────────────────
// Only the nearby-stop key remains: the Saved Stop and Favourite Service
// widget kinds (and their pins/favs App Group keys) were removed outright
// per the 2026-07-24 "one widget, one size" directive. The app may still
// publish `leyne.pins.shared` / `leyne.favs.shared` for its own use — that's
// app-owned state outside this extension target — but nothing here reads
// them anymore.
enum WGroup {
    static let id        = "group.com.leyne"        // must match LeyneWidgets.entitlements
    static let nearbyKey = "leyne.nearby.shared"     // [WNearbyStop]

    /// The full stop directory the app publishes (see DataStore's
    /// `mirrorStopIndexToWidget`). A file, not a defaults key — it's ~5,000
    /// records.
    static var stopIndexURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent("stopindex.json")
    }
}

private func decode<T: Decodable>(_ key: String, _ type: [T].Type) -> [T] {
    guard let d = UserDefaults(suiteName: WGroup.id)?.data(forKey: key),
          let v = try? JSONDecoder().decode([T].self, from: d)
    else { return [] }
    return v
}

// Last-known nearby stops, published by the app whenever location updates.
// The widget refetches live arrivals itself — this is just the stop list +
// walking distance, which the widget can't compute without the stop DB.
struct WNearbyStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String
    let walkMin: Int
    /// Straight-line metres. Optional ON PURPOSE: a build published by an
    /// older app version has no such key, and a non-optional field would fail
    /// the whole decode and blank the widget until the app next ran.
    var distanceM: Int? = nil
}

/// "180m" / "1.2km" — the app's `fmtDistance`, duplicated here because the
/// extension can't import the app module. Keep the two in step.
func wFmtDistance(_ m: Int) -> String {
    if m < 1000 { return "\(m)m" }
    let km = Double(m) / 1000
    return km < 10 ? String(format: "%.1fkm", km) : "\(Int(km.rounded()))km"
}
func loadNearby() -> [WNearbyStop] { decode(WGroup.nearbyKey, [WNearbyStop].self) }

// ─── Resolving the nearest stop in the EXTENSION ─────────────────────
// The app-published `loadNearby()` list is a snapshot of wherever the app
// last had a location fix. It is the fallback, not the source of truth:
// on its own it froze the widget on the stop you were at the last time you
// opened Departly (owner 2026-07-26 — "if I go to another location, the
// widget does not update itself to show the nearest bus stop").
//
// With `NSWidgetWantsLocation` in this extension's Info.plist the widget
// gets its own fix AND the system reloads the timeline by itself when you
// move a significant distance — which is precisely the missing trigger.

/// One stop in the shared directory. Mirrors `SharedStopPin` in the app;
/// the single-letter keys are the app's, kept for size.
struct WStopPin: Codable {
    let c: String, n: String
    let y: Double, x: Double
}

func loadStopIndex() -> [WStopPin] {
    guard let url = WGroup.stopIndexURL,
          let d = try? Data(contentsOf: url),
          let v = try? JSONDecoder().decode([WStopPin].self, from: d)
    else { return [] }
    return v
}

/// Metres between two coordinates. Same formula the app uses so the widget's
/// walk estimate can't disagree with the one on the stop screen.
func wHaversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    return r * 2 * atan2(sqrt(a), sqrt(1 - a))
}

/// The closest stop to `loc` in the shared directory, with walk minutes at
/// ~80 m/min — the app's rate (`DataStore.updateNearby`), so the widget and
/// the app never quote different numbers for the same stop.
func wNearestStop(to loc: CLLocation, in index: [WStopPin]) -> WNearbyStop? {
    let here = loc.coordinate
    var best: (pin: WStopPin, d: Double)?
    for p in index {
        let d = wHaversine(here.latitude, here.longitude, p.y, p.x)
        if best == nil || d < best!.d { best = (p, d) }
    }
    guard let best else { return nil }
    return WNearbyStop(id: best.pin.c, name: best.pin.n,
                       walkMin: max(1, Int((best.d / 80).rounded())),
                       distanceM: Int(best.d.rounded()))
}

/// One-shot location for a timeline pass.
///
/// Uses the containing app's authorization — the widget never prompts, and
/// `isAuthorizedForWidgetUpdates` is the documented gate for whether this
/// extension may read location at all. A cached fix under 5 minutes old is
/// used as-is; otherwise we ask for one and give up after 6s so a timeline
/// pass can never hang on a GPS that isn't coming (WidgetKit budgets these
/// tightly, and a stale-but-rendered widget beats a blank one).
final class WLocator: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WLocator()
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    /// Whether this extension may read location at all — the app's
    /// authorization, surfaced by Core Location for widget use.
    var isAuthorized: Bool { mgr.isAuthorizedForWidgetUpdates }

    /// A fix Core Location already has, if it's fresh enough to trust. Lets
    /// the snapshot path stay synchronous.
    func cachedLocation(maxAge: TimeInterval) -> CLLocation? {
        guard isAuthorized, let l = mgr.location,
              l.timestamp.timeIntervalSinceNow > -maxAge else { return nil }
        return l
    }

    private func request() async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let l = mgr.location, l.timestamp.timeIntervalSinceNow > -300 { return l }
        return await withCheckedContinuation { c in
            cont = c
            mgr.delegate = self
            mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
            mgr.requestLocation()
        }
    }

    /// `request()` bounded by a 6-second deadline.
    func current() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await self.request() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func finish(_ loc: CLLocation?) {
        guard let c = cont else { return }   // resume exactly once
        cont = nil
        c.resume(returning: loc)
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        finish(locs.last)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}

// ─── Self-contained LTA Bus Arrival v3 client ────────────────────────
// Same live source the app uses. Captures the GPS `Monitored` flag per
// arrival so the widget can be as honest about uncertainty as the app.
enum WLTA {
    static let key  = "+6zJ3XstTqOcDkvczHttWA=="
    static let base = URL(string: "https://datamall2.mytransport.sg/ltaodataservice")!

    private struct Resp: Decodable { let Services: [Svc] }
    private struct Svc: Decodable {
        let ServiceNo: String
        let NextBus: Bus
        let NextBus2: Bus
        let NextBus3: Bus
    }
    private struct Bus: Decodable {
        let EstimatedArrival: String?
        let Monitored: Int?
        // "SEA" (seats) / "SDA" (standing) / "LSD" (limited/packed). Absent
        // on some scheduled-only rows — stays nil rather than guessing.
        let Load: String?
    }

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

    struct Row: Identifiable, Hashable {
        let id: String          // service number
        let eta1: Int?
        let eta2: Int?
        let eta3: Int?
        /// First arrival is GPS-monitored (live). False = scheduled-only.
        var mon1: Bool = true
        /// Crowd level of the soonest bus, straight from LTA. nil = unknown
        /// (never guessed) — the crowd dots simply don't render.
        var load1: WLoad? = nil

        init(id: String, eta1: Int?, eta2: Int?, eta3: Int? = nil, mon1: Bool = true,
             load1: WLoad? = nil) {
            self.id = id; self.eta1 = eta1; self.eta2 = eta2; self.eta3 = eta3
            self.mon1 = mon1; self.load1 = load1
        }
    }

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
            .map { Row(id: $0.ServiceNo,
                       eta1: mins($0.NextBus.EstimatedArrival),
                       eta2: mins($0.NextBus2.EstimatedArrival),
                       eta3: mins($0.NextBus3.EstimatedArrival),
                       mon1: ($0.NextBus.Monitored ?? 1) == 1,
                       load1: WLoad(lta: $0.NextBus.Load)) }
            // Number order, matching the in-app board: rows must not
            // reshuffle between refreshes.
            .sorted { a, b in
                let na = Int(a.id.filter(\.isNumber)) ?? Int.max
                let nb = Int(b.id.filter(\.isNumber)) ?? Int.max
                if na != nb { return na < nb }
                return a.id < b.id
            }
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────
func etaLabel(_ m: Int?) -> String {
    guard let m else { return "—" }
    return m <= 0 ? "Arr" : "\(m)"
}

/// Whisper-quiet estimate tell: a single faint "~" before a scheduled-only
/// ETA. The widget reads as a confident live number (timeliness is the
/// promise); the "~" is the only quiet signal. See memory
/// `feedback_timely_over_honest`.
func schedPrefix(_ mon: Bool, _ m: Int?) -> String {
    (!mon && (m ?? 0) > 0) ? "~" : ""
}

/// Deep link the host app can route (tap-to-open). Harmless if unhandled.
func stopURL(_ code: String) -> URL? { URL(string: "lyne://stop/\(code)") }

// ─── Crowd (SEA / SDA / LSD) ───────────────────────────────────────────
// Straight from LTA's `Load` field — never inferred. Rendered as the
// ●●○ dot triplet + a one-word verdict, matching the shared design spec:
// blue = seats, amber = standing, red = packed.
enum WLoad: String {
    case seats, standing, packed

    init?(lta: String?) {
        switch lta?.uppercased() {
        case "SEA": self = .seats
        case "SDA": self = .standing
        case "LSD": self = .packed
        default: return nil
        }
    }

    var word: String {
        switch self {
        case .seats:    return "seats"
        case .standing: return "standing"
        case .packed:   return "packed"
        }
    }
    /// Dot fill colour — always the severity colour, seats included.
    var tint: Color {
        switch self {
        case .seats:    return wAccentBlue
        case .standing: return wAmber
        case .packed:   return wCrowdRed
        }
    }
    /// Word colour — spec calls out that ONLY standing/packed tint their
    /// word (amber/red); "seats" is calm news, so its word stays neutral
    /// grey even though its dot is blue.
    var wordColor: Color {
        switch self {
        case .seats:    return wFaint
        case .standing: return wAmber
        case .packed:   return wCrowdRed
        }
    }
    /// Filled dots out of 3, left→right severity.
    var filledDots: Int {
        switch self {
        case .seats: return 1
        case .standing: return 2
        case .packed: return 3
        }
    }
}

/// The "●●○ standing" crowd read. nil load renders nothing — an unknown
/// crowd level is omitted, never guessed.
struct WCrowdDots: View {
    let load: WLoad?
    var size: CGFloat = 9.5

    var body: some View {
        if let load {
            HStack(spacing: 3) {
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < load.filledDots ? load.tint : wLine)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                Text(load.word)
                    .font(wSans(size, .semibold))
                    .foregroundStyle(load.wordColor)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crowd: \(load.word)")
        }
    }
}

// ─── Card chrome ───────────────────────────────────────────────────
// The spec's outer card: radius 22, 1px rgba(255,255,255,.09) hairline,
// 16/15 padding. `.containerBackground` already paints the gradient fill
// and the system's own corner mask (we don't fight that — see file header),
// but it draws no border and applies no interior padding on its own, so
// both are added explicitly here for every Home Screen widget root view.
private let wCardRadius: CGFloat = 22
private let wCardBorder = Color.black.opacity(0.06)

extension View {
    /// Interior padding + hairline border matching the card spec. Apply
    /// AFTER content, BEFORE `.containerBackground`.
    func wCardChrome() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .overlay(RoundedRectangle(cornerRadius: wCardRadius, style: .continuous)
                .stroke(wCardBorder, lineWidth: 1))
    }
}

// ─── Shared UI atoms ─────────────────────────────────────────────────

/// Service-number chip — the spec's tinted pair: pale-blue .14-strength fill
/// off #1F74C0, matching #1F74C0 hairline + heavy numerals. Fixed styling
/// regardless of arriving state: the chip's job is identity, not status
/// (status lives in the ETA tile it sits in). Also used, unchanged, inside
/// the always-dark Dynamic Island leading region — the opacity-derived fill
/// reads as a dark-navy tag there rather than pale blue, which still holds
/// up against the system's black chrome.
struct WServiceBadge: View {
    let no: String
    var compact = false
    var body: some View {
        Text(no)
            .font(wMono(compact ? 9.5 : 10.5, .heavy))
            .foregroundStyle(wChipInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: compact ? 24 : 30, minHeight: compact ? 18 : 21)
            .background(wChipInk.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(wChipInk.opacity(0.45), lineWidth: 1))
            .widgetAccentable()
    }
}

/// One bus per LINE, not per column (owner 2026-07-26, "a lot of space
/// wasted… middle area a lot of empty space").
///
/// The previous layout gave each bus a tall narrow tile and stacked chip /
/// ETA / crowd inside it with a flexible gap above AND below the ETA. On a
/// 364×170 medium widget that tile is ~105×114pt carrying ~57pt of content,
/// so ~26pt of nothing got injected twice into every bus — and the row still
/// only showed one arrival each, discarding the `eta2`/`eta3` the timeline
/// had already fetched.
///
/// A full-width line fixes both axes at once: the card's 332pt of width
/// carries identity on the left and the answer on the right (F-scan), the
/// three lines split the available height between them so there is no dead
/// band anywhere, and the space reclaimed from the tile gutters pays for the
/// follow-on arrivals. Three lines × three numbers instead of three × one.
///
/// Columns are fixed-width and trailing-aligned on purpose: the ETAs of all
/// three buses line up vertically, so the gap between the crowd read and the
/// numbers reads as board structure rather than as emptiness.
struct WArrivalRow: View {
    let row: WLTA.Row
    let soonest: Bool

    private var arriving: Bool { etaLabel(row.eta1) == "Arr" }

    /// "then 9 · 17" — the arrivals after the hero one. Omitted entirely when
    /// LTA gives us nothing (never padded with guesses), and the unit is left
    /// to the hero's "min" so the faint column stays short.
    private var followText: String {
        let more = [row.eta2, row.eta3].compactMap { $0 }.filter { $0 > 0 }
        guard !more.isEmpty else { return "" }
        return "then " + more.prefix(2).map(String.init).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Identity, hard left, never truncated. Full-size badge (not
            // `compact`) — the spec's chip is 10.5pt.
            WServiceBadge(no: row.id)
                .frame(minWidth: 44, alignment: .leading)

            WCrowdDots(load: row.load1)
                .padding(.leading, 2)

            Spacer(minLength: 8)

            Text(followText)
                .font(wSans(10.5, .medium))
                .foregroundStyle(wFaint)
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)

            // The answer — hero ETA, hard right, same trailing column on
            // every line.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(schedPrefix(row.mon1, row.eta1) + etaLabel(row.eta1))
                    .font(wMono(arriving ? 16 : 21, .heavy))
                    .foregroundStyle(soonest ? wAccentBlue : wFg)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if !arriving {
                    Text("min").font(wSans(9.5, .medium)).foregroundStyle(wDim)
                }
            }
            .contentTransition(.numericText(countsDown: true))
            .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(soonest ? wAccentBlue.opacity(0.10) : Color.black.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(soonest ? wAccentBlue.opacity(0.30) : Color.black.opacity(0.07), lineWidth: 1))
    }
}

/// The medium-widget board: up to three `WArrivalRow`s stacked, each greedy
/// in height so they divide the card's remaining space evenly — whatever is
/// left over becomes row padding rather than one dead band.
///
/// "Soonest" is determined by the lowest `eta1`, NOT list position — the
/// caller (LeyneNearbyWidget) passes rows already sorted soonest-first, but
/// this stays index-independent on purpose so it can't accent-highlight the
/// wrong bus if that ever changes.
struct WArrivalBoard: View {
    let rows: [WLTA.Row]
    private var soonestID: String? {
        rows.min { ($0.eta1 ?? .max) < ($1.eta1 ?? .max) }?.id
    }
    var body: some View {
        let soonest = soonestID
        VStack(spacing: 6) {
            ForEach(Array(rows.prefix(3))) { row in
                WArrivalRow(row: row, soonest: row.id == soonest)
            }
        }
    }
}

/// "3 min ago" / "12 s ago" — the widget's staleness tell. Composes a plain
/// "ago" suffix onto a `Text(_:style: .relative)` fragment, so the caption
/// keeps itself honest (re-renders as time passes) without a per-second
/// refresh budget — SwiftUI ticks styled `Text` on its own schedule even
/// inside a concatenation.
struct WUpdatedCaption: View {
    let date: Date
    var body: some View {
        (Text(date, style: .relative) + Text(" ago"))
            .font(wSans(10, .medium))
            .foregroundStyle(wFaint)
            .lineLimit(1)
    }
}
