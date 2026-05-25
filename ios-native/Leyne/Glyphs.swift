// Custom vector marks the design draws as inline SVG and that have no clean
// SF Symbol equivalent: the Lyne brand mark and the "Step-up" (not wheelchair
// accessible) glyph. Everything else uses SF Symbols.

import SwiftUI

/// Two parallel diagonal strokes — the Lyne identity. Dim base + live leader.
struct LeyneMark: View {
    var dim: Color
    var live: Color
    var lineWidth: CGFloat = 7
    var dimOpacity: Double = 0.55

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 68.0
            Path { p in
                p.move(to: CGPoint(x: 14 * s, y: 50 * s))
                p.addLine(to: CGPoint(x: 32 * s, y: 18 * s))
            }
            .stroke(dim.opacity(dimOpacity), style: StrokeStyle(lineWidth: lineWidth * s, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 32 * s, y: 50 * s))
                p.addLine(to: CGPoint(x: 50 * s, y: 18 * s))
            }
            .stroke(live, style: StrokeStyle(lineWidth: lineWidth * s, lineCap: .round))
        }
    }
}

/// "Step-up" — a wheelchair pictogram with a diagonal strike-through, used to
/// flag the rare non-accessible bus (inverted accessibility signal).
struct StepUpGlyph: View {
    var color: Color
    var size: CGFloat = 11

    var body: some View {
        ZStack {
            Image(systemName: "figure.roll")
                .font(.system(size: size, weight: .regular))
            // diagonal strike
            Rectangle()
                .fill(color)
                .frame(width: size * 1.55, height: max(1.2, size * 0.11))
                .rotationEffect(.degrees(-45))
        }
        .foregroundStyle(color)
        .frame(width: size * 1.4, height: size * 1.4)
    }
}

/// A small inline label: "● Crowded" style load dot + text.
struct LoadDotLabel: View {
    let load: Load
    let t: Theme
    var dotSize: CGFloat = 5
    var fontSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(load.color(t)).frame(width: dotSize, height: dotSize)
            Text(load.label).font(t.mono(fontSize)).foregroundStyle(t.dim)
        }
    }
}

/// iOS-style switch matching the design's 44×26 pill.
struct LeyneSwitch: View {
    let t: Theme
    @Binding var value: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { value.toggle() }
        } label: {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule().fill(value ? t.live : t.line)
                    .frame(width: 44, height: 26)
                Circle().fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control used in Settings (theme / search style).
struct SegmentedControl: View {
    let t: Theme
    @Binding var value: String
    let options: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let active = value == opt.value
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { value = opt.value }
                } label: {
                    Text(opt.label)
                        .font(t.sans(12, weight: .medium))
                        .foregroundStyle(active ? t.bg : t.dim)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(active ? t.fg : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(t.bg, in: Capsule())
        .overlay(Capsule().stroke(t.line, lineWidth: 1))
    }
}

/// Pulsing dot used on arriving cards (the design's .pulse-dot ring).
struct PulseDot: View {
    var color: Color
    var size: CGFloat = 7
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle().fill(color).opacity(animate ? 0 : 0.7)
                .scaleEffect(animate ? 2.4 : 0.9)
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

/// Outward-rippling capsule ring used as a coachmark — overlay it on any
/// element to draw a first-time user's eye. Pure decoration: it ignores
/// hit-testing so the user can still tap the element beneath. Auto-fades
/// to zero; the parent decides when to remove it from the view tree.
struct CoachmarkRing: View {
    var color: Color
    @State private var on = false

    var body: some View {
        Capsule()
            .stroke(color, lineWidth: 1.6)
            .scaleEffect(on ? 1.35 : 0.95)
            .opacity(on ? 0 : 0.85)
            .padding(-6)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

/// Inline mono "kind" pill (DD / SD chip).
struct DeckChip: View {
    let deck: Deck
    let t: Theme
    var body: some View {
        Text(deck.rawValue)
            .font(t.mono(9))
            .foregroundStyle(t.dim)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.line, lineWidth: 1))
    }
}
