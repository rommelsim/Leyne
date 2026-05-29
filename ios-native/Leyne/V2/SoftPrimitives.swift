// Smaller V2 primitives shared across screens. Kept together for
// discoverability — promote out if any grows past ~40 lines.

import SwiftUI

/// Walk-time tile — leading element on Nearby rows. 44×44 (iOS) rounded
/// surface-tinted square with "N min" walk time.
struct WalkTile: View {
    let t: Theme
    let minutes: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(minutes)")
                .font(t.sans(18, weight: .semibold))
                .foregroundStyle(t.accent)
            Text("min")
                .font(t.mono(9))
                .foregroundStyle(t.dim)
        }
        .frame(width: 44, height: 44)
        .background(t.liveBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Toggle switch — Soft variant of LeyneSwitch with accent track when on.
/// 38×22 pill per the Soft prototype (`proto-soft-ios.jsx:455`).
struct SoftToggle: View {
    let t: Theme
    @Binding var value: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { value.toggle() }
        } label: {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule().fill(value ? t.accent : t.surfaceHi)
                    .frame(width: 38, height: 22)
                Circle().fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Eyebrow" mono caption — used above page titles ("STOP 80071", "LIVE MAP").
struct Eyebrow: View {
    let text: String
    let t: Theme

    var body: some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
    }
}

/// Press-down scale for tappable cards — recreates the prototype's 0.985
/// mousedown scale. Implemented as a ButtonStyle so the scale is driven by
/// the button's own `isPressed` state. The earlier version layered a
/// `DragGesture(minimumDistance: 0)` onto the card, which claimed the touch
/// on contact and blocked the enclosing ScrollView from panning — you
/// couldn't scroll if your finger landed on a card. A ButtonStyle yields
/// the same press feedback while letting the scroll gesture win, and it
/// also replaces `.buttonStyle(.plain)` (no default button chrome).
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Legend dot used on the LIVE MAP caption row ("● BUS 80   ● STOP   ● ME").
struct LegendDot: View {
    let label: String
    let color: Color
    let t: Theme

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(t.mono(9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(t.dim)
        }
    }
}

/// Vertical MRT-line bar — coloured 4×28 rectangle leading an alert card.
struct MRTLineBar: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4, height: 28)
    }
}
