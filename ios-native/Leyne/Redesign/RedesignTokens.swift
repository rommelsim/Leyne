// Design tokens for the SG Transit redesign (Material 3 Expressive), ported to
// SwiftUI. Mirrors the Flutter implementation's RdTokens: the light/dark surface
// ramp, the primary / bus / mrt / amber roles, the eight Material You colour
// seeds, and the "premium" monochrome override.
//
// Reuses the project's `Color(hex:)` initialiser (Theme.swift). Typography uses
// the native system font (SF Pro) — the iOS-native counterpart to Hanken
// Grotesk on Android — via `rdFont`.

import SwiftUI
import UIKit

/// Hex → Color, local to the redesign module (avoids colliding with SwiftUI's
/// `Color(_:)` asset initialiser during single-file indexing).
func rdHex(_ hex: String) -> Color {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return Color(.sRGB,
                 red: Double((v & 0xFF0000) >> 16) / 255,
                 green: Double((v & 0x00FF00) >> 8) / 255,
                 blue: Double(v & 0x0000FF) / 255,
                 opacity: 1)
}

/// System font helper. CSS weights map onto `Font.Weight`. The point size is
/// run through `UIFontMetrics` so every redesign label honours the user's
/// Dynamic Type setting — clamped to 1.3× so the dense fixed-size badges and
/// timeline rows stay intact at the largest accessibility sizes.
func rdFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let scaled = min(UIFontMetrics.default.scaledValue(for: size), size * 1.3)
    return .system(size: scaled, weight: weight)
}

/// One selectable Material You colour seed.
struct RDSeed: Identifiable {
    let key: String
    let name: String
    let dot: Color
    /// `[primary, onPrimary, primaryContainer, onPrimaryContainer]` (nil = base).
    let light: [Color]?
    let dark: [Color]?
    var id: String { key }
}

private func seedSet(_ hexes: [String]?) -> [Color]? {
    hexes?.map { rdHex($0) }
}

let kRDSeeds: [RDSeed] = [
    RDSeed(key: "blue", name: "Default", dot: rdHex("1F66E0"), light: nil, dark: nil),
    RDSeed(key: "violet", name: "Teal", dot: rdHex("0F8A8A"),
           light: seedSet(["0F8A8A", "FFFFFF", "A8F2EE", "00201F"]),
           dark: seedSet(["54D9D2", "003735", "00504D", "A8F2EE"])),
    RDSeed(key: "green", name: "Cyan", dot: rdHex("0B7EA0"),
           light: seedSet(["0B7EA0", "FFFFFF", "B5EAFF", "001F2A"]),
           dark: seedSet(["5BD2F8", "00344A", "004C63", "B5EAFF"])),
    RDSeed(key: "coral", name: "Fuchsia", dot: rdHex("B5179E"),
           light: seedSet(["B5179E", "FFFFFF", "FFD7F0", "3D0036"]),
           dark: seedSet(["FFA9E4", "5E0052", "820072", "FFD7F0"])),
    RDSeed(key: "teal", name: "Rose", dot: rdHex("C2185B"),
           light: seedSet(["C2185B", "FFFFFF", "FFD9E1", "400014"]),
           dark: seedSet(["FFB1C5", "65002A", "8E0040", "FFD9E1"])),
    RDSeed(key: "rose", name: "Slate", dot: rdHex("475569"),
           light: seedSet(["475569", "FFFFFF", "D8E2F0", "0A1B2E"]),
           dark: seedSet(["AEC3DE", "1A2A3D", "33455A", "D8E2F0"])),
    RDSeed(key: "amber", name: "Plum", dot: rdHex("7A1FA2"),
           light: seedSet(["7A1FA2", "FFFFFF", "F2D9FF", "2C0043"]),
           dark: seedSet(["E3B0FF", "4A0068", "621A82", "F2D9FF"])),
    RDSeed(key: "indigo", name: "Sand", dot: rdHex("7A6A3A"),
           light: seedSet(["7A6A3A", "FFFFFF", "FFEFC2", "261A00"]),
           dark: seedSet(["E8CE8E", "3F2E00", "5B4A1F", "FFEFC2"])),
]

/// Resolved colour roles for one theme / seed / premium configuration.
struct RDTokens {
    var dark: Bool
    var page, page2: Color
    var surface, sc, scLow, scHigh, scHighest: Color
    var onSurface, onVariant, outline, outlineVariant: Color
    var primary, onPrimary, primaryContainer, onPrimaryContainer: Color
    var bus, busContainer, onBusContainer: Color
    var mrt, mrtContainer, onMrtContainer: Color
    var amber, amberContainer, onAmberContainer: Color

    /// Fixed amber/orange for MRT-transfer affordances (independent of role).
    var transferOrange: Color { rdHex("FA9E0D") }
    var transferOnOrange: Color { rdHex("3A2500") }

    static func resolve(dark: Bool, seed: String, premium: Bool) -> RDTokens {
        var t = dark ? darkBase : lightBase

        if premium {
            t.surface = rdHex("FFFFFF")
            t.sc = rdHex("EFEFF2")
            t.scLow = rdHex("F5F5F7")
            t.scHigh = rdHex("ECECEF")
            t.scHighest = rdHex("E5E5EA")
            t.onSurface = rdHex("1C1C1E")
            t.onVariant = rdHex("6E6E73")
            t.outline = rdHex("A6A6AD")
            t.outlineVariant = rdHex("E5E5EA")
            t.page = rdHex("F5F5F7")
            t.page2 = rdHex("FFFFFF")
            t.primary = rdHex("1C1C1E")
            t.onPrimary = rdHex("FFFFFF")
            t.primaryContainer = rdHex("F0F0F2")
            t.onPrimaryContainer = rdHex("1C1C1E")
            return t
        }

        let s = kRDSeeds.first { $0.key == seed } ?? kRDSeeds[0]
        if let set = dark ? s.dark : s.light {
            t.primary = set[0]
            t.onPrimary = set[1]
            t.primaryContainer = set[2]
            t.onPrimaryContainer = set[3]
        }
        return t
    }

    static let lightBase = RDTokens(
        dark: false,
        page: rdHex("E6E9ED"), page2: rdHex("EFF1F4"),
        surface: rdHex("FFFFFF"), sc: rdHex("EFF2F6"),
        scLow: rdHex("F5F7FA"), scHigh: rdHex("E8ECF1"), scHighest: rdHex("DFE4EC"),
        onSurface: rdHex("14161A"), onVariant: rdHex("4A515B"),
        outline: rdHex("79808B"), outlineVariant: rdHex("D5DAE1"),
        primary: rdHex("1F66E0"), onPrimary: rdHex("FFFFFF"),
        primaryContainer: rdHex("D9E6FF"), onPrimaryContainer: rdHex("0A2C66"),
        bus: rdHex("1F8A4C"), busContainer: rdHex("DCEFE0"), onBusContainer: rdHex("0A3D20"),
        mrt: rdHex("D23B2C"), mrtContainer: rdHex("FBE2DD"), onMrtContainer: rdHex("551812"),
        amber: rdHex("B0670C"), amberContainer: rdHex("FCE6C8"), onAmberContainer: rdHex("3A2500")
    )

    static let darkBase = RDTokens(
        dark: true,
        page: rdHex("0A0C10"), page2: rdHex("12151B"),
        surface: rdHex("13161C"), sc: rdHex("1D212A"),
        scLow: rdHex("171A21"), scHigh: rdHex("262B36"), scHighest: rdHex("30363F"),
        onSurface: rdHex("EAEDF2"), onVariant: rdHex("B4BBC6"),
        outline: rdHex("878E9A"), outlineVariant: rdHex("2A2F3A"),
        primary: rdHex("9CC0FF"), onPrimary: rdHex("0A2C66"),
        primaryContainer: rdHex("234890"), onPrimaryContainer: rdHex("D6E6FF"),
        bus: rdHex("5FCB8A"), busContainer: rdHex("123524"), onBusContainer: rdHex("9FE6BC"),
        mrt: rdHex("F5708A"), mrtContainer: rdHex("36161C"), onMrtContainer: rdHex("FBC4CE"),
        amber: rdHex("F5B53D"), amberContainer: rdHex("4A3410"), onAmberContainer: rdHex("FCE6C8")
    )
}
