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
    /// Blue accent — a deliberate, disciplined exception to "colour = data".
    /// Used ONLY for accent bars, the live dot/ping, and in-content selected
    /// states. Solid, saturated (Downtown-line blue) — white text sits on it.
    let accent: Color
    /// Brighter blue tint for thin marks / text / dots on a surface where the
    /// solid `accent` would read too dark (the near-black board especially).
    let accentSoft: Color

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
        tabbar: Color(wsHex: "12161B"),
        accent:     Color(wsHex: "005EC4"),
        accentSoft: Color(wsHex: "3B9EFF")
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
        tabbar: Color(wsHex: "FFFFFF"),
        accent:     Color(wsHex: "005EC4"),
        accentSoft: Color(wsHex: "1F6FE0")
    )

    static func resolve(dark: Bool) -> WSTheme { dark ? .dark : .light }

    // ── Typography ───────────────────────────────────────────────────
    // Sans (UI) = Inter. Mono (all numerals & codes) = IBM Plex Mono — a real
    // typewriter/board mono with tabular numerals, the departure-board look.
    // Both are bundled (see UIAppFonts) and picked by explicit PostScript name
    // per weight (SwiftUI's Font.Weight doesn't drive a custom family). Sizes
    // still run through UIFontMetrics so the whole app honours Dynamic Type
    // (the "Larger text" setting) exactly as the old system faces did.
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(WSFont.inter(weight),
                fixedSize: UIFontMetrics.default.scaledValue(for: size))
    }
    /// Monospaced face for arrival minutes, stop codes, line codes, times,
    /// frequencies — anything tabular. IBM Plex Mono's figures are tabular.
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(WSFont.plexMono(weight),
                fixedSize: UIFontMetrics.default.scaledValue(for: size))
    }
}

// MARK: - Bundled font faces (PostScript names, mapped from Font.Weight)

/// Font.Weight is a struct of static members, not an enum, so a custom family
/// can't be driven by `.weight()` — each weight maps to a specific bundled
/// face. Names verified against the shipped .ttf name tables.
enum WSFont {
    static func inter(_ w: Font.Weight) -> String {
        if w == .medium   { return "Inter-Medium" }
        if w == .semibold { return "Inter-SemiBold" }
        if w == .bold     { return "Inter-Bold" }
        if w == .heavy || w == .black { return "Inter-ExtraBold" }
        return "Inter-Regular"   // ultraLight…regular collapse to Regular
    }
    static func plexMono(_ w: Font.Weight) -> String {
        if w == .medium   { return "IBMPlexMono-Medium" }
        if w == .semibold { return "IBMPlexMono-SemiBold" }
        if w == .bold || w == .heavy || w == .black { return "IBMPlexMono-Bold" }
        return "IBMPlexMono-Regular"
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

// MARK: - Liquid Glass chrome (iOS 26 real glass · material fallback ≤ iOS 25)
//
// WhereSia's own glass helper — deliberately separate from Theme.glassSurface()
// (Theme.swift), which only ever fakes glass with `.regularMaterial`. Here we
// opt into real system Liquid Glass on iOS 26 via `glassEffect()`, tinted
// toward the theme's own neutral board surface (never the blue accent, never
// an MRT line colour) so the chrome reads as WhereSia rather than generic
// system grey. Below iOS 26 it falls back to `.ultraThinMaterial` layered
// over the same tint. Chrome only — content panels stay the flat `panel` /
// `panel2` surfaces; this never touches "colour = data".
private struct WSGlassChrome: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    @Environment(\.ws) private var ws

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(tint.opacity(0.5)), in: shape)
            } else {
                content
                    .background {
                        ZStack {
                            tint.opacity(0.55)
                            Rectangle().fill(.ultraThinMaterial)
                        }
                    }
                    .clipShape(shape)
            }
        }
        .overlay(shape.stroke(ws.rule, lineWidth: 1))
    }
}

extension View {
    /// Floating glass chrome for bars/surfaces (tab bar today). Real Liquid
    /// Glass on iOS 26, `.ultraThinMaterial` fallback on 18–25 — both tinted
    /// so the surface still reads as the WhereSia board in either theme.
    func wsGlassChrome(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(WSGlassChrome(cornerRadius: cornerRadius, tint: tint))
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
