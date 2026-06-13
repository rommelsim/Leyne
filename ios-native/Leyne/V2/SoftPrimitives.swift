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

    // Custom monochrome switch. A native Toggle tinted with t.soon goes
    // white-on-white in dark mode (the system thumb is always white, and
    // t.soon/accent is white in dark) — the knob vanishes. We draw our own so
    // both states read in both modes: ON = accent-filled track with a
    // contrasting onAccent thumb; OFF = subtle track with a dim thumb.
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { value.toggle() }
        } label: {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule()
                    .fill(value ? t.accent : t.surfaceHi)
                    .overlay(Capsule().stroke(t.line, lineWidth: 1))
                    .frame(width: 46, height: 28)
                Circle()
                    .fill(value ? t.onAccent : t.dim)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(value ? "On" : "Off")
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

/// Multi-colour MRT line bar — vertical (for list rows) or horizontal (for hero rules).
///
/// Renders a thin rounded bar whose colours reflect all line codes for a station:
///   - 1 colour  → solid bar.
///   - N colours → bar split into N equal segments, one per distinct line colour
///                 (deduped while preserving code order). Vertical axis: segments
///                 run top-to-bottom. Horizontal axis: segments run left-to-right.
///
/// Interchange examples:
///   Jurong East (EW24, NS1)         → 2-segment green/red bar
///   Dhoby Ghaut (NS24, NE6, CC1)   → 3-segment red/purple/orange bar
///
/// Fixed width (4 pt) for the vertical variant so it doubles as an alignment
/// anchor in list rows. Height defaults to 44 pt to match a standard card row.
/// For the hero horizontal rule, callers flip the axis and swap width/height.
struct MrtLineColorBar: View {
    enum Axis { case vertical, horizontal }

    let colors: [Color]
    var width: CGFloat = 4
    var height: CGFloat = 44
    var axis: Axis = .vertical

    /// Single-colour convenience init (e.g. re-using from alert cards).
    init(color: Color, width: CGFloat = 4, height: CGFloat = 44, axis: Axis = .vertical) {
        self.colors = [color]
        self.width = width
        self.height = height
        self.axis = axis
    }

    /// Multi-colour init from station codes — dedups by 2-letter line prefix.
    init(codes: [String], width: CGFloat = 4, height: CGFloat = 44, axis: Axis = .vertical) {
        var seen: Set<String> = []
        self.colors = codes.compactMap { code -> Color? in
            let prefix = String(code.prefix(2)).uppercased()
            guard seen.insert(prefix).inserted else { return nil }
            return mrtLineColorFor(code)
        }
        self.width = width
        self.height = height
        self.axis = axis
    }

    var body: some View {
        let distinct = colors.isEmpty ? [Color.gray] : colors
        let r = axis == .vertical ? width / 2 : height / 2

        if distinct.count == 1 {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(distinct[0])
                .frame(width: width, height: height)
        } else {
            segmentedBar(distinct, cornerRadius: r)
        }
    }

    @ViewBuilder
    private func segmentedBar(_ distinct: [Color], cornerRadius r: CGFloat) -> some View {
        let count = CGFloat(distinct.count)
        if axis == .vertical {
            VStack(spacing: 0) {
                ForEach(Array(distinct.enumerated()), id: \.offset) { index, color in
                    segment(
                        color: color,
                        size: CGSize(width: width, height: height / count),
                        isFirst: index == 0,
                        isLast: index == distinct.count - 1,
                        cornerRadius: r,
                        axis: .vertical
                    )
                }
            }
            .frame(width: width, height: height)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(distinct.enumerated()), id: \.offset) { index, color in
                    segment(
                        color: color,
                        size: CGSize(width: width / count, height: height),
                        isFirst: index == 0,
                        isLast: index == distinct.count - 1,
                        cornerRadius: r,
                        axis: .horizontal
                    )
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func segment(
        color: Color,
        size: CGSize,
        isFirst: Bool,
        isLast: Bool,
        cornerRadius r: CGFloat,
        axis: Axis
    ) -> some View {
        // Round only the ends the segment "owns" so adjacent segments butt flush.
        let shape: UnevenRoundedRectangle = {
            if axis == .vertical {
                return UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? r : 0,
                    bottomLeadingRadius: isLast ? r : 0,
                    bottomTrailingRadius: isLast ? r : 0,
                    topTrailingRadius: isFirst ? r : 0,
                    style: .continuous
                )
            } else {
                return UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? r : 0,
                    bottomLeadingRadius: isFirst ? r : 0,
                    bottomTrailingRadius: isLast ? r : 0,
                    topTrailingRadius: isLast ? r : 0,
                    style: .continuous
                )
            }
        }()
        return Rectangle()
            .fill(color)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
    }
}

/// Legacy single-colour vertical MRT-line bar — thin 4×28 rectangle.
/// Kept for existing callers (alert cards in SoftHomeView / SoftMrtStationView).
/// New code should prefer `MrtLineColorBar`.
struct MRTLineBar: View {
    let color: Color
    var body: some View {
        MrtLineColorBar(color: color, width: 4, height: 28)
    }
}

/// Uniform MRT line-code pill — the single source of truth for all code badges.
///
/// Renders the station code (e.g. "EW24", "NS1") in a coloured capsule.
/// The fixed `minWidth: 48` ensures that short codes (NS1) and long codes
/// (EW24) occupy the same horizontal space, so stacked interchange pills
/// align flush in every list context — MRT tab, station detail, Saved tab.
///
/// Pass the ambient `Theme` so the font scales correctly with Dynamic Type
/// (the same pattern used by all other primitives in this file).
struct MrtCodePill: View {
    let t: Theme
    let code: String

    var body: some View {
        Text(code)
            .font(t.mono(11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 48)
            .background(mrtLineColorFor(code), in: Capsule())
    }
}
