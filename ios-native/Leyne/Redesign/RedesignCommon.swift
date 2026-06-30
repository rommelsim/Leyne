// Shared primitives for the redesign screens (iOS): an SF Symbol wrapper,
// occupancy → symbol/label/colour resolution, a crowd dot, a circular icon
// button, and a couple of small reused modifiers.

import SwiftUI

/// SF Symbol rendered at a fixed point size / weight / colour. Pass the
/// ".fill" variant name for filled glyphs (mirrors Material Symbols FILL=1).
struct RDSym: View {
    let name: String
    var size: CGFloat
    var color: Color
    var weight: Font.Weight = .regular

    init(_ name: String, size: CGFloat, color: Color, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }
}

/// Occupancy resolved for arrival rows: (symbol, label, colour).
func rdOcc(_ load: RDLoad, _ t: RDTokens) -> (symbol: String, label: String, color: Color) {
    switch load {
    case .seats: return ("figure.seated.side", "Seats available", t.bus)
    case .standing: return ("figure.stand", "Standing room", t.amber)
    case .packed: return ("person.3.fill", "Packed", t.mrt)
    }
}

func rdLoadColor(_ load: RDLoad, _ t: RDTokens) -> Color {
    switch load {
    case .seats: return t.bus
    case .standing: return t.amber
    case .packed: return t.mrt
    }
}

/// Small circular crowd / live dot.
struct RDDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Circular outline icon button used in detail-screen headers.
struct RDCircleButton: View {
    let symbol: String
    var bordered: Bool = true
    var iconColor: Color? = nil
    var bg: Color? = nil
    var size: CGFloat = 42
    var iconSize: CGFloat = 21
    let t: RDTokens
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(bg ?? Color.clear)
                if bordered {
                    Circle().strokeBorder(t.outlineVariant, lineWidth: 1)
                }
                RDSym(symbol, size: iconSize, color: iconColor ?? t.onSurface)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Rounded card surface used by the list screens.
struct RDCard<Content: View>: View {
    let t: RDTokens
    var radius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(t.scLow)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(t.outlineVariant, lineWidth: 1)
            )
    }
}

extension View {
    /// Fills the available width and aligns content to the leading edge.
    func rdLeading() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}
