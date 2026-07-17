// Shared foundation for the widget extension (now Live Activity only). The
// extension can't import the app module, so the palette, the fonts and the
// common UI atoms live here. Values mirror
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
