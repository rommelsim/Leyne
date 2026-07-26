// WhereSia — design tokens.
//
// "Departly green-dark" system (design-greendark branch, imported from the
// owner's Claude Design project "Departly App"): a near-black blue-grey
// gradient board with ONE live-data accent — mint (#35E0B2) — used for the
// soonest ETA, live dots, glow edges and selected states. Amber is reserved
// for real disruptions (delays, lift maintenance, offline), red for "packed"
// crowd and destructive actions, official line colours for rail identity.
// Cards are soft white-alpha gradients with hairline strokes and deep
// shadows; numerals are tabular SF.
//
// This supersedes the previous "colour = data, blue accent" monochrome rule.
// Token NAMES are kept so every WhereSia screen re-skins by value.

import SwiftUI
import UIKit  // UIFontMetrics — Dynamic Type scaling

struct WSTheme: Equatable {
    let isDark: Bool

    /// Screen background (bottom of the gradient — use wsBackground() for the full wash).
    let bg: Color
    /// Cards.
    let panel: Color
    /// Nested surfaces / pills.
    let panel2: Color
    /// Search field.
    let input: Color
    /// Primary text.
    let text: Color
    /// Secondary text.
    let dim: Color
    /// Tertiary / disabled.
    let faint: Color
    /// Hairline borders + empty gauge track.
    let rule: Color
    /// Tab bar background.
    let tabbar: Color
    /// Mint accent — the single "live data" colour. Dark ink text sits on it
    /// (`accentInk`), never white.
    let accent: Color
    /// Brighter mint for thin marks / text / dots on dark surfaces.
    let accentSoft: Color

    // ── Departly status colours (same in both variants) ─────────────
    /// Deep mint for gradient starts / pressed states.
    static let mintDeep  = Color(wsHex: "2BBD96")
    /// Text/icons ON a mint fill.
    static let accentInk = Color(wsHex: "06251D")
    /// Disruptions: delays, maintenance, offline. The design's #FFB454 is
    /// tuned for near-black; on paper it washes out, so light mode resolves
    /// to a burnt amber (dynamic — tracks the system appearance like the
    /// rest of the theme).
    static let amber     = Color(wsHexDark: "FFB454", light: "C07A1B")
    /// Title/body text inside amber banners.
    static let amberText = Color(wsHexDark: "E8C896", light: "8F5B1D")
    /// Packed crowd · destructive.
    static let red       = Color(wsHex: "FF7B6B")
    /// Favourite star.
    static let gold      = Color(wsHex: "FFD666")

    // ── DARK (default) ───────────────────────────────────────────────
    static let dark = WSTheme(
        isDark: true,
        bg:     Color(wsHex: "0A0C0F"),
        panel:  Color(wsHex: "14181E"),
        panel2: Color(wsHex: "1B2027"),
        input:  Color(wsHex: "181D24"),
        text:   Color(wsHex: "F2F4F6"),
        dim:    Color(wsHex: "8B929C"),
        faint:  Color(wsHex: "6B727C"),
        rule:   Color.white.opacity(0.08),
        tabbar: Color(wsHex: "171B21"),
        accent:     Color(wsHex: "35E0B2"),
        accentSoft: Color(wsHex: "35E0B2")
    )

    // ── LIGHT — same architecture, ink-on-paper with the mint accent ─
    static let light = WSTheme(
        isDark: false,
        bg:     Color(wsHex: "F4F6F8"),
        panel:  Color(wsHex: "FFFFFF"),
        panel2: Color(wsHex: "EEF1F4"),
        input:  Color(wsHex: "ECEFF2"),
        text:   Color(wsHex: "14181D"),
        dim:    Color(wsHex: "6B7280"),
        faint:  Color(wsHex: "A2A8B2"),
        rule:   Color.black.opacity(0.08),
        tabbar: Color(wsHex: "FFFFFF"),
        accent:     Color(wsHex: "0E9E7B"),   // darkened mint for light bg contrast
        accentSoft: Color(wsHex: "0E9E7B")
    )

    static func resolve(dark: Bool) -> WSTheme { dark ? .dark : .light }

    /// Full-screen background wash: #101318 → #0A0C0F top-to-bottom.
    func background() -> LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(wsHex: "101318"), Color(wsHex: "0A0C0F")],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(wsHex: "F7F9FA"), Color(wsHex: "EFF2F5")],
                             startPoint: .top, endPoint: .bottom)
    }

    /// Soft top-lit card fill (design: 170° white .05 → .02).
    func cardFill(_ hi: Double = 0.05, _ lo: Double = 0.02) -> LinearGradient {
        isDark
            ? LinearGradient(colors: [.white.opacity(hi), .white.opacity(lo)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.white, .white.opacity(0.85)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Mint CTA gradient ("Turn on Location", "Set alert").
    var mintGradient: LinearGradient {
        LinearGradient(colors: [Self.mintDeep, accent], startPoint: .leading, endPoint: .trailing)
    }

    // ── Typography ───────────────────────────────────────────────────
    // Departly is SF throughout (-apple-system in the design). Numerals and
    // codes use SF with tabular figures so countdowns don't jitter. Sizes run
    // through UIFontMetrics so Dynamic Type is honoured.
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight)
    }
    /// Tabular-figure face for arrival minutes, stop codes, times. Stop codes
    /// keep the monospaced design (`ui-monospace` in the design file).
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size),
                weight: weight, design: .monospaced)
    }
}

// MARK: - Official line palette

enum WSLine {
    /// Line brand colours as specced in the Departly design file, keyed by the
    /// 2-letter code prefix.
    static let colors: [String: Color] = [
        "NS": Color(wsHex: "D42E12"), // North South — red
        "EW": Color(wsHex: "009645"), // East West — green
        "CG": Color(wsHex: "009645"), // Changi Airport branch — green
        "NE": Color(wsHex: "9900AA"), // North East — purple
        "CC": Color(wsHex: "FA9E0D"), // Circle — amber
        "CE": Color(wsHex: "FA9E0D"), // Circle extension — amber
        "DT": Color(wsHex: "0055B8"), // Downtown — blue
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

// MARK: - Departly card chrome + glow

/// Standard Departly card: gradient fill, hairline stroke, deep soft shadow,
/// inner top highlight. `emphasized` = the hero cards (brighter fill, bigger
/// shadow).
private struct WSCardChrome: ViewModifier {
    var radius: CGFloat
    var emphasized: Bool
    @Environment(\.ws) private var ws

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(ws.cardFill(emphasized ? 0.07 : 0.05, emphasized ? 0.03 : 0.02))
            .overlay(alignment: .top) {   // inset 0 1px 0 white highlight
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(ws.isDark ? (emphasized ? 0.10 : 0.07) : 0),
                                            .clear],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .overlay(shape.strokeBorder(ws.rule.opacity(emphasized ? 1.25 : 1), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(ws.isDark ? (emphasized ? 0.45 : 0.35) : 0.10),
                    radius: emphasized ? 20 : 14, y: emphasized ? 16 : 10)
    }
}

extension View {
    /// Departly list/detail card chrome.
    func wsCard(radius: CGFloat = 18, emphasized: Bool = false) -> some View {
        modifier(WSCardChrome(radius: radius, emphasized: emphasized))
    }
}

/// The glowing hairline along a card's top edge — mint for "live", amber for
/// disruptions, or a line colour on MRT cards. `breathing` pulses it (bus ≤1 min).
struct WSGlowEdge: View {
    var color: Color
    var breathing: Bool = false
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LinearGradient(colors: [.clear, color, .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 2)
            .shadow(color: color.opacity(0.6), radius: 7)
            .padding(.horizontal, 20)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard breathing, !reduceMotion else { return }
                withAnimation(SoftMotion.breathe) { dimmed = true }
            }
            .onChange(of: breathing) { _, on in
                if on, !reduceMotion {
                    withAnimation(SoftMotion.breathe) { dimmed = true }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dimmed = false }
                }
            }
    }
}

/// Small pulsing status dot (mint live · amber disruption).
struct WSPulseDot: View {
    var color: Color
    var size: CGFloat = 7
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.75), radius: 5)
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(SoftMotion.breathe) { dimmed = true }
            }
    }
}

/// Mint-outlined service-number tile ("14", "65") — the Departly bus mark.
struct WSServiceTile: View {
    var no: String
    var size: CGFloat = 13          // font size; pads scale with it
    var filledStyle: Bool = true    // mint-tinted (list) vs neutral (hero)
    @Environment(\.ws) private var ws

    var body: some View {
        Text(no)
            .font(ws.sans(size, weight: .heavy))
            .foregroundStyle(filledStyle ? ws.accent : ws.text)
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.3)
            .frame(minWidth: size * 2.6)
            .background(filledStyle ? ws.accent.opacity(0.12) : ws.panel2.opacity(0.7))
            .overlay(RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                .strokeBorder(filledStyle ? ws.accent.opacity(0.4) : ws.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
    }
}

/// "STOP · 09022" bordered code chip.
struct WSStopCodeChip: View {
    var code: String
    var compact: Bool = false
    @Environment(\.ws) private var ws

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Text("STOP")
                .font(ws.sans(compact ? 8 : 8.5, weight: .bold)).kerning(0.8)
                .foregroundStyle(ws.faint)
            Text(code)
                .font(ws.mono(compact ? 10.5 : 11.5, weight: .semibold)).kerning(0.5)
                .foregroundStyle(ws.isDark ? Color(wsHex: "CFD4DA") : ws.text)
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 6)
            .strokeBorder(ws.isDark ? Color.white.opacity(0.14) : ws.rule, lineWidth: 1))
    }
}

/// Big mint countdown numeral with glow + rolling-digit transitions.
/// `sec` drives styling: ≤60 s breathes.
struct WSBigETA: View {
    var text: String
    var size: CGFloat = 38
    var glow: Bool = true
    @Environment(\.ws) private var ws

    var body: some View {
        Text(text)
            .font(ws.sans(size, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(ws.accent)
            .contentTransition(.numericText(countsDown: true))
            .shadow(color: glow ? ws.accent.opacity(0.5) : .clear, radius: 12)
    }
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
// Chrome only (tab bar, floating pills) — content cards use `wsCard`.
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
    /// Floating glass chrome for bars/surfaces. Real Liquid Glass on iOS 26,
    /// `.ultraThinMaterial` fallback on 18–25.
    func wsGlassChrome(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(WSGlassChrome(cornerRadius: cornerRadius, tint: tint))
    }

    /// UNTINTED native system glass (owner call for the search bar + tab bar):
    /// pure `glassEffect(.regular)` on iOS 26 so it looks exactly like system
    /// chrome; `.ultraThinMaterial` + hairline fallback on 18–25.
    @ViewBuilder
    func wsNativeGlass(cornerRadius: CGFloat = 999) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
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

    /// Trait-resolved pair for static tokens that must adapt (WSTheme's
    /// `amber`/`amberText` are statics, not per-variant fields, so they can't
    /// go through `resolve(dark:)`).
    init(wsHexDark dark: String, light: String) {
        self.init(UIColor { trait in
            UIColor(Color(wsHex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
