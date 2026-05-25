// Canonical pinned card + its parts — ported from cards.jsx.

import SwiftUI

/// Tap-press scale for content-shaped buttons (service rows, hero card,
/// large hit targets). Keeps native accessibility/voice-over intact while
/// adding the ~2% "yield under finger, spring back" response that iOS users
/// expect on a tappable surface. Used everywhere a row or card-sized region
/// is the primary tap target.
struct PressableRowStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.75),
                       value: configuration.isPressed)
    }
}

/// Applies `.draggable` + `.dropDestination` only while `editing` is true.
/// We chose system drag-and-drop over a custom long-press-to-drag gesture
/// because the previous custom approach claimed touches from the parent
/// ScrollView under iOS 26 — blocking the user from scrolling a screen
/// full of pinned cards. The system path is touch-coordinated and only
/// initiates a drag on an intentional long-press.
///
/// `onTargetChange` exposes the `isTargeted` signal so callers can render
/// a drop-position indicator (a mint hairline above the hovered card) —
/// the visual answer to "where will this land if I let go?".
extension View {
    @ViewBuilder
    func reorderable(
        editing: Bool,
        stopCode: String,
        onMove: ((String) -> Void)?,
        onTargetChange: ((Bool) -> Void)? = nil
    ) -> some View {
        if editing {
            self
                .draggable(stopCode)
                .dropDestination(for: String.self) { items, _ in
                    if let source = items.first { onMove?(source) }
                    return true
                } isTargeted: { isTargeting in
                    onTargetChange?(isTargeting)
                }
        } else {
            self
        }
    }
}

// ─── User-named pin badge: pencil + dashed underline, tap to rename ───
struct PinTag: View {
    let label: String
    let t: Theme
    var dark = false
    var onRename: ((String) -> Void)? = nil

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.7)
            if editing {
                TextField("", text: $draft)
                    .focused($focused)
                    .font(t.mono(10))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fixedSize()
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(t.accent).frame(height: 1).offset(y: 3)
                    }
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
            } else {
                Text(label.uppercased())
                    .font(t.mono(10))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill((dark ? Color.white : t.line))
                            .frame(height: 1).offset(y: 3)
                    }
            }
        }
        .tracking(0.8)
        .foregroundStyle(dark ? Color.white.opacity(0.6) : t.dim)
        .contentShape(Rectangle())
        .onTapGesture {
            guard onRename != nil else { return }
            draft = label
            editing = true
            focused = true
        }
    }

    private func commit() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, v != label { onRename?(v) }
        editing = false
    }
}

struct WalkChip: View {
    let mins: Int
    let t: Theme
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk").font(.system(size: 9, weight: .semibold))
            Text("\(mins) min walk").font(t.mono(10))
        }
        .foregroundStyle(t.dim)
    }
}

struct PinButton: View {
    let pinned: Bool
    let t: Theme
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { pressed = false }
            action()
        } label: {
            Image(systemName: pinned ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pinned ? t.accent : t.dim)
                .scaleEffect(pressed ? 0.78 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.5), value: pressed)
        }
        .buttonStyle(.plain)
    }
}

// ─── Service row inside a pinned card ─────────────────────
struct ServiceRow: View {
    let s: Service
    let t: Theme
    /// True when this row is the *primary* bus on its card — the soonest
    /// tracked service. Drives the bookmark marker on the left and the
    /// mint-filled bus badge, the two signals that read together as "this
    /// is the bus that matters at this stop".
    var isPrimary: Bool = false
    /// True only when this row is the primary AND its card is the global
    /// hero (the smallest ETA-walk margin across every saved stop). Adds
    /// the mint row background so the "which bus & when" answer is the
    /// most-solid pixel on screen — Variant B's "filled mint hero".
    var isGlobalHero: Bool = false
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        let eta = fmtETA(s.etaSec)
        let eta2 = fmtETA(s.followingSec)
        let arriving = eta.live
        let heroRow = isPrimary && isGlobalHero

        Button(action: { onTap?(s.no) }) {
            HStack(spacing: 10) {
                // Primary marker — a small filled bookmark, mint accent,
                // mirroring the bookmark on the card header. Non-primary
                // rows reserve the same width so badges line up across
                // the card.
                if isPrimary {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .frame(width: 16, alignment: .center)
                } else {
                    Color.clear.frame(width: 16)
                }

                // Bus number badge — filled. Mint for primary (the loud
                // "this one"), warm near-black for everything else.
                Text(s.no)
                    .font(t.mono(15, weight: .semibold))
                    .foregroundStyle(isPrimary ? t.bg : t.contrastFg)
                    .frame(minWidth: 30, alignment: .center)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(
                        isPrimary ? t.accent : t.contrast,
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("→ \(s.dest)")
                        .font(t.sans(14, weight: .medium))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LoadDotLabel(load: s.load, t: t)
                        if !s.wab {
                            HStack(spacing: 3) {
                                StepUpGlyph(color: t.crit, size: 10)
                                Text("Step-up").font(t.mono(10))
                            }
                            .foregroundStyle(t.crit)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(eta.big)
                            .font(t.mono(eta.big == "Arr" ? 22 : 28, weight: .medium))
                            .foregroundStyle(arriving ? t.live : t.fg)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.easeInOut(duration: 0.35), value: eta.big)
                        Text(eta.small).font(t.mono(10)).foregroundStyle(t.dim)
                    }
                    Text("then \(eta2.big)\(eta2.big == "Arr" ? "" : "m")")
                        .font(t.mono(10)).foregroundStyle(t.dim)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeInOut(duration: 0.35), value: eta2.big)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            // Mint background only on the global-hero primary row. An
            // arriving non-hero row still gets the existing liveBg tint,
            // but the hero takes visual precedence.
            .background(heroRow ? t.liveBg : (arriving ? t.liveBg : .clear))
            .overlay(alignment: .leading) {
                // Mint left-edge pill always wins for arriving rows (it's
                // the loudest "your bus is here" signal). Otherwise the
                // operator stripe gives non-primary rows a quiet identity;
                // primary rows skip the stripe — the bookmark already marks
                // them.
                if arriving { ArrivingPill(t: t) }
                else if !isPrimary { OperatorStripe(op: s.op, t: t) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
    }
}

// Left-edge arriving indicator — slim mint pill, inset so its rounded
// ends read at a glance and the card's curved aesthetic carries through.
struct ArrivingPill: View {
    let t: Theme
    var body: some View {
        Capsule().fill(t.live)
            .frame(width: 4)
            .padding(.vertical, 10)
            .padding(.leading, 6)
    }
}

/// Left-edge operator stripe — same geometry as ArrivingPill but narrower
/// and operator-coloured. Visible only when the row is *not* arriving (mint
/// always wins); below the visual noise floor unless you're scanning a list.
/// SBST red, SMRT silver, TTS yellow, GAS orange-red.
struct OperatorStripe: View {
    let op: BusOperator
    let t: Theme
    var body: some View {
        Capsule().fill(op.stripe(t))
            .frame(width: 3)
            .padding(.vertical, 10)
            .padding(.leading, 6)
            .opacity(op == .unknown ? 0 : 0.85)
    }
}

// ─── Canonical pinned card ────────────────────────────────
struct PinnedCardView: View {
    let card: CardModel
    let t: Theme
    let pinned: Bool
    var isNew = false
    let onOpen: (String?) -> Void
    let onPin: () -> Void
    let onRename: (String) -> Void
    var hiddenServices: Set<String> = []
    /// One-shot first-run hint. When true, overlays a pulsing accent ring
    /// on the bookmark and the rename pencil so a brand-new user discovers
    /// the two non-obvious tap targets. HomeView toggles this on once per
    /// install and auto-dismisses after ~6s.
    var coachmark: Bool = false
    /// This card holds the global primary — the soonest primary bus across
    /// every saved stop. Drives the green border + the mint row background
    /// on the primary's row inside the card. There's exactly one global
    /// hero card per Home render (or none, if no card has a primary).
    var isGlobalHero: Bool = false
    /// Edit mode flag (toggled by the SAVED ROUTES header's Edit button).
    /// When true the card surfaces a drag handle on the right and disables
    /// its tap-to-open behaviour so the handle can claim touches.
    var editing: Bool = false
    /// Called when another card is dropped on this one in edit mode. The
    /// String payload is the *source* card's stopCode; the receiving card
    /// is `self.card`. HomeView wires this to `m.movePin(_:before:)`.
    var onMove: ((String) -> Void)? = nil
    /// User-chosen primary bus for this stop (`Pin.primary`). When nil,
    /// the card auto-picks the soonest-tracked service as primary.
    var userPrimary: String? = nil
    /// Long-press handler invoked from a service row's context menu —
    /// passes the tapped row's bus number, or nil if the user chose
    /// "Clear primary". HomeView wires this to `m.setPrimary(code:busNo:)`.
    var onSetPrimary: ((String?) -> Void)? = nil

    @State private var exiting = false
    @State private var appeared = false
    /// Slow breathing scale while at least one tracked service is arriving.
    /// Composes multiplicatively on top of the entrance/exit scaleEffect —
    /// at rest the card sits at 1.000 ↔ 1.012 over 1.4s. Subtle, but the
    /// arriving card visibly *breathes* on screen, which is the single
    /// most useful "your bus is here" signal we can layer onto the design
    /// without changing the layout.
    @State private var heartbeatOn = false
    /// Drop-target hover state — true while another card is being dragged
    /// over this one in edit mode. Drives the mint hairline indicator that
    /// previews where the drop will land.
    @State private var dropHovering = false

    private var tracked: [Service] {
        hiddenServices.isEmpty ? card.services
            : card.services.filter { !hiddenServices.contains($0.no) }
    }
    private var visible: [Service] { tracked.sorted { $0.etaSec < $1.etaSec } }
    private var shown: [Service] { Array(visible.prefix(3)) }
    private var overflow: Int { visible.count - shown.count }
    private var hiddenCount: Int { card.services.count - tracked.count }
    private var anyArriving: Bool { visible.contains { $0.etaSec <= 60 } }

    /// Resolved primary bus number. Honors the user's explicit choice
    /// (`userPrimary`) when that bus is still visible; otherwise falls
    /// back to the soonest visible service — the implicit answer to
    /// "which bus matters most at this stop right now."
    private var primaryBusNo: String? {
        if let p = userPrimary, visible.contains(where: { $0.no == p }) {
            return p
        }
        return visible.first?.no
    }

    private func handlePin() {
        if pinned {
            withAnimation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.36)) { exiting = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { onPin() }
        } else { onPin() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // HEADER — stop name leads (this is the card's identity), and
            // STOP code · walk · rename pencil sit on one mono subtitle
            // line beneath. The bookmark (pin/unpin) is the only right-side
            // affordance; the live-pulse dot rides next to it for arriving.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.stopName)
                        .font(t.sans(20, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("STOP \(card.stopCode)")
                            .font(t.mono(11))
                            .foregroundStyle(t.dim)

                        if card.walkMin > 0 {
                            Text("·").foregroundStyle(t.dim.opacity(0.5))
                            HStack(spacing: 3) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("\(card.walkMin) min").font(t.mono(11))
                            }
                            .foregroundStyle(t.dim)
                        }

                        Text("·").foregroundStyle(t.dim.opacity(0.5))
                        PinTag(label: card.label, t: t, onRename: onRename)
                            .overlay {
                                if coachmark { CoachmarkRing(color: t.accent) }
                            }

                        if hiddenCount > 0 {
                            Text("·").foregroundStyle(t.dim.opacity(0.5))
                            Text("\(visible.count)/\(card.services.count) tracked")
                                .font(t.mono(10)).foregroundStyle(t.dim)
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if editing {
                        // Drag handle — only visible in edit mode. Native
                        // .draggable/.dropDestination on the whole card
                        // does the heavy lifting; this glyph is a hint
                        // that the card is reorderable.
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(t.dim)
                            .frame(width: 28, height: 28)
                    } else {
                        if anyArriving { PulseDot(color: t.live) }
                        PinButton(pinned: pinned, t: t, action: handlePin)
                            .overlay {
                                if coachmark { CoachmarkRing(color: t.accent) }
                            }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            // SERVICE ROWS
            if visible.isEmpty {
                // "All hidden" used to be a flat italic line — readers
                // skipped it. Now it's structured like a real row with the
                // hidden-count and a clear action verb, so it's obvious why
                // the card looks empty and how to fix it.
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 13)).foregroundStyle(t.dim)
                    Text("\(card.services.count) service\(card.services.count == 1 ? "" : "s") hidden")
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(t.fg)
                    Spacer()
                    Text("Tap to manage")
                        .font(t.mono(10)).foregroundStyle(t.accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .overlay(alignment: .top) { Divider().background(t.line) }
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider().overlay(t.line) }
                    // Primary defers to the user's explicit choice (when
                    // set and still visible); otherwise the soonest tracked
                    // row wins. If this card is also the global hero, the
                    // primary row gets the mint background fill on top.
                    ServiceRow(
                        s: s, t: t,
                        isPrimary: s.no == primaryBusNo,
                        isGlobalHero: isGlobalHero
                    ) { onOpen($0) }
                    // Long-press → "Make primary" / "Clear primary" so the
                    // user can lock in a specific bus and override the
                    // auto-soonest default.
                    .contextMenu {
                        let isUserMarked = userPrimary == s.no
                        Button {
                            onSetPrimary?(isUserMarked ? nil : s.no)
                        } label: {
                            if isUserMarked {
                                Label("Clear primary", systemImage: "bookmark.slash")
                            } else {
                                Label("Make primary", systemImage: "bookmark.fill")
                            }
                        }
                    }
                }
                if overflow > 0 {
                    Button { onOpen(nil) } label: {
                        HStack {
                            Text("+ \(overflow) more \(overflow == 1 ? "service" : "services")")
                                .foregroundStyle(t.dim)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("See all")
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            }.foregroundStyle(t.fg)
                        }
                        .font(t.mono(11))
                        // Extra top room so this hit target clears the bus
                        // timer (ETA) of the service row directly above it.
                        .padding(.horizontal, 16)
                        .padding(.top, 16).padding(.bottom, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Divider().overlay(t.line) }
                }
            }
        }
        .background(t.glassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    // Global hero gets the loudest border — slightly heavier
                    // than the default arriving/new pulses. Falls back to
                    // the existing arriving/new mint, then to the hairline.
                    isGlobalHero ? t.live
                        : (isNew ? t.live : (anyArriving ? t.live : t.line)),
                    lineWidth: isGlobalHero ? 1.6 : 1
                )
        )
        .shadow(
            color: isGlobalHero ? t.live.opacity(0.18)
                : (isNew ? t.live.opacity(0.1)
                : (anyArriving ? t.live.opacity(0.12) : .black.opacity(0.02))),
            radius: (isGlobalHero || anyArriving || isNew) ? 14 : 1,
            y: (isGlobalHero || anyArriving || isNew) ? 8 : 1
        )
        // Entrance is additive only — the card is always visible. A genuinely
        // new card gets a subtle intro; it never gates whether it shows
        // (e.g. when inserted while the Home tab was off-screen).
        .opacity(exiting ? 0 : 1)
        .scaleEffect(exiting ? 0.97 : ((isNew && !appeared) ? 0.94 : 1))
        .scaleEffect(heartbeatOn ? 1.012 : 1)
        .offset(x: exiting ? 36 : 0, y: (isNew && !appeared) ? -16 : 0)
        .contentShape(Rectangle())
        // Tap-to-open is disabled in edit mode so a tap on a card can't
        // accidentally drill into a stop while the user is reordering.
        .onTapGesture { if !exiting && !editing { onOpen(nil) } }
        .reorderable(
            editing: editing,
            stopCode: card.stopCode,
            onMove: onMove,
            onTargetChange: { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    dropHovering = hovering
                }
            }
        )
        // Mint hairline floats just above the card while another card is
        // being dragged over it — a preview of where the drop will land.
        // The overlay is placed AFTER `.clipShape` (above, in the body
        // chain) so the indicator can sit OUTSIDE the card's clip, just
        // above its rounded top edge.
        .overlay(alignment: .top) {
            if editing && dropHovering {
                Capsule()
                    .fill(t.live)
                    .frame(height: 3)
                    .padding(.horizontal, 18)
                    .offset(y: -8)
                    .shadow(color: t.live.opacity(0.45), radius: 4)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if isNew {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            }
            if anyArriving { startHeartbeat() }
        }
        .onChange(of: anyArriving) { _, on in
            if on { startHeartbeat() } else { stopHeartbeat() }
        }
    }

    private func startHeartbeat() {
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            heartbeatOn = true
        }
    }
    private func stopHeartbeat() {
        // A one-shot animation interrupts the repeatForever cleanly, settling
        // the scale back to 1.0 without an abrupt snap.
        withAnimation(.easeInOut(duration: 0.3)) { heartbeatOn = false }
    }
}

// ─── Add bus stop tile ─────────────────────────────────────
struct AddPinTile: View {
    let t: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text("Add a bus stop").font(t.sans(14, weight: .medium))
            }
            .foregroundStyle(t.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(t.line)
            )
        }
        .buttonStyle(.plain)
    }
}
