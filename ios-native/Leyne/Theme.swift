// Theme — Leyne 2.0 "Soft" tokens.
// Monochrome both ways: black-and-white dark (#0F0F0F, white accent) and
// white & black light (#F2F2F2, black accent) — clean, no brand green;
// confidence reads from opacity/shape, with amber+red kept for alerts.
// Property names are preserved from the v1 theme so call sites compile
// unchanged; only the values move to the Soft palette per specs/leyne-2.0-plan.md.

import SwiftUI
import UIKit  // UIFontMetrics — Dynamic Type scaling for sans()/mono()

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
    /// Stronger raised surface — hero cards, secondary fills.
    let surfaceHi: Color
    /// Inverse panel colour (FAB / inverted banners).
    let contrast: Color
    /// Foreground used on top of `contrast` (also on `accent`).
    let contrastFg: Color
    /// Darker companion to `contrast` (raised inside an inverse panel).
    let contrastSurface: Color
    /// Primary foreground text.
    let fg: Color
    /// Secondary text — ~60% of fg in Soft.
    let dim: Color
    /// Tertiary text — ~35% of fg.
    let faint: Color
    /// Hairline borders + dividers.
    let line: Color
    /// Stronger border.
    let lineHi: Color
    /// Brand accent + live/arriving colour (mint).
    let accent: Color
    /// Alias for `accent`.
    let live: Color
    /// Subtle background tint for live / arriving rows (Soft "accentTint").
    let liveBg: Color
    /// Warning amber.
    let warn: Color
    let warnBg: Color
    /// Critical red.
    let crit: Color
    let critBg: Color
    /// Foreground to use on `accent` fills.
    let onAccent: Color

    // ── Cross-mode signal colours ────────────────────────────────────
    /// MRT NE-line purple — used for MRT alert cards / dots.
    let mrtNE: Color = Color(hex: "9B26B6")
    /// Live "ME" location dot on maps.
    let meBlue: Color = Color(hex: "3B82F6")

    // ── Fonts ────────────────────────────────────────────────────────
    // Leyne 2.0 typography target is Inter; for now we use the system
    // face. Inter bundling tracked separately — `sans()` is the single
    // place to swap when the font asset lands.
    //
    // Sizes are run through UIFontMetrics so the whole app honours the
    // user's Dynamic Type setting — `Font.system(size:)` alone is a fixed
    // point size and ignores it. Scaling here (the single font factory)
    // cascades to every call site. `Font.system` has no `relativeTo:`
    // parameter, so we scale the value, not the Font.
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size),
                weight: weight, design: .default)
    }
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size),
                weight: weight, design: .monospaced)
    }

    // Monochrome dark — clean black-and-white, no brand green. Accent (LIVE /
    // arriving / pin) is pure white ink, mirroring the light mode's black-ink
    // accent; confidence reads from opacity/shape, not hue. Amber + red are
    // kept for disruption severity.
    static let dark = Theme(
        isDark: true,
        bg: Color(hex: "0F0F0F"),
        surface: Color(hex: "1A1A1A"),
        surfaceHi: Color(hex: "262626"),
        contrast: Color(hex: "FFFFFF"),
        contrastFg: Color(hex: "0F0F0F"),
        contrastSurface: Color(hex: "2E2E2E"),
        fg: Color(hex: "FFFFFF"),
        dim: Color(hex: "FFFFFF").opacity(0.6),
        faint: Color(hex: "FFFFFF").opacity(0.35),
        line: Color(hex: "FFFFFF").opacity(0.1),
        lineHi: Color(hex: "FFFFFF").opacity(0.16),
        accent: Color(hex: "FFFFFF"),
        live: Color(hex: "FFFFFF"),
        liveBg: Color(hex: "242424"),
        warn: Color(hex: "F4B870"),
        warnBg: Color(hex: "F4B870").opacity(0.16),
        crit: Color(hex: "F08F7C"),
        critBg: Color(hex: "F08F7C").opacity(0.16),
        onAccent: Color(hex: "111111")
    )

    // White & black light mode — mirrors the bus-view card (white surface,
    // black ink). Monochrome: the accent (LIVE / arriving / pin) is pure black
    // ink rather than the old mint green. Warning amber + critical red are kept
    // so disruptions still read at a glance. `bg` is a hair off-white so white
    // `surface` cards lift off it (some cards carry no hairline border).
    static let light = Theme(
        isDark: false,
        bg: Color(hex: "F2F2F2"),
        surface: Color(hex: "FFFFFF"),
        surfaceHi: Color(hex: "E9E9E9"),
        contrast: Color(hex: "111111"),
        contrastFg: Color(hex: "FFFFFF"),
        contrastSurface: Color(hex: "2A2A2A"),
        fg: Color(hex: "111111"),
        dim: Color(hex: "111111").opacity(0.6),
        faint: Color(hex: "111111").opacity(0.35),
        line: Color(hex: "111111").opacity(0.10),
        lineHi: Color(hex: "111111").opacity(0.16),
        accent: Color(hex: "111111"),
        live: Color(hex: "111111"),
        liveBg: Color(hex: "EDEDED"),
        warn: Color(hex: "A0631A"),
        warnBg: Color(hex: "A0631A").opacity(0.14),
        crit: Color(hex: "A4422F"),
        critBg: Color(hex: "A4422F").opacity(0.14),
        onAccent: Color(hex: "FFFFFF")
    )

    /// iOS 26 Liquid Glass surface used for the floating tab bar and
    /// glass pill buttons. On iOS 18–25 falls back to opaque `surface`.
    @ViewBuilder
    func glassSurface() -> some View {
        if #available(iOS 26.0, *) {
            ZStack {
                surface.opacity(0.4)
                Rectangle().fill(.regularMaterial)
            }
        } else {
            surface
        }
    }

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
}

/// Singapore MRT line colours. Used for line indicators in MRT alert
/// cards and (eventually) interchange annotations on Stop detail.
enum MRTLine: String, CaseIterable {
    case EW, NS, NE, CC, DT, TE

    var color: Color {
        switch self {
        case .EW: return Color(hex: "009645")
        case .NS: return Color(hex: "D42E12")
        case .NE: return Color(hex: "9B26B6")
        case .CC: return Color(hex: "FA9E0D")
        case .DT: return Color(hex: "005EC4")
        case .TE: return Color(hex: "9D5B25")
        }
    }

    var displayName: String {
        switch self {
        case .EW: return "East-West"
        case .NS: return "North-South"
        case .NE: return "North-East"
        case .CC: return "Circle"
        case .DT: return "Downtown"
        case .TE: return "Thomson-East Coast"
        }
    }

    /// Map LTA TrainServiceAlerts `Line` codes (e.g. "NEL", "EWL") to
    /// our local palette enum. Returns nil for lines we don't colour
    /// yet — callers fall back to a neutral marker so the alert still
    /// surfaces.
    static func from(ltaCode raw: String) -> MRTLine? {
        switch raw.uppercased() {
        case "EWL", "CGL", "EWN": return .EW
        case "NSL": return .NS
        case "NEL": return .NE
        case "CCL", "CEL", "CGE": return .CC
        case "DTL": return .DT
        case "TEL": return .TE
        default: return nil
        }
    }

    /// LTA's `Line` strings are airport-code style; surface a short
    /// human label ("NE Line") for headers without sounding bureaucratic.
    static func shortLabel(forLta raw: String) -> String {
        if let line = from(ltaCode: raw) { return "\(line.rawValue) Line" }
        return raw
    }
}
