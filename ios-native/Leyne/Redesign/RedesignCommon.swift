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
    var label: String? = nil          // VoiceOver label for this icon-only control
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
        .accessibilityLabel(label ?? "")
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

/// "then 11" → "Next 11 min"; nil when there's no following bus.
func rdNextLabel(_ then: String?) -> String? {
    guard let then else { return nil }
    let digits = then.filter(\.isNumber)
    return digits.isEmpty ? nil : "Next \(digits) min"
}

/// One live-arrival row, shared by the Home and Stop screens so they stay
/// identical: a flat grouped-list row (no card) — neutral bus badge, destination,
/// occupancy dot, and an ETA-dominant right side (green "Now" when arriving) with
/// the following bus beneath.
struct RDArrivalRow: View {
    let a: RDArrival
    let t: RDTokens
    let onTap: () -> Void

    var body: some View {
        let occ = rdOcc(a.load, t)
        let arriving = (Int(a.min) ?? 99) <= 0
        return Button(action: onTap) {
            HStack(spacing: 14) {
                Text(a.route)
                    .font(rdFont(17, .heavy)).foregroundStyle(t.onSurface)
                    .frame(minWidth: 46).frame(height: 38).padding(.horizontal, 8)
                    .background(t.scHigh).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.dest).font(rdFont(16.5, .semibold)).foregroundStyle(t.onSurface).lineLimit(1)
                    HStack(spacing: 6) {
                        RDDot(color: occ.color, size: 7)
                        Text(occ.label).font(rdFont(12.5, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    if arriving {
                        Text("Now").font(rdFont(17, .heavy)).foregroundStyle(t.bus)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(a.min).font(rdFont(24, .black)).foregroundStyle(t.onSurface)
                                .contentTransition(.numericText())
                            Text("min").font(rdFont(11, .bold)).foregroundStyle(t.onVariant)
                        }
                    }
                    if let next = rdNextLabel(a.then) {
                        Text(next).font(rdFont(10.5, .medium)).foregroundStyle(t.onVariant)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.35), value: a.min)
    }
}

extension View {
    /// Fills the available width and aligns content to the leading edge.
    func rdLeading() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}
