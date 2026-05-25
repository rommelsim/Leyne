// Theme — color tokens for the redesigned Lyne UI.
// Ported 1:1 from lib/theme.dart (Flutter v2.0): warm near-black dark
// background with a mint accent; warm off-white light background with
// a darker mint. "mono" maps to SF Mono, "sans" to the system face.

import SwiftUI

extension Color {
    /// Hex like "F7F4ED" or "#F7F4ED".
    init(hex: String) {
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

struct Theme: Equatable {
    let isDark: Bool

    /// Page background.
    let bg: Color
    /// Default raised surface (cards, list backgrounds).
    let surface: Color
    /// Stronger raised surface — the hero card on Home.
    let surfaceHi: Color
    /// Inverse panel colour (FAB, dark banners on light bg).
    let contrast: Color
    /// Foreground used on top of `contrast`.
    let contrastFg: Color
    /// Darker companion to `contrast` (raised inside an inverse panel).
    let contrastSurface: Color
    /// Primary foreground text.
    let fg: Color
    /// Secondary text — ~52% of fg.
    let dim: Color
    /// Tertiary text — ~32% of fg. Stop IDs, "then NN" follow-ups.
    let faint: Color
    /// Hairline borders + dividers.
    let line: Color
    /// Stronger border — for the hero card.
    let lineHi: Color
    /// Brand accent + the "live / arriving" colour.
    let accent: Color
    /// Live-data colour (alias for accent in this palette).
    let live: Color
    /// Subtle background tint for live / arriving rows.
    let liveBg: Color
    /// Warning amber — "leave now", "delay".
    let warn: Color
    let warnBg: Color
    /// Critical red — "last bus", "service disrupted".
    let crit: Color
    let critBg: Color

    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let dark = Theme(
        isDark: true,
        bg: Color(hex: "0E0E0A"),
        surface: Color(hex: "161612"),
        surfaceHi: Color(hex: "1D1C18"),
        contrast: Color(hex: "ECE9E0"),
        contrastFg: Color(hex: "0B0B08"),
        contrastSurface: Color(hex: "2A251F"),
        fg: Color(hex: "ECE9E0"),
        dim: Color(hex: "ECE9E0").opacity(0.52),
        faint: Color(hex: "ECE9E0").opacity(0.32),
        line: Color.white.opacity(0.07),
        lineHi: Color.white.opacity(0.14),
        accent: Color(hex: "5EE597"),
        live: Color(hex: "5EE597"),
        liveBg: Color(hex: "5EE597").opacity(0.14),
        warn: Color(hex: "E9B04B"),
        warnBg: Color(hex: "E9B04B").opacity(0.16),
        crit: Color(hex: "E96A5C"),
        critBg: Color(hex: "E96A5C").opacity(0.16)
    )

    /// Lyne's unified glass surface. On iOS 26 lifts onto the system
    /// Liquid Glass material (`.regularMaterial`) with a faint warm tint
    /// under it so the tea/parchment palette still reads through. On iOS
    /// 18–25, falls back to the opaque `surface` colour. Use this anywhere
    /// the design previously called for `t.surface` on a *raised* element:
    /// pinned cards, sheets, sticky bars, empty/error cards. Inline rows
    /// and the page background stay solid for legibility.
    @ViewBuilder
    func glassSurface() -> some View {
        if #available(iOS 26.0, *) {
            ZStack {
                // Tint sits UNDER the glass so the warm Leyne palette still
                // tints through. 0.4 is enough to recognize as "Leyne",
                // light enough to let the glass do its work.
                surface.opacity(0.4)
                Rectangle().fill(.regularMaterial)
            }
        } else {
            surface
        }
    }

    /// Same as `glassSurface()` but using the elevated `surfaceHi` tone —
    /// the hero card's surface. Use when you want a slightly stronger glass
    /// presence (a more clearly "raised" element).
    @ViewBuilder
    func glassSurfaceHi() -> some View {
        if #available(iOS 26.0, *) {
            ZStack {
                surfaceHi.opacity(0.5)
                Rectangle().fill(.regularMaterial)
            }
        } else {
            surfaceHi
        }
    }

    static let light = Theme(
        isDark: false,
        bg: Color(hex: "F7F4ED"),
        surface: Color(hex: "FFFDF7"),
        surfaceHi: Color(hex: "F1ECDE"),
        contrast: Color(hex: "1A1916"),
        contrastFg: Color(hex: "F2EFE8"),
        contrastSurface: Color(hex: "2A2925"),
        fg: Color(hex: "171612"),
        dim: Color(hex: "6D6859"),
        faint: Color(hex: "A8A192"),
        line: Color(hex: "E5E0D2"),
        lineHi: Color(hex: "D8D3C5"),
        accent: Color(hex: "2BAA67"),
        live: Color(hex: "2BAA67"),
        liveBg: Color(hex: "E3F5EA"),
        warn: Color(hex: "B58A1F"),
        warnBg: Color(hex: "F6EBC9"),
        crit: Color(hex: "C44A3A"),
        critBg: Color(hex: "F7DAD4")
    )
}
