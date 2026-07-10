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

/// Quiet `+N` overflow chip for stops with more services than fit. Solid
/// hairline, not dashed — a dashed border is an empty-state / "add" idiom,
/// and this chip holds real content (owner walkthrough 2026-07-07).
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
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ws.rule, lineWidth: 1))
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
                .lineLimit(1)
                .fixedSize()   // never let a station code wrap ("EW2/1") in a tight row
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 21)
                .background(colour)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .large:
            Text(code)
                .font(ws.mono(15, weight: .bold))
                .foregroundStyle(WSLine.onLine)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
//
// A single-line capsule that hugs its content. The previous stacked layout
// stretched three pills across the full row width and read as "big boxes"
// (owner feedback 2026-07-02).

struct ArrivalPill: View {
    let eta: ETA
    /// nil ⟹ scheduled bus (empty gauge, dimmed) or crowd unknown.
    let load: Load?
    var highlighted: Bool = false
    var scheduled: Bool = false

    @Environment(\.ws) private var ws

    var body: some View {
        HStack(spacing: 7) {
            // minutes — "Arr" stands alone; a numeric ETA gets an "m" suffix.
            (Text(eta.big).font(ws.mono(14, weight: .bold)).foregroundStyle(ws.text)
             + Text(eta.big == "Arr" ? "" : "m")
                .font(ws.mono(10, weight: .regular))
                .foregroundStyle(ws.dim))
            CrowdGauge(fraction: scheduled ? 0 : (load?.wsFraction ?? 0), width: 22)
            Text(scheduled ? "sched" : (load?.wsShort ?? "—"))
                .font(ws.mono(9.5, weight: .regular))
                .foregroundStyle(highlighted ? ws.text : ws.dim)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 11)
        .background(ws.panel2)
        .overlay(
            Capsule()
                .stroke(highlighted ? ws.accent : ws.rule, lineWidth: highlighted ? 1.5 : 1)
        )
        .clipShape(Capsule())
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

// MARK: - Live badge (pulsing dot + the word LIVE)
//
// The one unmistakable liveness mark. A lone pulsing radar icon read as
// decoration from arm's length (owner feedback 2026-07-02) — the word does
// the explaining, the dot does the pulsing. accentSoft is the sanctioned
// "live" colour exception.

struct WSLiveBadge: View {
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            // Anim spec: slow, subtle — a 2.5s breath (scale 1.0→1.08,
            // opacity 70→100%), transforms only. The word never moves.
            Circle().fill(ws.accentSoft).frame(width: 6, height: 6)
                .scaleEffect(on ? 1.08 : 1.0)
                .opacity(on || reduceMotion ? 1 : 0.7)
            Text("LIVE").font(ws.mono(9.5, weight: .bold)).tracking(1.1)
                .foregroundStyle(ws.accentSoft)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) { on = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live data")
    }
}

// MARK: - Section header (uppercase label · LIVE badge · hairline · right meta)

struct WSSectionHeader: View {
    let label: String
    var meta: String? = nil
    var live: Bool = false
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(ws.sans(11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(ws.dim)
            if live { WSLiveBadge() }
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
    /// Optional eyebrow glyph shown before the title (owner spec 2026-07-08 —
    /// the "Nearest bus stop" / "Nearest MRT" card grammar from Home).
    var glyph: WSGlyph? = nil
    @ViewBuilder var content: Content
    @Environment(\.ws) private var ws
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 9) {
                    if let glyph {
                        WSIcon(glyph: glyph, size: 15, weight: .medium, color: ws.dim)
                    }
                    Text(title)
                        .font(ws.sans(14, weight: .semibold))
                        .foregroundStyle(ws.dim)
                }
                .padding(.top, 16).padding(.bottom, 4)
            }
            content
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Tap compress (anim spec: 98% for 80ms, no ripple, no highlight)

struct WSCompressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Departure row (the one bus-row grammar, Home + Bus stop screens)

/// One departure: plate (solid green + white + a green edge tick while
/// arriving), destination + coloured seat dot, the next arrivals stacked on
/// the right, chevron. Anim spec: only the number animates (numericText);
/// the dot's colour crossfades 200ms; tap compresses 98%/80ms and navigates
/// immediately. `showsVehicleIcons` adds the double-deck / wheelchair glyphs
/// (Bus stop screen); `extraFollowMin` appends a third arrival when known.
struct WSDepartureRow: View {
    let service: Service
    let stopCode: String
    var showsVehicleIcons: Bool = false
    @Environment(AppModel.self) private var m: AppModel
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = m.tick
        let sec = wsLiveETASec(service)
        let now = sec < 60
        let minutes = max(1, sec / 60)
        let followMin = Self.liveMin(service.followingDate, fallbackSec: service.followingSec)
        let sched = !service.monitored
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            push(.trackBus(stopCode: stopCode, no: service.no))
        } label: {
            HStack(spacing: 13) {
                Text(service.no)
                    .font(ws.mono(service.no.count > 3 ? 16 : 19, weight: .bold))
                    .foregroundStyle(now ? .white : ws.text)
                    .frame(width: 62, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(now ? ws.now : ws.panel2))
                VStack(alignment: .leading, spacing: 5) {
                    Text(service.dest.isEmpty ? "Bus \(service.no)" : service.dest)
                        .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(service.load.wsDotColor)
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: service.load)
                        Text(service.load.wsSeatPhrase)
                            .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                            .lineLimit(1).allowsTightening(true)
                        if showsVehicleIcons {
                            if service.deck == .DD { WSIcon(glyph: .busDouble, size: 13, color: ws.faint) }
                            else if service.deck == .BD { WSIcon(glyph: .busBendy, size: 13, color: ws.faint) }
                            if service.wab { WSIcon(glyph: .wheelchair, size: 13, color: ws.faint) }
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Group {
                        if now {
                            Text("Now")
                                .font(ws.sans(19, weight: .heavy)).foregroundStyle(ws.text)
                        } else if sec < 120 && !sched {
                            // Design spec: under 2 minutes reads "Arriving",
                            // not a countdown — the number stops mattering.
                            Text("Arriving")
                                .font(ws.sans(16, weight: .heavy)).foregroundStyle(ws.text)
                        } else {
                            // Scheduled-only ETA carries the whisper "~" —
                            // never a banner (feedback_timely_over_honest).
                            (Text(sched ? "~" : "")
                                .font(ws.sans(15, weight: .semibold)).foregroundStyle(ws.dim)
                             + Text("\(minutes)").font(ws.sans(19, weight: .heavy)).foregroundStyle(ws.text)
                             + Text(" min").font(ws.sans(12, weight: .semibold)).foregroundStyle(ws.dim))
                        }
                    }
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    if let followMin {
                        Text(followText(followMin))
                            .font(ws.sans(12.5, weight: .medium)).foregroundStyle(ws.dim)
                            .contentTransition(reduceMotion ? .opacity
                                                            : .numericText(countsDown: true))
                    }
                }
                WSIcon(glyph: .chevron, size: 12, color: ws.faint)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .leading) {
                if now {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ws.now)
                        .frame(width: 3, height: 46)
                        .offset(x: -12)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WSCompressStyle())
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.35, dampingFraction: 0.85), value: now)
        .animation(.snappy(duration: 0.28), value: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(now: now, minutes: minutes, followMin: followMin, sched: sched))
    }

    /// "12 min" — with the third bus appended when LTA knows it ("12 · 24 min").
    private func followText(_ followMin: Int) -> String {
        if let third = Self.liveMin(service.thirdDate, fallbackSec: 0) {
            return "\(followMin) · \(third) min"
        }
        return "\(followMin) min"
    }

    /// Live minutes from an absolute timestamp so the row ticks with the
    /// board. nil when LTA has no such bus.
    static func liveMin(_ date: Date?, fallbackSec: Int) -> Int? {
        let sec: Int
        if let date {
            sec = max(0, Int(date.timeIntervalSince(Date())))
        } else if fallbackSec > 0 {
            sec = fallbackSec
        } else {
            return nil
        }
        return max(1, sec / 60)
    }

    private func a11y(now: Bool, minutes: Int, followMin: Int?, sched: Bool) -> String {
        var parts = [now ? "Bus \(service.no), arriving now"
                         : "Bus \(service.no), \(sched ? "around " : "")\(minutes) minutes"]
        if !service.dest.isEmpty { parts.append("to \(service.dest)") }
        parts.append(service.load.wsSeatPhrase)
        if service.wab { parts.append("wheelchair accessible") }
        if let followMin { parts.append("then \(followMin) minutes") }
        return parts.joined(separator: ", ")
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
        // Fill the row and lead-align — an HStack that hugs its content gets
        // centred by parent VStacks, which reads as unaligned.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hairline button (bare toolbar icon, ≥44×44 tap target)
//
// Every current use sits in a toolbar, where iOS 26 already wraps items in
// its own Liquid Glass circle — drawing our own panel + hairline inside it
// produced a double outline (owner-reported UI bug, 2026-07-02). The button
// is now a bare icon: the system supplies the chrome on 26, and a plain
// icon is the native nav-bar idiom on 18–25.

struct WSHairButton: View {
    let glyph: WSGlyph
    var filled: Bool = false
    var action: () -> Void
    @Environment(\.ws) private var ws
    var body: some View {
        Button(action: action) {
            WSIcon(glyph: glyph, size: 19)
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
    /// `title` + `collapsed`: when the screen's big in-content title scrolls
    /// away, pass `collapsed: true` and the bar's eyebrow animates into the
    /// title (and back on scroll-up) — the large-title→inline idiom.
    func wsHeaderBar<Trailing: View>(eyebrow: String,
                                      title: String? = nil,
                                      collapsed: Bool = false,
                                      onBack: (() -> Void)? = nil,
                                      @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        modifier(WSHeaderBarChrome(eyebrow: eyebrow, title: title,
                                   collapsed: collapsed, onBack: onBack, trailing: trailing))
    }
    func wsHeaderBar(eyebrow: String,
                     title: String? = nil,
                     collapsed: Bool = false,
                     onBack: (() -> Void)? = nil) -> some View {
        wsHeaderBar(eyebrow: eyebrow, title: title, collapsed: collapsed,
                    onBack: onBack) { EmptyView() }
    }
}

private struct WSHeaderBarChrome<Trailing: View>: ViewModifier {
    let eyebrow: String
    var title: String?
    var collapsed: Bool = false
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showTitle: Bool { collapsed && title != nil }

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            // Hiding the system back button also disables the edge-swipe pop
            // gesture (its delegate requires the default button) — reinstate
            // it. Owner-reported regression 2026-07-02.
            .enableSwipeBack()
            .toolbar {
                if let onBack {
                    ToolbarItem(placement: .navigationBarLeading) {
                        WSHairButton(glyph: .back, action: onBack)
                    }
                }
                ToolbarItem(placement: .principal) {
                    ZStack {
                        if showTitle {
                            Text(title ?? "")
                                .font(ws.sans(14, weight: .heavy))
                                .foregroundStyle(ws.text)
                                .lineLimit(1)
                                .transition(reduceMotion ? .opacity :
                                    .move(edge: .bottom).combined(with: .opacity))
                        } else {
                            Text(eyebrow.uppercased())
                                .font(ws.sans(11, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(ws.dim)
                                .lineLimit(1)
                                .transition(reduceMotion ? .opacity :
                                    .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.22), value: showTitle)
                    // The bar region clips, so the moving lines slide in/out
                    // of the chrome instead of floating over content.
                    .clipped()
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
        // The current period is ENLARGED (taller track, brighter label)
        // rather than outlined — a thick border read as selection chrome,
        // not emphasis (design spec §8).
        let trackH: CGFloat = isNow ? 58 : 44
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 7)
                .fill(ws.rule)
                .frame(height: trackH)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ws.text)
                        .frame(height: trackH * fraction)
                        .scaleEffect(y: shown ? 1 : 0, anchor: .bottom)
                }
            Text(time)
                .font(ws.mono(10, weight: isNow ? .bold : .regular))
                .foregroundStyle(isNow ? ws.text : ws.dim)
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

// MARK: - Skeletons (spec: shimmer, never a spinner)

/// A single shimmering placeholder bar. The highlight sweeps left → right
/// every 1.4s; Reduce Motion renders it static.
struct WSShimmerBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(ws.panel2)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, ws.rule.opacity(0.9), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}

/// Skeleton for one departure row: plate + two text bars + an ETA bar.
struct WSSkeletonRow: View {
    var body: some View {
        HStack(spacing: 13) {
            WSShimmerBar(width: 62, height: 46)
            VStack(alignment: .leading, spacing: 7) {
                WSShimmerBar(width: 130, height: 13)
                WSShimmerBar(width: 88, height: 10)
            }
            Spacer(minLength: 8)
            WSShimmerBar(width: 46, height: 16)
        }
    }
}

/// Whole-card skeleton shown before the first nearby stop resolves.
struct WSSkeletonCard: View {
    @Environment(\.ws) private var ws
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WSShimmerBar(width: 84, height: 12)
            WSShimmerBar(width: 190, height: 22)
            WSShimmerBar(width: 120, height: 11)
            WSRowDivider().padding(.top, 4)
            ForEach(0..<3, id: \.self) { _ in WSSkeletonRow() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ws.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel("Finding transport near you")
    }
}


