// WhereSia — design tokens.
//
// A dark "departure board" system: near-black surfaces, tabular/mono numerals,
// thin single-weight line icons, no emoji. A light variant swaps the same token
// names. Ported verbatim from wheresia-handoff/DESIGN-SYSTEM.md — this file is
// the single source of truth for the WhereSia look, kept fully separate from the
// existing `Theme` so the two design languages never bleed into each other.
//
// THE ONE HARD RULE: colour = data, never chrome. The ONLY colour anywhere in
// the app is official MRT/LRT line identity (the line "bullet" tiles). Every
// other surface — backgrounds, text, buttons, bus route numbers, crowd gauges —
// is greyscale/tonal. Crowd is NEVER colour-coded: it is a neutral occupancy
// gauge (fill length) + a word. Do not reintroduce green/amber/red for crowd.

import SwiftUI
import UIKit  // UIFontMetrics — Dynamic Type scaling

struct WSTheme: Equatable {
    let isDark: Bool

    /// Screen background.
    let bg: Color
    /// Cards.
    let panel: Color
    /// Nested surfaces / pills.
    let panel2: Color
    /// Search field.
    let input: Color
    /// Primary text + gauge fill + accents.
    let text: Color
    /// Secondary text.
    let dim: Color
    /// Tertiary / disabled.
    let faint: Color
    /// Hairline borders + empty gauge track.
    let rule: Color
    /// Tab bar background.
    let tabbar: Color

    // ── DARK (default) ───────────────────────────────────────────────
    static let dark = WSTheme(
        isDark: true,
        bg:     Color(wsHex: "0F1216"),
        panel:  Color(wsHex: "161A20"),
        panel2: Color(wsHex: "1B2027"),
        input:  Color(wsHex: "181D24"),
        text:   Color(wsHex: "E8EAED"),
        dim:    Color(wsHex: "8A93A2"),
        faint:  Color(wsHex: "5A626E"),
        rule:   Color(wsHex: "242A33"),
        tabbar: Color(wsHex: "12161B")
    )

    // ── LIGHT (body.light) ───────────────────────────────────────────
    static let light = WSTheme(
        isDark: false,
        bg:     Color(wsHex: "FFFFFF"),
        panel:  Color(wsHex: "F5F6F8"),
        panel2: Color(wsHex: "EEF0F3"),
        input:  Color(wsHex: "F1F2F5"),
        text:   Color(wsHex: "14181D"),
        dim:    Color(wsHex: "6B7280"),
        faint:  Color(wsHex: "A2A8B2"),
        rule:   Color(wsHex: "E6E8EC"),
        tabbar: Color(wsHex: "FFFFFF")
    )

    static func resolve(dark: Bool) -> WSTheme { dark ? .dark : .light }

    // ── Typography ───────────────────────────────────────────────────
    // Sans (UI) = the system face. Mono (all numerals & codes) = SF Mono via
    // the `.monospaced` design, with tabular numerals — the departure-board
    // look. Both run through UIFontMetrics so the whole app honours Dynamic
    // Type (there's a "Larger text" setting), scaling the point size the way
    // the existing Theme.sans/mono do.
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size),
                weight: weight, design: .default)
    }
    /// Monospaced face for arrival minutes, stop codes, line codes, times,
    /// frequencies — anything tabular. `tabular-nums` is implicit in the
    /// monospaced design.
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size),
                weight: weight, design: .monospaced)
    }
}

// MARK: - Official line palette (the only colour in the app)

enum WSLine {
    /// Official LTA line brand colours, keyed by the 2-letter code prefix.
    /// Hexes are the WhereSia contract (DESIGN-SYSTEM.md) — a hair different
    /// from the existing app's palette, kept local so the two never diverge.
    static let colors: [String: Color] = [
        "NS": Color(wsHex: "E1251B"), // North South — red
        "EW": Color(wsHex: "009645"), // East West — green
        "CG": Color(wsHex: "009645"), // Changi Airport branch — green
        "NE": Color(wsHex: "9E28B5"), // North East — purple
        "CC": Color(wsHex: "FFAD00"), // Circle — amber
        "CE": Color(wsHex: "FFAD00"), // Circle extension — amber
        "DT": Color(wsHex: "005EC4"), // Downtown — blue
        "TE": Color(wsHex: "9D5B25"), // Thomson–East Coast — brown
    ]
    /// LRT (BP / SK / PG) + any code we don't brand individually.
    static let lrt = Color(wsHex: "748477")

    /// Brand colour for a station code like "NS22" / "TE14" / "BP1".
    static func color(forStationCode code: String) -> Color {
        let prefix = String(code.prefix(2)).uppercased()
        return colors[prefix] ?? lrt
    }

    /// Brand colour for an LTA line code like "NSL" / "EWL" / "TEL".
    static func color(forLineCode code: String) -> Color {
        let c = code.uppercased()
        for (prefix, colour) in colors where c.hasPrefix(prefix) { return colour }
        return lrt
    }

    /// White text always reads on the saturated line hexes.
    static let onLine = Color.white
}

// MARK: - Environment plumbing

private struct WSThemeKey: EnvironmentKey {
    static let defaultValue = WSTheme.dark
}

extension EnvironmentValues {
    var ws: WSTheme {
        get { self[WSThemeKey.self] }
        set { self[WSThemeKey.self] = newValue }
    }
}

// MARK: - Hex initialiser (local so WhereSia doesn't depend on Theme.swift)

extension Color {
    init(wsHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
