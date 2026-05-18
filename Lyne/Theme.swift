// Theme — color tokens ported 1:1 from the design's THEMES object (app.jsx).
// Light and dark palettes. "mono" maps to a monospaced system face (SF Mono),
// "sans" to the system face (SF Pro) — the design used JetBrains Mono + SF.

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
    let bg: Color
    let surface: Color
    let contrast: Color
    let contrastFg: Color
    let contrastSurface: Color
    let fg: Color
    let dim: Color
    let line: Color
    let accent: Color
    let live: Color
    let liveBg: Color
    let warn: Color
    let crit: Color

    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let light = Theme(
        isDark: false,
        bg: Color(hex: "F7F4ED"),
        surface: Color(hex: "FFFDF7"),
        contrast: Color(hex: "1A1916"),
        contrastFg: Color(hex: "F2EFE8"),
        contrastSurface: Color(hex: "2A2925"),
        fg: Color(hex: "171612"),
        dim: Color(hex: "807A6E"),
        line: Color(hex: "E5E0D2"),
        accent: Color(hex: "8B5A2B"),
        live: Color(hex: "3C8A4E"),
        liveBg: Color(hex: "EEF5EF"),
        warn: Color(hex: "B58A1F"),
        crit: Color(hex: "C44A3A")
    )

    static let dark = Theme(
        isDark: true,
        bg: Color(hex: "15140F"),
        surface: Color(hex: "1F1D17"),
        contrast: Color(hex: "F2EFE8"),
        contrastFg: Color(hex: "15140F"),
        contrastSurface: Color(hex: "E5E0D2"),
        fg: Color(hex: "F2EFE8"),
        dim: Color(hex: "8A8478"),
        line: Color(hex: "2A2820"),
        accent: Color(hex: "D9A86C"),
        live: Color(hex: "5BC07A"),
        liveBg: Color(hex: "1B2A1F"),
        warn: Color(hex: "D9B466"),
        crit: Color(hex: "E07A6A")
    )
}
