// Shared foundation for every Home Screen widget in the extension. The
// extension can't import the app module, so the palette, the fonts, the App
// Group readers, the self-contained LTA client, and the common UI atoms all
// live here once instead of being copy-pasted per widget. Values mirror
// Leyne/WhereSia/WSTheme.swift and the WhereSia components (RouteTile,
// WSLiveBadge) so a widget always reads as a quote of the app.

import WidgetKit
import SwiftUI
import UIKit
import CoreText

// ─── Palette — dynamic, mirrors WSTheme.dark / WSTheme.light ─────────
// The WhereSia departure board: near-black board surfaces + off-white ink in
// dark, white + near-black in light. Colour discipline carries over: the ONLY
// colour is the blue live/arriving accent (accentSoft) — crowd, badges and
// text stay greyscale/tonal.
func wDyn(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}

private func wHex(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255, alpha: alpha)
}

// bg — the widget card background (WSTheme.bg)
let wBg     = wDyn(light: wHex(0xFFFFFF), dark: wHex(0x0F1216))

// panel2 — nested tile fill (WSTheme.panel2; route-tile background)
let wPanel2 = wDyn(light: wHex(0xEEF0F3), dark: wHex(0x1B2027))

// text — primary ink (WSTheme.text)
let wFg     = wDyn(light: wHex(0x14181D), dark: wHex(0xE8EAED))

// dim — secondary text (WSTheme.dim)
let wDim    = wDyn(light: wHex(0x6B7280), dark: wHex(0x8A93A2))

// faint — tertiary (WSTheme.faint)
let wFaint  = wDyn(light: wHex(0xA2A8B2), dark: wHex(0x5A626E))

// rule — hairline borders (WSTheme.rule)
let wLine   = wDyn(light: wHex(0xE6E8EC), dark: wHex(0x242A33))

// accentSoft — the live/arriving blue (WSTheme.accentSoft). The disciplined
// exception to "no colour": marks LIVE data and a bus that's pulling in.
let wAccentSoft = wDyn(light: wHex(0x1F6FE0), dark: wHex(0x3B9EFF))

// accent — solid Downtown-line blue (WSTheme.accent); white text sits on it.
let wAccent = wDyn(light: wHex(0x005EC4), dark: wHex(0x005EC4))

// live — kept as a named token for arriving emphasis (now the blue accent,
// no longer ink — the app moved off monochrome-arriving on 2026-07-02).
let wLive   = wAccentSoft

// liveBg — soft blue wash behind an "arriving" row (quotes the in-app
// arriving-row highlight).
let wLiveBg = wDyn(light: wHex(0x1F6FE0, alpha: 0.10), dark: wHex(0x3B9EFF, alpha: 0.13))

// onAccent — text on a solid accent fill.
let wOnLive = Color.white

// ─── Fonts — Inter (sans) + IBM Plex Mono (numerals), bundled ────────
// The TTFs ship in the extension (LeyneWidgets/Fonts + UIAppFonts in the
// widget Info.plist). The CTFontManager call is a belt-and-braces fallback —
// registration is idempotent and safe if UIAppFonts already loaded them.
private let wFontsReady: Bool = {
    for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
                 "Inter-ExtraBold", "IBMPlexMono-Regular", "IBMPlexMono-Medium",
                 "IBMPlexMono-SemiBold", "IBMPlexMono-Bold"] {
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    return true
}()

/// Inter — UI text. Same weight → PostScript-face mapping as in-app WSFont.
func wSans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    _ = wFontsReady
    let name: String
    if weight == .medium { name = "Inter-Medium" }
    else if weight == .semibold { name = "Inter-SemiBold" }
    else if weight == .bold { name = "Inter-Bold" }
    else if weight == .heavy || weight == .black { name = "Inter-ExtraBold" }
    else { name = "Inter-Regular" }
    return .custom(name, fixedSize: size)
}

/// IBM Plex Mono — every numeral, code and time (tabular figures, so a
/// ticking ETA never shifts its neighbours).
func wMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    _ = wFontsReady
    let name: String
    if weight == .medium { name = "IBMPlexMono-Medium" }
    else if weight == .semibold { name = "IBMPlexMono-SemiBold" }
    else if weight == .bold || weight == .heavy || weight == .black { name = "IBMPlexMono-Bold" }
    else { name = "IBMPlexMono-Regular" }
    return .custom(name, fixedSize: size)
}

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

/// Deep links the host app can route (tap-to-open). Harmless if unhandled.
func stopURL(_ code: String) -> URL? { URL(string: "lyne://stop/\(code)") }
func serviceURL(_ no: String, stop: String) -> URL? {
    URL(string: "lyne://service/\(no)?stop=\(stop)")
}

// ─── Shared UI atoms ─────────────────────────────────────────────────

/// Route tile — the widget counterpart of in-app RouteTile: mono numerals on
/// a panel2 fill with a hairline, NEVER coloured (colour is reserved for the
/// live accent + MRT lines). Width adapts to fit "21A" etc.
struct WServiceBadge: View {
    let no: String
    var compact = false
    var body: some View {
        Text(no)
            .font(wMono(compact ? 12 : 14, .bold))
            .foregroundStyle(wFg)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: compact ? 26 : 32, minHeight: compact ? 21 : 26)
            .background(wPanel2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(wLine, lineWidth: 1))
            .widgetAccentable()
    }
}

/// The unmistakable liveness mark — quotes in-app WSLiveBadge (blue dot +
/// the word LIVE). Static here: widget snapshots don't animate, so the word
/// carries the meaning on its own.
struct WLiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(wAccentSoft).frame(width: 5, height: 5)
            Text("LIVE").font(wMono(8.5, .bold)).kerning(1.0)
                .foregroundStyle(wAccentSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live data")
        .widgetAccentable()
    }
}

/// The "2 / 18 / 35 min" arrival triple: a hero ETA plus up to two thin
/// follow-up columns. "Arriving" emphasis is the blue live accent + bold,
/// matching the in-app board. Plex Mono keeps digit widths stable as the
/// countdown ticks.
struct WEtaColumns: View {
    let row: WLTA.Row
    var heroSize: CGFloat = 22
    private var arriving: Bool { row.mon1 && (row.eta1 ?? 99) <= 1 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(schedPrefix(row.mon1, row.eta1) + etaLabel(row.eta1))
                    .font(wMono(etaLabel(row.eta1) == "Arr" ? heroSize * 0.78 : heroSize,
                                arriving ? .bold : .medium))
                    .foregroundStyle(arriving ? wAccentSoft : wFg)
                    .widgetAccentable(arriving)
                if etaLabel(row.eta1) != "Arr" {
                    Text("min").font(wMono(9)).foregroundStyle(wDim)
                }
            }
            .contentTransition(.numericText(countsDown: true))

            ForEach(Array([row.eta2, row.eta3].compactMap { $0 }.prefix(2).enumerated()),
                    id: \.offset) { _, m in
                Text(m <= 0 ? "Arr" : "\(m)")
                    .font(wMono(12))
                    .foregroundStyle(wFaint)
            }
        }
    }
}
