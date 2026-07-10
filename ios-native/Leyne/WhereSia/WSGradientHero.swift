// WhereSia — the living sky hero.
//
// COPYRIGHT NOTE (owner, 2026-07-10): the reference mockups used a photographic
// train/skyline hero. We ship NO photography. Instead the hero is a generated,
// slowly-drifting ambient gradient (an animated MeshGradient) whose palette is
// computed from the time of day and — via a stubbed hook, wired later — the
// weather. Dawn warms, midday brightens to blue, dusk deepens to violet, night
// falls to near-black indigo; overcast desaturates, rain cools, haze veils.
//
// The motion is deliberately barely-there — a calm ambient drift, not a
// light-show — and collapses to a static mesh under Reduce Motion. This is the
// ONE place colour is allowed as chrome (owner call 2026-07-10 supersedes the
// "colour = data" rule for the greeting hero specifically); every content
// surface below the hero stays greyscale.

import SwiftUI
import UIKit  // UIColor — mesh-corner colour blending

// MARK: - Weather (stubbed hook)

/// The weather condition the sky reacts to. WeatherKit was removed from iOS
/// (App Store 5.2.5), so there is no live source today: this defaults to
/// `.clear` and is driven purely by time. When a weather source is wired back
/// in, set `WSSky.weather` and the hero reacts on the next frame — no other
/// change needed.
enum WSWeather: String, CaseIterable {
    case clear, cloudy, rain, haze

    /// Multipliers the palette applies: saturation, brightness, and a neutral
    /// grey veil (0 = none, 1 = fully grey). Tuned to stay legible under the
    /// white greeting text in every theme.
    var mood: (sat: Double, bri: Double, veil: Double) {
        switch self {
        case .clear:  return (1.00, 1.00, 0.00)
        case .cloudy: return (0.62, 0.90, 0.22)
        case .rain:   return (0.55, 0.74, 0.30)
        case .haze:   return (0.70, 0.86, 0.18)
        }
    }
}

// MARK: - Sky model

/// Turns a wall-clock date + weather into the three-stop palette the hero mesh
/// is built from. Pure value type; no view state.
struct WSSky {
    /// Current weather. Time-only today (`.clear`); flip this when a weather
    /// feed returns (see the header note).
    static var weather: WSWeather = .clear

    /// Keyframes around the 24-hour ring: hour → (top, mid, bottom) sky stops.
    /// Interpolated linearly to the exact minute so the sky is never static
    /// between keyframes even across a long dwell.
    private static let ring: [(hour: Double, top: RGB, mid: RGB, bottom: RGB)] = [
        // deep night — indigo into near-black
        (0,  RGB(0.05, 0.07, 0.16), RGB(0.06, 0.08, 0.20), RGB(0.03, 0.04, 0.09)),
        // pre-dawn — indigo warming at the horizon
        (5,  RGB(0.12, 0.11, 0.28), RGB(0.28, 0.18, 0.34), RGB(0.06, 0.06, 0.15)),
        // sunrise — violet into peach
        (7,  RGB(0.30, 0.24, 0.48), RGB(0.72, 0.44, 0.42), RGB(0.16, 0.14, 0.28)),
        // morning — soft blue into cyan
        (9,  RGB(0.20, 0.42, 0.70), RGB(0.38, 0.62, 0.82), RGB(0.14, 0.28, 0.50)),
        // midday — bright, clean blue
        (13, RGB(0.16, 0.44, 0.78), RGB(0.34, 0.64, 0.90), RGB(0.12, 0.32, 0.62)),
        // afternoon — blue easing to warm gold
        (16, RGB(0.20, 0.40, 0.72), RGB(0.60, 0.56, 0.66), RGB(0.16, 0.26, 0.50)),
        // golden hour — amber into rose
        (18, RGB(0.42, 0.30, 0.50), RGB(0.86, 0.52, 0.40), RGB(0.22, 0.16, 0.32)),
        // dusk — violet into deep blue
        (20, RGB(0.20, 0.16, 0.40), RGB(0.34, 0.22, 0.46), RGB(0.08, 0.08, 0.22)),
        // evening — indigo settling to night
        (22, RGB(0.09, 0.10, 0.24), RGB(0.12, 0.11, 0.28), RGB(0.05, 0.05, 0.13)),
        // wrap back to 0h
        (24, RGB(0.05, 0.07, 0.16), RGB(0.06, 0.08, 0.20), RGB(0.03, 0.04, 0.09)),
    ]

    let top: Color
    let mid: Color
    let bottom: Color
    /// A darker relative of `bottom` used to fade the hero into the page.
    let base: Color

    init(at date: Date, weather: WSWeather = WSSky.weather) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let h = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60.0

        // Find the two keyframes bracketing `h` and lerp between them.
        var lo = Self.ring[0], hi = Self.ring[Self.ring.count - 1]
        for i in 0..<(Self.ring.count - 1) where h >= Self.ring[i].hour && h <= Self.ring[i + 1].hour {
            lo = Self.ring[i]; hi = Self.ring[i + 1]; break
        }
        let span = max(0.0001, hi.hour - lo.hour)
        let t = min(1, max(0, (h - lo.hour) / span))

        let mood = weather.mood
        func stop(_ a: RGB, _ b: RGB) -> Color {
            a.lerp(to: b, t).moodAdjusted(mood).color
        }
        top = stop(lo.top, hi.top)
        mid = stop(lo.mid, hi.mid)
        bottom = stop(lo.bottom, hi.bottom)
        base = lo.bottom.lerp(to: hi.bottom, t).scaled(0.55).moodAdjusted(mood).color
    }

    /// Time-of-day greeting — "Good morning / afternoon / evening".
    static func greeting(at date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - RGB helper (linear-ish colour math the SwiftUI Color API can't do)

/// A tiny sRGB triplet so the palette can interpolate and mood-adjust before
/// becoming a `Color`. Not colour-accurate linear light — just enough to blend
/// keyframes smoothly and desaturate for weather.
private struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    func lerp(to o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    func scaled(_ f: Double) -> RGB { RGB(r * f, g * f, b * f) }

    /// Apply a weather mood: pull toward the channel average (desaturate),
    /// scale brightness, then veil toward neutral grey.
    func moodAdjusted(_ mood: (sat: Double, bri: Double, veil: Double)) -> RGB {
        let avg = (r + g + b) / 3
        var out = RGB(avg + (r - avg) * mood.sat,
                      avg + (g - avg) * mood.sat,
                      avg + (b - avg) * mood.sat).scaled(mood.bri)
        let grey = 0.45
        out = RGB(out.r + (grey - out.r) * mood.veil,
                  out.g + (grey - out.g) * mood.veil,
                  out.b + (grey - out.b) * mood.veil)
        return out
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

// MARK: - The animated mesh

/// A slowly-drifting mesh gradient painted from a `WSSky`. The four interior
/// control points breathe on long, out-of-phase sine paths (≈20–30s periods)
/// so the light never sits still, yet never distracts. Static under Reduce
/// Motion. iOS 18+ uses `MeshGradient`; older systems get a soft linear fade.
struct WSSkyGradient: View {
    /// Re-samples the sky on this cadence (drives slow palette shift over a
    /// long dwell without a per-second tick).
    var sky: WSSky
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 18.0, *) {
            TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 30.0)) { tl in
                let phase = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                mesh(phase: phase)
            }
        } else {
            LinearGradient(colors: [sky.top, sky.mid, sky.bottom],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @available(iOS 18.0, *)
    private func mesh(phase: Double) -> some View {
        // Drift amplitude in normalised mesh space — tiny, so points stay in
        // their row/column and the mesh never folds. The glow point roams a
        // little wider (it's the soft light source, not a grid corner).
        func d(_ speed: Double, _ off: Double, _ amp: Double = 0.05) -> Float {
            Float(sin(phase * speed + off) * amp)
        }
        let pts: [SIMD2<Float>] = [
            [0, 0],                                  [0.5 + d(0.17, 2.2), 0],                 [1, 0],
            [0, 0.5 + d(0.28, 0)],                   [0.42 + d(0.22, 1.7, 0.10), 0.44 + d(0.31, 0.6, 0.08)], [1, 0.5 + d(0.26, 3.1)],
            [0, 1],                                  [0.5, 1],                                [1, 1],
        ]
        // Nine mesh colours from the three stops, arranged for DEPTH rather
        // than flat bands: the top corners stay deep, a single warm/bright
        // glow blooms off-centre in the upper-middle (the "light source"),
        // and the bottom settles into `bottom`. No uniform edge row — that
        // dead-flat top was the muddy look (owner, 2026-07-10).
        let t = sky.top, m = sky.mid, b = sky.bottom
        let deep = t.blended(b, 0.35)          // deepened top corners
        let glow = m.blended(.white, 0.16)     // soft luminous centre
        let colors: [Color] = [
            deep,               t.blended(m, 0.45),  deep.blended(m, 0.2),
            t.blended(m, 0.4),  glow,                m,
            b,                  b.blended(m, 0.12),  b.blended(deep, 0.4),
        ]
        return MeshGradient(width: 3, height: 3, points: pts, colors: colors)
    }
}

private extension Color {
    /// Cheap perceptual-ish blend for the mesh corners (UIColor mix).
    func blended(_ other: Color, _ t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(.sRGB,
                     red: ar + (br - ar) * t,
                     green: ag + (bg - ag) * t,
                     blue: ab + (bb - ab) * t,
                     opacity: 1)
    }
}

// MARK: - Greeting hero

/// The Home header: the living sky behind a time-of-day greeting and (optional)
/// trailing action + a tappable search field. Fades into the page background at
/// the bottom so the content cards below continue seamlessly.
struct WSGreetingHero<Trailing: View>: View {
    var onSearchTap: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.ws) private var ws

    // GRADIENT PARKED (owner, 2026-07-10 "remove the gradient for now"): the
    // living-sky background is disabled while the layout settles. The sky
    // engine (WSSky / WSSkyGradient) stays in this file intact — to bring it
    // back, restore the ZStack { WSSkyGradient(...) } body from git history.
    // For now the header is a plain, content-sized greeting + search over the
    // page background (no fixed height → no dead space below the field).
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WSSky.greeting())
                        .font(ws.sans(19, weight: .medium))
                        .foregroundStyle(ws.dim)
                    Text("Where to?")
                        .font(ws.sans(27, weight: .heavy))
                        .foregroundStyle(ws.text)
                }
                Spacer(minLength: 8)
                trailing()
            }

            Button(action: onSearchTap) {
                HStack(spacing: 11) {
                    WSIcon(glyph: .search, size: 16, weight: .medium, color: ws.dim)
                    Text("Search stop, bus or station")
                        .font(ws.sans(15, weight: .medium))
                        .foregroundStyle(ws.dim)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15).frame(height: 48)
                .background(Capsule().fill(ws.input))
                .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(WSCompressStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }
}

extension WSGreetingHero where Trailing == EmptyView {
    init(onSearchTap: @escaping () -> Void) {
        self.init(onSearchTap: onSearchTap, trailing: { EmptyView() })
    }
}
