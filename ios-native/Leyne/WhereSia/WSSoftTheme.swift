// Soft-blue "4b" design language — the app-wide visual system since
// 2026-07-24 (owner pick: "4b reference blue", design project file
// "Nearby Soft.dc.html"). One palette for every appearance: tinted pale-blue
// ground, floating white cards with soft shadows, ONE saturated gradient
// hero per screen, friendly rounded chrome, colour elsewhere only as
// information (official line colours, amber/red for disruptions and crowd).
//
// First shipped on Nearby (WSHomeView); the remaining WhereSia screens adopt
// these tokens rather than redeclaring their own. The greendark WSTheme
// palette still backs screens that haven't converted yet.

import SwiftUI

enum SoftBlue {
    // ─── Ground + ink ───────────────────────────────────────
    static let bg       = Color(wsHex: "DCE9F4")   // tinted page ground
    static let card     = Color.white              // floating surfaces
    static let ink      = Color(wsHex: "1B2430")   // primary text
    static let sub      = Color(wsHex: "7A8794")   // secondary text
    static let hairline = Color(wsHex: "EEF3F8")   // in-card separators

    // ─── The one accent ─────────────────────────────────────
    static let blue     = Color(wsHex: "2E8FE0")   // hero gradient start / links
    static let blueSoft = Color(wsHex: "5CB8F2")   // hero gradient end
    static let chipBg   = Color(wsHex: "E4F1FC")   // tinted chips / icon tiles
    static let chipInk  = Color(wsHex: "1F74C0")   // text on tinted chips

    // ─── Semantic (information only, never decoration) ──────
    static let amber    = Color(wsHex: "E8960C")   // disruptions / standing crowd
    static let red      = Color(wsHex: "D9483B")   // severe / packed crowd

    static let shadow   = Color(wsHex: "173049").opacity(0.07)

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [blue, blueSoft],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// ─── Motion language ───────────────────────────────────────

/// The app-wide water/cloud motion vocabulary (owner 2026-07-25): nothing
/// snaps — state changes FLOW like water finding a level, appearances DRIFT
/// in like cloud, ambient tells BREATHE. Use these tokens instead of ad-hoc
/// `.snappy`/`.easeOut` curves so the whole app moves as one weather system.
enum SoftMotion {
    /// State changes (chips, expand/collapse, value updates): a soft spring
    /// with no bounce — water settling, not a mechanical snap.
    static let flow = Animation.smooth(duration: 0.45)
    /// Appearances/entrances: slow start-fast-slow drift, like cloud moving.
    static let drift = Animation.easeInOut(duration: 0.7)
    /// One-shot appear sweeps (ring fill, hero reveal).
    static let settle = Animation.easeOut(duration: 0.9)
    /// Ambient repeating tells (tip dots, live markers): a slow inhale/exhale.
    static let breathe = Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)
}

// ─── Native press feedback ──────────────────────────────────

/// Shared press feedback for the soft-blue chrome. The custom white-card /
/// capsule / chip look must stay exactly as designed, but every tappable
/// element should still FEEL native — a real control responding to touch,
/// not inert art. Subtle scale + opacity dip on press, eased with the
/// app-wide water/cloud motion (`SoftMotion.flow`) rather than a mechanical
/// snap. Use this in place of `.buttonStyle(.plain)` on soft-chrome buttons
/// (owner audit 2026-07-25: native button behaviour, not system button skins).
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(SoftMotion.flow, value: configuration.isPressed)
    }
}

// ─── Shared chrome helpers ─────────────────────────────────

extension View {
    /// Floating white card: radius 20 continuous, soft ambient shadow.
    func softCard(radius: CGFloat = 20) -> some View {
        // The shadow belongs to the CARD SHAPE, not to the card's contents.
        // As a plain `.shadow` on self it also fell on every opaque child the
        // card contains, so a list of rows drew a drop shadow around each row
        // — the "weird cut out" on every row of All services (owner
        // 2026-07-26, three times). Shadowing the background shape alone
        // leaves the contents flat, which is what a single card should be.
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(SoftBlue.card)
                    .shadow(color: SoftBlue.shadow, radius: 9, y: 6)
            }
    }
}

/// Section header: bold title left, optional action right — sits on the
/// ground between cards ("Nearby stops · View all").
struct SoftSectionHead: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    @Environment(\.ws) private var ws

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action)
                        .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(SoftBlue.blue)
                }
                .buttonStyle(SoftPressStyle())
            }
        }
        .padding(.horizontal, 4)
    }
}

// ─── Soft equivalents of greendark primitives ──────────────
// (Forks, not in-place restyles, for screens that still read greendark
// tokens directly. WSMapView converted to soft-blue in place 2026-07-25 —
// its chrome now reads SoftBlue.* directly rather than forking. This file is
// the ONLY place new shared soft symbols may be declared — see
// docs/soft-blue-design.md appendix.)

/// Bus-number chip — soft replacement for WSServiceTile.
struct SoftServiceTile: View {
    var no: String
    var size: CGFloat = 13
    /// Fixed tile width. In a COLUMN of rows this must be set: sized to its
    /// content, "961M" makes a visibly wider pill than "93", and because the
    /// tile is the row's leading element every following column — destination,
    /// crowd word — starts at a different x on every row (owner 2026-07-26).
    /// A fixed width makes the tiles identical and the text after them align.
    var width: CGFloat? = nil
    @Environment(\.ws) private var ws

    var body: some View {
        Text(no)
            .font(ws.sans(size, weight: .heavy))
            .foregroundStyle(SoftBlue.chipInk)
            .lineLimit(1)
            // Long numbers shrink INSIDE the fixed tile rather than widening it.
            .minimumScaleFactor(0.65)
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.3)
            .frame(minWidth: width == nil ? size * 2.6 : nil)
            .frame(width: width)
            .background(SoftBlue.chipBg,
                        in: RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
    }
}

/// Segmented bus + time pill — ONE capsule, two segments: bright segment
/// carries the service number, dim segment the time, so the pair reads as a
/// unit while the halves stay distinct (owner 2026-07-25; born on the Nearby
/// hero, now the app-wide idiom for any "bus X in N min" pairing).
/// `onGradient` styles for the blue hero; default styles for white cards.
/// Fixed `noWidth`/`timeWidth` align the segment boundary down a column of rows.
struct SoftBusTimePill: View {
    var no: String
    var etaBig: String          // fmtETA(...).big: "Arr" or minutes digits
    var onGradient: Bool = false
    var noWidth: CGFloat? = nil
    var timeWidth: CGFloat? = nil
    @Environment(\.ws) private var ws

    private var arriving: Bool { etaBig == "Arr" }

    var body: some View {
        HStack(spacing: 0) {
            segment(no, weight: .heavy,
                    ink: onGradient ? .white : SoftBlue.chipInk,
                    bg: onGradient ? Color.white.opacity(0.32) : SoftBlue.chipBg,
                    width: noWidth)
            // Arriving: the WORD becomes "Now" (an abbreviation reads as a
            // word, not a clock value) and the segment takes accent ink at a
            // heavier weight, so a row that needs your legs is distinguishable
            // from "7 min" at a glance. No motion down here — a stop with
            // three arriving buses would otherwise pulse three times over.
            segment(arriving ? "Now" : "\(etaBig) min",
                    weight: arriving ? .heavy : .semibold,
                    ink: onGradient ? .white : (arriving ? SoftBlue.chipInk : SoftBlue.ink),
                    bg: onGradient ? Color.white.opacity(arriving ? 0.22 : 0.12)
                                   : SoftBlue.chipBg.opacity(arriving ? 0.9 : 0.45),
                    width: timeWidth)
        }
        .clipShape(Capsule())
        .lineLimit(1)
    }

    private func segment(_ text: String, weight: Font.Weight,
                         ink: Color, bg: Color, width: CGFloat?) -> some View {
        Text(text)
            .font(ws.sans(onGradient ? 11 : 12, weight: weight)).monospacedDigit()
            .foregroundStyle(ink)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8).padding(.vertical, onGradient ? 3.5 : 6)
            .frame(width: width)
            .background(bg)
    }
}

/// One departure line inside a gradient hero board: service number tile ·
/// destination · that bus's own ETA. The `lead` row (the soonest bus) gets
/// the big numeral — it is the card's answer now that the countdown ring is
/// gone (owner 2026-07-25) — and the rows below it stay quiet so the board
/// reads top-down rather than as three equal shouts.
///
/// White-on-gradient only: this row lives on `SoftBlue.heroGradient`.
struct SoftHeroBoardRow: View {
    var no: String
    var dest: String
    var etaBig: String          // fmtETA(...).big: "Arr" or minutes digits
    var lead: Bool = false
    var pulse: Bool = false
    @Environment(\.ws) private var ws

    var body: some View {
        HStack(spacing: 10) {
            Text(no)
                .font(ws.sans(lead ? 14 : 12.5, weight: .heavy)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 46, height: lead ? 30 : 26)
                .background(Color.white.opacity(lead ? 0.28 : 0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("to \(dest)")
                .font(ws.sans(lead ? 13.5 : 12.5, weight: lead ? .bold : .semibold))
                .opacity(lead ? 1 : 0.85)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            time
                .contentTransition(.numericText(countsDown: true))
                .opacity(pulse ? 0.5 : 1)
                // LEAD row only: below it the arrival isn't the card's answer,
                // and three breathing rows would read as decoration.
                .softArrivalPulse(lead && etaBig == "Arr")
        }
        .foregroundStyle(.white)
        .padding(.vertical, lead ? 7 : 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bus \(no) to \(dest), \(etaBig == "Arr" ? "arriving now" : "\(etaBig) minutes")")
    }

    /// "Now" rather than the "Arr" abbreviation — in a column of times an
    /// abbreviation reads as a word, not as a clock value (owner 2026-07-25).
    private var time: Text {
        guard etaBig != "Arr" else {
            return Text("Now").font(ws.sans(lead ? 26 : 15, weight: .heavy))
        }
        return Text(etaBig).font(ws.sans(lead ? 26 : 15, weight: .heavy)).monospacedDigit()
            + Text(" min").font(ws.sans(lead ? 12 : 11, weight: .semibold))
    }
}

/// Left-aligned wrapping row: lays children out horizontally and moves to the
/// next line when the width runs out. Chip rows used to be a horizontal
/// ScrollView, which clipped the last chip mid-word and hid facts off-screen
/// (owner 2026-07-26) — a wrap shows every chip and stays put.
struct SoftFlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0; lineHeight = 0
            }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX; lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// Quiet stop-code metadata — soft replacement for WSStopCodeChip.
/// 4b keeps identity info as text, not a bordered chip.
///
/// ALWAYS labelled "Stop 11119", never a bare "11119" (owner 2026-07-25): on
/// a card that also carries a bus number, a walk time and a distance, a naked
/// 5-digit number doesn't say what it counts. The label is the whole reason
/// the number is useful — it's what you match against the pole.
struct SoftStopCode: View {
    var code: String
    var suffix: String? = nil    // e.g. "1 min walk · 68m away"
    @Environment(\.ws) private var ws

    var body: some View {
        Text(wsStopCodeLabel(code, suffix: suffix))
            .font(ws.sans(11.5)).monospacedDigit()
            .foregroundStyle(SoftBlue.sub)
    }
}

/// `Stop 11119 · 1 min walk · 68m away`. One place builds the stop metadata
/// line so the label and the field order can't drift between screens.
func wsStopCodeLabel(_ code: String, suffix: String? = nil) -> String {
    let head = "Stop \(code)"
    return suffix.map { "\(head) · \($0)" } ?? head
}

/// Big ETA numeral — soft replacement for WSBigETA. No glow: emphasis is
/// weight + size only; callers carry the refresh pulse via opacity.
struct SoftBigETA: View {
    var text: String
    var size: CGFloat = 34
    @Environment(\.ws) private var ws

    var body: some View {
        Text(text)
            .font(ws.sans(size, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(SoftBlue.ink)
            .contentTransition(.numericText(countsDown: true))
    }
}

/// Titled white card — soft replacement for WSCard(title:).
struct SoftCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.ws) private var ws

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

/// Status dot with an opacity pulse — soft replacement for WSPulseDot.
/// Same semantic colours (amber disruption, red severe); NO glow shadow.
struct SoftPulseDot: View {
    var color: Color
    var size: CGFloat = 7
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.4 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(SoftMotion.breathe) { dimmed = true }
            }
    }
}

/// Pulses the ARRIVING VALUE ITSELF — the "Now" that replaced the ETA.
///
/// This started life as a separate "ARRIVING" capsule, which was wrong: on
/// the stop hero it added a fourth element to the NEXT slot only, so that
/// slot's crowd chip sat a row lower than THEN's and LATER's and the board
/// lost its alignment (owner 2026-07-26 — "why put it on top of the crowd
/// indicator… literally you can just pulsate the Arr"). Pulsing the existing
/// word costs no layout at all, so every slot keeps its shape.
///
/// The motion is a FINITE opacity breath:
/// - §5 of the design doc bans glows and pulsing dots for urgency, allowing
///   only "animate the opacity subtly (1s ease-in-out), never colour-shift
///   or glow". This is that.
/// - Three breaths (~3s), not forever. WCAG 2.2.2 requires a pause/stop/hide
///   control for automatic motion running past five seconds beside other
///   content; stopping short of it means there is nothing to gate. Apple's
///   Reduced Motion guidance agrees — stop "ongoing motion", and replace
///   meaningful animation rather than delete it, so Reduce Motion keeps the
///   word (and its accent colour) with no movement.
/// - The word carries the message alone (HIG: motion is never the only
///   channel), so missing the pulse costs nothing.
private struct SoftArrivalPulse: ViewModifier {
    let active: Bool
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.45 : 1)
            .onAppear { start() }
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active, !reduceMotion else { dimmed = false; return }
        // 6 half-cycles at 0.5s = three full breaths, then it rests opaque
        // for as long as the bus is arriving.
        withAnimation(.easeInOut(duration: 0.5).repeatCount(6, autoreverses: true)) {
            dimmed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { dimmed = false }
    }
}

extension View {
    /// Breathe this ETA three times when the bus is arriving. No-op otherwise.
    func softArrivalPulse(_ active: Bool) -> some View {
        modifier(SoftArrivalPulse(active: active))
    }
}

/// "LIVE" — a breathing dot + the word, for a screen whose data is refreshing
/// underneath it.
///
/// Nearby reads as a dead sheet of paper when nothing on it moves: minute-
/// resolution ETAs change every 60s at best, so between refreshes there is
/// no evidence the app is doing anything at all (owner 2026-07-26). The dot
/// is the ambient proof; `SoftPulseDot` is the already-sanctioned 4b pulse
/// (Alerts uses it), and Reduce Motion renders it as a static dot.
struct SoftLiveChip: View {
    @Environment(\.ws) private var ws
    var body: some View {
        HStack(spacing: 4) {
            SoftPulseDot(color: SoftBlue.blue, size: 5.5)
            Text("LIVE")
                .font(ws.sans(9.5, weight: .heavy)).kerning(0.6)
                .foregroundStyle(SoftBlue.chipInk)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(SoftBlue.chipBg, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live data")
    }
}

/// In-card hairline row divider — soft replacement for WSRowDivider.
struct SoftRowDivider: View {
    /// Leading inset; 64 aligns with text after a 38pt icon tile.
    var inset: CGFloat = 16
    var body: some View {
        Rectangle().fill(SoftBlue.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Disruption chip — the 4b replacement for amber glow edges and pulsing
/// "!" badges: a small tinted capsule with the warning as TEXT.
struct SoftDisruptionChip: View {
    var text: String
    var severe: Bool = false
    @Environment(\.ws) private var ws

    private var tint: Color { severe ? SoftBlue.red : SoftBlue.amber }

    var body: some View {
        Text(text)
            .font(ws.sans(11, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Hero countdown ring — the ONE progress ring in the language (hero-only,
/// spec §4). Fills as the bus closes in (empty-ish at 15 min, full at
/// arrival). Live tells follow the water/cloud motion language (owner
/// 2026-07-25 — the old orbiting satellite read as gimmicky):
///   • the fill arc flows in on appear with a fluid ease,
///   • a slow ripple expands off the ring and dissolves, like a droplet,
///   • the dot at the arc's leading tip breathes gently,
///   • the numeral dips briefly when fresh data lands (`pulse`).
/// At "Arr" the ring switches to a closed, breathing arrival state — a maxed
/// -out countdown arc is indistinguishable from a frozen one.
/// Reduce Motion disables the flow, ripple and breathing; the dip is data.
struct SoftCountdownRing: View {
    var sec: Int
    /// Unit line under an "Arr" label ("now", "35 m walk", …).
    var unitWhenArr: String = "now"
    /// Caller-driven freshness dip (bind to a lastRefresh onChange).
    var pulse: Bool = false
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var breathing = false

    private var frac: Double { max(0.08, min(1, 1 - Double(sec) / 900)) }
    private var label: String { fmtETA(sec).big }
    /// The bus is here. A countdown ring has nothing left to count, so this
    /// is a different STATE, not the last frame of the animation — see the
    /// arrival branch in `body`.
    private var arrived: Bool { label == "Arr" }

    var body: some View {
        ZStack {
            if !reduceMotion {
                // Two staggered ripples read as water; one alone read as a
                // radar blip (owner 2026-07-25: "better visuals").
                SoftRipple()
                SoftRipple(delay: 1.3)
            }
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 7)

            if arrived {
                // At "Arr" the countdown ring used to simply max out: a
                // complete circle with the tip dot parked at 12 o'clock,
                // motionless for as long as LTA keeps reporting 0 — which
                // reads as a hung animation, not as "the bus is here" (owner
                // 2026-07-25, "Arr would cause the animation to be stuck").
                //
                // Arrival gets its own resting state instead: a closed ring
                // that breathes. Nothing is travelling, so there's no tip dot
                // and no arc tail — the ring is whole because the wait is
                // over, and the breathing says it's still live.
                Circle()
                    .stroke(Color.white, lineWidth: 8)
                    .opacity(breathing ? 1 : 0.72)
                    .scaleEffect(breathing ? 1.02 : 0.98)
            } else {
                // The arc fades in from its tail to a solid tip — the bright
                // end IS the countdown's leading edge, so the eye lands there.
                // Gradient angles live in the shape's PRE-rotation frame: the
                // trim runs 0°→frac·360°, then the -90° rotationEffect moves
                // the whole thing to start at 12 o'clock. (Declaring the
                // gradient from -90° double-applied the offset — the bright
                // end sat 90° away from the real arc tip and the tip dot
                // looked like a stray floating dot; owner bug 2026-07-25.)
                Circle().trim(from: 0, to: appeared ? frac : 0)
                    .stroke(AngularGradient(colors: [.white.opacity(0.45), .white],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(frac * 360)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(SoftMotion.flow, value: frac)
                // Leading-tip dot: marks how far along the countdown is (it
                // rides the end of the arc) and breathes like a surface
                // bobbing on water.
                Circle().fill(.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: .white.opacity(0.9), radius: breathing ? 5 : 2)
                    .scaleEffect(breathing ? 1.35 : 1)
                    .offset(y: -47)
                    .rotationEffect(.degrees((appeared ? frac : 0) * 360))
                    .animation(SoftMotion.flow, value: frac)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                Text(label)
                    .font(ws.sans(arrived ? 22 : 26, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .opacity(pulse ? 0.5 : 1)
                Text(arrived ? unitWhenArr : "min")
                    .font(ws.sans(10, weight: .semibold)).opacity(0.85)
            }
        }
        .frame(width: 94, height: 94)
        // Counting-down → arrived is a state change, so it eases like every
        // other one rather than cutting between two different rings.
        .animation(reduceMotion ? nil : SoftMotion.flow, value: arrived)
        .onAppear {
            if reduceMotion { appeared = true; return }
            withAnimation(SoftMotion.settle) { appeared = true }
            withAnimation(SoftMotion.breathe) { breathing = true }
        }
    }
}

/// The ring's ambient live tell: a soft circle that swells outward off the
/// ring and dissolves — a droplet ripple. Two instances at offset delays
/// layer into a continuous water surface.
private struct SoftRipple: View {
    var delay: Double = 0
    @State private var out = false
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.6), lineWidth: 2)
            .scaleEffect(out ? 1.42 : 1.0)
            .opacity(out ? 0 : 0.45)
            .onAppear {
                withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)
                    .delay(delay)) {
                    out = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// White rounded-14 icon button (header chrome: search, map, back, star…).
struct SoftIconButton: View {
    let glyph: WSGlyph
    var label: String
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            WSIcon(glyph: glyph, size: 15, color: tint ?? SoftBlue.ink.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(SoftBlue.card,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: SoftBlue.shadow, radius: 6, y: 3)
                .frame(width: 44, height: 44)   // 44pt hit area overhangs the 40pt tile
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .frame(width: 40, height: 40)   // layout stays tile-sized
        .accessibilityLabel(label)
    }
}
