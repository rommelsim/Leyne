// Canonical pinned card + its parts — ported from cards.jsx.

import SwiftUI

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
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        let eta = fmtETA(s.etaSec)
        let eta2 = fmtETA(s.followingSec)
        let arriving = eta.live

        HStack(spacing: 12) {
            Text(s.no)
                .font(t.mono(18, weight: .bold))
                .foregroundStyle(t.fg)
                .frame(minWidth: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("→ \(s.dest)")
                    .font(t.sans(13))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LoadDotLabel(load: s.load, t: t)
                    DeckChip(deck: s.deck, t: t)
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
                    Text(eta.small).font(t.mono(10)).foregroundStyle(t.dim)
                }
                Text("then \(eta2.big)\(eta2.big == "Arr" ? "" : "m")")
                    .font(t.mono(10)).foregroundStyle(t.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(arriving ? t.liveBg : .clear)
        .overlay(alignment: .leading) {
            if arriving {
                Capsule().fill(t.live).frame(width: 3).padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?(s.no) }
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

    @State private var exiting = false
    @State private var appeared = false

    private var tracked: [Service] {
        hiddenServices.isEmpty ? card.services
            : card.services.filter { !hiddenServices.contains($0.no) }
    }
    private var visible: [Service] { tracked.sorted { $0.etaSec < $1.etaSec } }
    private var shown: [Service] { Array(visible.prefix(3)) }
    private var overflow: Int { visible.count - shown.count }
    private var hiddenCount: Int { card.services.count - tracked.count }
    private var anyArriving: Bool { visible.contains { $0.etaSec <= 60 } }

    private func handlePin() {
        if pinned {
            withAnimation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.36)) { exiting = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { onPin() }
        } else { onPin() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // HEADER
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 8) {
                        PinTag(label: card.label, t: t, onRename: onRename)
                        Text("· STOP \(card.stopCode)")
                            .font(t.mono(10)).foregroundStyle(t.dim.opacity(0.7))
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if anyArriving { PulseDot(color: t.live) }
                        PinButton(pinned: pinned, t: t, action: handlePin)
                    }
                }
                Text(card.stopName)
                    .font(t.sans(17, weight: .semibold))
                    .foregroundStyle(t.fg)
                HStack(spacing: 8) {
                    if card.walkMin > 0 { WalkChip(mins: card.walkMin, t: t) }
                    if hiddenCount > 0 {
                        Text("Tracking \(visible.count)/\(card.services.count)")
                            .font(t.mono(10)).foregroundStyle(t.dim)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(t.line, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            // SERVICE ROWS
            if visible.isEmpty {
                Text("All services hidden — tap to manage")
                    .font(t.sans(12)).italic()
                    .foregroundStyle(t.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .overlay(alignment: .top) { Divider().background(t.line) }
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider().overlay(t.line) }
                    ServiceRow(s: s, t: t) { onOpen($0) }
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
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isNew ? t.live : (anyArriving ? t.live : t.line), lineWidth: 1)
        )
        .shadow(color: isNew ? t.live.opacity(0.1) : (anyArriving ? t.live.opacity(0.12) : .black.opacity(0.02)),
                radius: anyArriving || isNew ? 14 : 1, y: anyArriving || isNew ? 8 : 1)
        // Entrance is additive only — the card is always visible. A genuinely
        // new card gets a subtle intro; it never gates whether it shows
        // (e.g. when inserted while the Home tab was off-screen).
        .opacity(exiting ? 0 : 1)
        .scaleEffect(exiting ? 0.97 : ((isNew && !appeared) ? 0.94 : 1))
        .offset(x: exiting ? 36 : 0, y: (isNew && !appeared) ? -16 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if !exiting { onOpen(nil) } }
        .onAppear {
            if isNew {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            }
        }
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
