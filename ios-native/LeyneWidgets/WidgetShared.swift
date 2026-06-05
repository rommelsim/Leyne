// Shared foundation for every Home Screen widget in the extension. The
// extension can't import the app module, so the palette, the App Group
// readers, the self-contained LTA client, and the common UI atoms all live
// here once instead of being copy-pasted per widget. Values mirror
// Leyne/Theme.swift and the in-app V2 components (ServiceBadge, ArrivingPill)
// so a widget always reads as a quote of the app.

import WidgetKit
import SwiftUI
import UIKit

// ─── Palette — dynamic, mirrors Theme.light / Theme.dark ─────────────
// dim/faint alphas are nudged up vs the app (0.60 / 0.45) for legibility at
// widget scale on unpredictable wallpapers; liveBg is the solid Soft fill.
func wDyn(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}
let wBg      = wDyn(light: UIColor(red: 0xF4/255, green: 0xEF/255, blue: 0xE7/255, alpha: 1),
                    dark:  UIColor(red: 0x15/255, green: 0x20/255, blue: 0x1C/255, alpha: 1))
let wFg      = wDyn(light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 1),
                    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 1))
let wDim     = wDyn(light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 0.60),
                    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 0.60))
let wFaint   = wDyn(light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 0.45),
                    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 0.45))
let wLine    = wDyn(light: UIColor(red: 0x1A/255, green: 0x20/255, blue: 0x1D/255, alpha: 0.10),
                    dark:  UIColor(red: 0xF1/255, green: 0xED/255, blue: 0xE7/255, alpha: 0.08))
let wLive    = wDyn(light: UIColor(red: 0x2D/255, green: 0x7A/255, blue: 0x5A/255, alpha: 1),
                    dark:  UIColor(red: 0x8E/255, green: 0xE6/255, blue: 0xC0/255, alpha: 1))
let wLiveBg  = wDyn(light: UIColor(red: 0xE8/255, green: 0xF5/255, blue: 0xEE/255, alpha: 1),
                    dark:  UIColor(red: 0x0F/255, green: 0x2A/255, blue: 0x20/255, alpha: 1))
// On-accent text for the filled service badge (light text on the mint fill).
let wOnLive  = wDyn(light: UIColor(red: 0xF7/255, green: 0xFC/255, blue: 0xF9/255, alpha: 1),
                    dark:  UIColor(red: 0x0C/255, green: 0x17/255, blue: 0x12/255, alpha: 1))

// ─── Shared App Group (published by the app) ─────────────────────────
enum WGroup {
    static let id       = "group.com.leyne"        // must match LeyneWidgets.entitlements
    static let pinsKey  = "leyne.pins.shared"      // [WPinnedStop]
    static let nearbyKey = "leyne.nearby.shared"   // [WNearbyStop]
    static let favsKey  = "leyne.favs.shared"      // [WFavService]
}

private func decode<T: Decodable>(_ key: String, _ type: [T].Type) -> [T] {
    guard let d = UserDefaults(suiteName: WGroup.id)?.data(forKey: key),
          let v = try? JSONDecoder().decode([T].self, from: d)
    else { return [] }
    return v
}

// Pinned stops the user can point the Stop widget at.
struct WPinnedStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String    // nickname OR resolved stop name (set by the app)
}
func loadPinnedStops() -> [WPinnedStop] { decode(WGroup.pinsKey, [WPinnedStop].self) }

// Last-known nearby stops, published by the app whenever location updates.
// The widget refetches live arrivals itself — this is just the stop list +
// walking distance, which the widget can't compute without the stop DB.
struct WNearbyStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String
    let walkMin: Int
}
func loadNearby() -> [WNearbyStop] { decode(WGroup.nearbyKey, [WNearbyStop].self) }

// A favourited service, pre-resolved app-side to a concrete stop + the
// route's destination (neither is resolvable inside the extension, which
// has no stop/route database).
struct WFavService: Codable, Identifiable, Hashable {
    let no: String          // service number, e.g. "186"
    let stopCode: String
    let stopName: String
    let dest: String        // "St. Michael's Ter" ("" when route unknown)
    var id: String { "\(no)#\(stopCode)" }
}
func loadFavs() -> [WFavService] { decode(WGroup.favsKey, [WFavService].self) }

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
    private struct Bus: Decodable { let EstimatedArrival: String?; let Monitored: Int? }

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

        init(id: String, eta1: Int?, eta2: Int?, eta3: Int? = nil, mon1: Bool = true) {
            self.id = id; self.eta1 = eta1; self.eta2 = eta2; self.eta3 = eta3; self.mon1 = mon1
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
                       mon1: ($0.NextBus.Monitored ?? 1) == 1) }
            .sorted { ($0.eta1 ?? 999) < ($1.eta1 ?? 999) }
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

/// Deep links the host app can route (tap-to-open). Harmless if unhandled.
func stopURL(_ code: String) -> URL? { URL(string: "lyne://stop/\(code)") }
func serviceURL(_ no: String, stop: String) -> URL? {
    URL(string: "lyne://service/\(no)?stop=\(stop)")
}

// ─── Shared UI atoms ─────────────────────────────────────────────────

/// Mint-filled service-number badge — the widget counterpart of in-app
/// V2/ServiceBadge. Width adapts to fit "21A" etc.
struct WServiceBadge: View {
    let no: String
    var compact = false
    var body: some View {
        Text(no)
            .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
            .foregroundStyle(wOnLive)
            .padding(.horizontal, compact ? 5 : 7)
            .frame(minWidth: compact ? 26 : 32, minHeight: compact ? 20 : 24)
            .background(wLive, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .widgetAccentable()
    }
}

/// The "2 / 18 / 35 min" arrival triple from the mockup: a hero ETA plus up
/// to two thin follow-up columns. `arriving` tints the hero mint.
struct WEtaColumns: View {
    let row: WLTA.Row
    var heroSize: CGFloat = 22
    private var arriving: Bool { row.mon1 && (row.eta1 ?? 99) <= 1 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(schedPrefix(row.mon1, row.eta1) + etaLabel(row.eta1))
                    .font(.system(size: etaLabel(row.eta1) == "Arr" ? heroSize * 0.78 : heroSize,
                                  weight: .medium, design: .monospaced))
                    .foregroundStyle(arriving ? wLive : wFg)
                    .widgetAccentable(arriving)
                if etaLabel(row.eta1) != "Arr" {
                    Text("min").font(.system(size: 9)).foregroundStyle(wDim)
                }
            }
            .contentTransition(.numericText(countsDown: true))

            ForEach(Array([row.eta2, row.eta3].compactMap { $0 }.prefix(2).enumerated()),
                    id: \.offset) { _, m in
                Text(m <= 0 ? "Arr" : "\(m)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(wFaint)
            }
        }
    }
}
