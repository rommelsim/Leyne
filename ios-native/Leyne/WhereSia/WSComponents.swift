// WhereSia — shared components.
//
// Every reusable primitive from DESIGN-SYSTEM.md: crowd gauge, route tiles,
// line bullet, arrival pill, chip, section header, card, tab bar, toggle,
// segmented control, header bar, hairline button. Motion is restrained and
// gated behind Reduce Motion.

import SwiftUI

// MARK: - Crowd gauge (neutral occupancy — colour reserved for lines)

/// A 26×6 rounded track (`rule`) with a `text` fill. Fill width = fraction.
/// Fills animate on appear via a leading scaleX. ALWAYS pair with a word at
/// the call site — VoiceOver must never rely on the gauge alone.
struct CrowdGauge: View {
    let fraction: CGFloat
    var width: CGFloat = 26
    var height: CGFloat = 6

    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(ws.rule)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(ws.text)
                    .frame(width: max(0, width * fraction), height: height)
                    .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
            }
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Entrance (restrained fade + slide-up on appear)

/// The single app-wide entrance motion: content fades in and rises a few points
/// when its screen appears. One idiom, one line to apply (`.wsEntrance()`), so
/// every screen animates in consistently. Fully gated behind Reduce Motion.
struct WSEntrance: ViewModifier {
    var delay: Double = 0
    var rise: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(.easeOut(duration: 0.45).delay(delay)) { shown = true } }
            }
    }
}

extension View {
    /// Fade + slide-up as the view appears. `delay` staggers siblings.
    func wsEntrance(delay: Double = 0, rise: CGFloat = 12) -> some View {
        modifier(WSEntrance(delay: delay, rise: rise))
    }
}

// MARK: - Ping halo (attention — draws the eye to a live/important node)

/// A repeating "radar ping": a neutral ring that expands and fades out from an
/// anchor, used to pull the eye to the live things that matter — the moving bus
/// and the user's stop. Place as a `.background` of the anchor so it inherits
/// its size and shape. Neutral (text colour — colour stays reserved for lines)
/// and fully gated behind Reduce Motion.
struct WSPing: View {
    /// Match the anchor's corner radius (use a large value for a circle).
    var cornerRadius: CGFloat = 999
    var lineWidth: CGFloat = 2
    var maxScale: CGFloat = 2.0

    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(ws.accentSoft, lineWidth: lineWidth)
            .scaleEffect(animate ? maxScale : 1)
            .opacity(animate ? 0 : 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Route tiles (mono, neutral — never coloured)

struct RouteTile: View {
    enum Size { case small, large }
    let text: String
    var size: Size = .small

    @Environment(\.ws) private var ws

    var body: some View {
        switch size {
        case .small:
            Text(text)
                .font(ws.mono(12, weight: .bold))
                .foregroundStyle(ws.text)
                .lineLimit(1)
                .fixedSize()   // never let a route number ellipsize in a tight row
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 21)
                .background(ws.panel2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ws.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .large:
            Text(text)
                .font(ws.mono(16, weight: .bold))
                .foregroundStyle(ws.text)
                .frame(width: 46, height: 40)
                .background(ws.panel2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ws.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Dashed `+N` overflow chip for stops with more services than fit.
struct OverflowTile: View {
    let count: Int
    @Environment(\.ws) private var ws
    var body: some View {
        Text("+\(count)")
            .font(ws.mono(11, weight: .bold))
            .foregroundStyle(ws.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: 21)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(ws.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
    }
}

// MARK: - Line bullet (mono tile, white text on the official line hex)

struct LineBullet: View {
    enum Size { case small, large }
    /// A station code ("NS22", "TE14") or a line code ("EWL", "NSL").
    let code: String
    var size: Size = .small
    /// When true, colour is derived from a line code (EWL) not a station code.
    var isLineCode: Bool = false

    @Environment(\.ws) private var ws

    private var colour: Color {
        isLineCode ? WSLine.color(forLineCode: code)
                   : WSLine.color(forStationCode: code)
    }

    var body: some View {
        switch size {
        case .small:
            Text(code)
                .font(ws.mono(12, weight: .bold))
                .foregroundStyle(WSLine.onLine)
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 21)
                .background(colour)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .large:
            Text(code)
                .font(ws.mono(15, weight: .bold))
                .foregroundStyle(WSLine.onLine)
                .frame(width: 46, height: 40)
                .background(colour)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// A row of route tiles for a stop, capped with a `+N` overflow chip.
struct TileRow: View {
    let services: [String]
    var cap: Int = 3
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(services.prefix(cap)), id: \.self) { RouteTile(text: $0) }
            if services.count > cap {
                OverflowTile(count: services.count - cap)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Arrival pill (minutes + gauge + word)

struct ArrivalPill: View {
    let eta: ETA
    /// nil ⟹ scheduled bus (empty gauge, dimmed) or crowd unknown.
    let load: Load?
    var highlighted: Bool = false
    var scheduled: Bool = false

    @Environment(\.ws) private var ws

    var body: some View {
        VStack(spacing: 7) {
            // minutes — "Arr" stands alone; a numeric ETA gets an "m" suffix.
            (Text(eta.big).font(ws.mono(16, weight: .bold)).foregroundStyle(ws.text)
             + Text(eta.big == "Arr" ? "" : "m")
                .font(ws.mono(10, weight: .regular))
                .foregroundStyle(ws.dim))
            CrowdGauge(fraction: scheduled ? 0 : (load?.wsFraction ?? 0), width: 30)
            Text(scheduled ? "sched" : (load?.wsShort ?? "—"))
                .font(ws.mono(9, weight: .regular))
                .foregroundStyle(highlighted ? ws.text : ws.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(ws.panel2)
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(highlighted ? ws.accent : ws.rule, lineWidth: highlighted ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .opacity(scheduled ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillLabel)
    }

    private var pillLabel: String {
        let when = eta.big == "Arr" ? "arriving now" : "\(eta.big) minutes"
        if scheduled { return "\(when), scheduled" }
        return "\(when), \(load?.wsWord ?? "crowd unknown")"
    }
}

// MARK: - Chip (mono, hairline)

struct WSChip: View {
    var gauge: CGFloat? = nil
    let text: String
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 6) {
            if let g = gauge { CrowdGauge(fraction: g, width: 22) }
            Text(text).font(ws.mono(10, weight: .bold)).foregroundStyle(ws.dim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(ws.rule, lineWidth: 1))
    }
}

// MARK: - Section header (uppercase label · hairline · right meta)

struct WSSectionHeader: View {
    let label: String
    var meta: String? = nil
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(ws.sans(11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(ws.dim)
            Rectangle().fill(ws.rule).frame(height: 1)
            if let meta {
                // Real content (a timestamp / count), not decoration — `dim`
                // clears WCAG AA 4.5:1 in both themes; `faint` doesn't.
                Text(meta)
                    .font(ws.mono(11))
                    .tracking(0.5)
                    .foregroundStyle(ws.dim)
            }
        }
    }
}

// MARK: - Card (panel with an uppercase title)

struct WSCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.ws) private var ws
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(ws.sans(11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(ws.dim)
                    .padding(.top, 12).padding(.bottom, 4)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Key/value row inside a card.
struct WSKV: View {
    let key: String
    let value: String
    var valueSuffix: String? = nil
    var last: Bool = false
    @Environment(\.ws) private var ws
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(ws.sans(13, weight: .semibold)).foregroundStyle(ws.dim)
                Spacer()
                Text(value).font(ws.mono(14, weight: .bold)).foregroundStyle(ws.text)
            }
            .padding(.vertical, 11)
            if !last { Rectangle().fill(ws.rule).frame(height: 1) }
        }
    }
}

// MARK: - Toggle (pill)

struct WSToggle: View {
    @Binding var isOn: Bool
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Capsule()
            .fill(isOn ? ws.accent : ws.panel2)
            .overlay(Capsule().stroke(isOn ? ws.accent : ws.rule, lineWidth: 1))
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? .white : ws.faint)
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isOn)
            .onTapGesture { isOn.toggle() }
            .sensoryFeedback(.selection, trigger: isOn)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Segmented control

struct WSSegmented: View {
    let options: [String]
    @Binding var selection: Int
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selection
                Button { selection = i } label: {
                    Text(options[i])
                        .font(ws.sans(12.5, weight: .bold))
                        .foregroundStyle(on ? .white : ws.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(on ? ws.accent : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ws.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

// MARK: - Filter chip row

struct WSFilterChips: View {
    let options: [String]
    @Binding var selection: Int
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selection
                Button { selection = i } label: {
                    Text(options[i])
                        .font(ws.sans(13, weight: .bold))
                        .foregroundStyle(on ? .white : ws.dim)
                        .padding(.horizontal, 15).padding(.vertical, 8)
                        .background(on ? ws.accent : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(on ? ws.accent : ws.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hairline button (38×38 visual, ≥44×44 tap target)

struct WSHairButton: View {
    let glyph: WSGlyph
    var filled: Bool = false
    var action: () -> Void
    @Environment(\.ws) private var ws
    var body: some View {
        Button(action: action) {
            WSIcon(glyph: glyph, size: 19)
                .frame(width: 38, height: 38)
                .background(ws.panel)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(ws.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                // Visual stays 38×38 (the WhereSia chip size); the tappable
                // area grows to the HIG's 44×44 minimum around it.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header bar (native nav-bar chrome; back · eyebrow · action)
//
// Pushed WhereSia screens apply this via `.wsHeaderBar(...)` instead of
// hosting a header as in-body content: the system now draws the actual nav
// bar — real Liquid Glass on iOS 26, translucent material on 18–25 — behind
// our WhereSia-styled leading/principal/trailing content. This also restores
// the interactive edge-swipe-back gesture for free: hiding the back *button*
// (`navigationBarBackButtonHidden`) doesn't disable it, only hiding the whole
// bar (the previous approach, paired with the `enableSwipeBack()` workaround)
// did.
extension View {
    func wsHeaderBar<Trailing: View>(eyebrow: String,
                                      onBack: (() -> Void)? = nil,
                                      @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        modifier(WSHeaderBarChrome(eyebrow: eyebrow, onBack: onBack, trailing: trailing))
    }
    func wsHeaderBar(eyebrow: String, onBack: (() -> Void)? = nil) -> some View {
        wsHeaderBar(eyebrow: eyebrow, onBack: onBack) { EmptyView() }
    }
}

private struct WSHeaderBarChrome<Trailing: View>: ViewModifier {
    let eyebrow: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.ws) private var ws

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if let onBack {
                    ToolbarItem(placement: .navigationBarLeading) {
                        WSHairButton(glyph: .back, action: onBack)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(eyebrow.uppercased())
                        .font(ws.sans(11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(ws.dim)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    trailing()
                }
            }
    }
}

// MARK: - Crowd forecast bar (grows on appear)

struct ForecastBar: View {
    let fraction: CGFloat
    let time: String
    var isNow: Bool = false
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 7)
                .fill(ws.rule)
                .frame(height: 46)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ws.text)
                        .frame(height: 46 * fraction)
                        .scaleEffect(y: shown ? 1 : 0, anchor: .bottom)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isNow ? ws.text : .clear, lineWidth: 2)
                        .padding(-3)
                )
            Text(time).font(ws.mono(10)).foregroundStyle(ws.dim)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion { shown = true }
            else { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
        }
    }
}

// MARK: - Divider row helper

struct WSRowDivider: View {
    @Environment(\.ws) private var ws
    var body: some View { Rectangle().fill(ws.rule).frame(height: 1) }
}
