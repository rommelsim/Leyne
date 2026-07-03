// Home — hero arrival + compact saved-routes list.
// Ported from Flutter v2.0 lib/screens/home_screen.dart + widgets/home_hero.dart.
//
// Picks the single most-urgent service across all pinned stops (smallest
// `eta - walk` margin) and promotes it to a full-bleed card. The rest flow
// below as compact rows via PinnedCardView. Long-press to reorder; pull to
// refresh; sticky compact header on scroll.

import SwiftUI

// MARK: - Shared atoms used by Home/Nearby/Settings

/// Large title that becomes a sticky compact bar on scroll. Used by Nearby,
/// kept here for other screens that reference it.
struct LargeTitleHeader: View {
    let t: Theme
    let title: String
    let subtitle: String?
    var locationSubtitle = false
    let onRefresh: (() -> Void)?
    let refreshing: Bool
    @Binding var collapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim)
                Spacer()
                Button { onRefresh?() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(refreshing ? 360 : 0))
                            .animation(refreshing ? .linear(duration: 0.7).repeatForever(autoreverses: false) : .default, value: refreshing)
                        Text("LIVE").font(t.mono(11))
                    }
                    .foregroundStyle(t.dim)
                }
                .disabled(onRefresh == nil)
            }
            .padding(.bottom, 14)

            Text(title)
                .font(t.sans(32, weight: .semibold))
                .foregroundStyle(t.fg)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TitleOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY)
                })

            if locationSubtitle {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12, weight: .semibold))
                    Text("Around Bishan")
                    Text("·").opacity(0.5)
                    Text("walking distance")
                }
                .font(t.sans(13)).foregroundStyle(t.dim).padding(.top, 6)
            } else if let s = subtitle {
                Text(s).font(t.sans(14)).foregroundStyle(t.dim).padding(.top, 2)
            }
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
        .onPreferenceChange(TitleOffsetKey.self) { y in
            let c = y < -12
            if c != collapsed { collapsed = c }
        }
    }
}

// MARK: - Preference keys (used by Home + Nearby + Settings)

struct TitleOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct StickyCompactBar: View {
    let t: Theme
    let title: String
    var trailing: AnyView
    let visible: Bool
    var body: some View {
        HStack {
            Text(title).font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg)
            Spacer()
            trailing
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        // Glass on iOS 26 so this bar reads as system chrome floating over
        // the content (matching the tab bar's vocabulary). The glass MUST
        // extend through the top safe area (`ignoresSafeArea(edges: .top)`),
        // otherwise scrolled cards peek into the gap between the status
        // bar and the chrome — the bleed-through bug. iOS's native nav
        // bars frost the safe area too; we mirror that.
        .background(
            t.glassSurface().ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(visible ? t.line : .clear).frame(height: 1)
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -6)
        .animation(.easeInOut(duration: 0.22), value: visible)
        .allowsHitTesting(visible)
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Environment(AppModel.self) var m: AppModel
    @Environment(DataStore.self) var store: DataStore
    @State private var collapsed = false
    @State private var refreshing = false
    @State private var pullY: CGFloat = 0
    @State private var pullArmed = true
    /// Edit mode toggled by the SAVED ROUTES header's Edit/Done button.
    /// When true, each card surfaces a drag handle so the user can reorder
    /// pins via SwiftUI's native draggable/dropDestination — chosen over a
    /// long-press-and-drag gesture because the earlier attempt at that
    /// pattern stole touches from the parent ScrollView under iOS 26.
    @State private var editing = false
    @State private var dragSource: String? = nil
    /// One-shot stagger flag for the saved-routes list. Flips to true on
    /// first appear so each card fades + rises with a small per-index
    /// delay. Stays true across tab switches so re-entering Home doesn't
    /// re-trigger the animation.
    @State private var savedRoutesEntered = false

    // ─── First-run coachmark ──────────────────────────────────
    // Two hidden tap targets in the saved-routes list are not obvious to
    // a brand-new user: the rename pencil on each card's label, and the
    // bookmark that toggles tracking. We pulse both on the first saved
    // card the first time Home is opened with at least one pin. Auto-
    // dismisses after a short window — the goal is a glance, not a tour.
    @AppStorage("leyne.coachmark.home.shown") private var coachmarkShown = false
    @State private var coachmarkActive = false

    private var t: Theme { m.t }

    private var cards: [CardModel] { m.allPinnedCards }

    /// Cards with at least one visible (non-hidden) service. Filtered like Flutter.
    private var visibleCards: [CardModel] {
        cards.filter { c in
            let hidden = m.hiddenSet(code: c.stopCode, allNos: c.services.map(\.no))
            return c.services.contains(where: { !hidden.contains($0.no) })
        }
    }

    /// The (card, service) pair holding the global primary — the bus with
    /// the smallest `etaMin - walkMin` margin *among each card's primary*.
    /// Each card's primary mirrors PinnedCardView.primaryBusNo: the user's
    /// explicit `pin.primary` when set and still visible, otherwise the
    /// soonest tracked service. Stale entries (etaSec >= 3600) are skipped.
    private var heroPick: (card: CardModel, service: Service)? {
        var best: (CardModel, Service)? = nil
        var bestMargin = Int.max
        for c in visibleCards {
            let hidden = m.hiddenSet(code: c.stopCode, allNos: c.services.map(\.no))
            let visible = c.services
                .filter { !hidden.contains($0.no) && $0.etaSec < 3600 }
                .sorted { $0.etaSec < $1.etaSec }
            let userPrimary = m.pin(forCode: c.stopCode)?.primary
            let primary: Service?
            if let up = userPrimary, let s = visible.first(where: { $0.no == up }) {
                primary = s
            } else {
                primary = visible.first
            }
            guard let p = primary else { continue }
            let margin = (p.etaSec / 60) - c.walkMin
            if margin < bestMargin {
                bestMargin = margin
                best = (c, p)
            }
        }
        return best
    }

    /// The stopCode of the card holding the global primary — i.e. the
    /// card whose soonest-tracked service has the smallest "leave in"
    /// margin across every saved stop. Drives the `isGlobalHero` flag on
    /// PinnedCardView. Nil means no candidate (all empty / stale).
    private var globalHeroCode: String? { heroPick?.card.stopCode }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: PullKey.self,
                                value: geo.frame(in: .named("scroll")).minY)
                        })

                    header

                    if case .error(let msg) = store.referenceState, m.pins.isEmpty {
                        errorCard(msg)
                    } else if m.pins.isEmpty {
                        emptyState
                    } else if !visibleCards.isEmpty {
                        // Variant B "Smart Hero" — the giant LEAVE NOW card
                        // is gone; the hero treatment is now folded into
                        // each saved card. The card holding the soonest
                        // primary across all stops gets a louder border +
                        // mint background on its primary row, so the answer
                        // to "which bus & when" is still unmissable but
                        // doesn't duplicate a whole row of information.
                        savedRoutesHeader
                        reorderableCards.padding(.horizontal, 16).padding(.bottom, 24)
                    }

                    Text("LEYNE · v\(versionShort)")
                        .font(t.mono(10)).tracking(1).foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16).padding(.bottom, 8)
                }
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(PullKey.self) { y in
                let p = max(0, y)
                pullY = p
                if p > 80, pullArmed, !refreshing {
                    pullArmed = false
                    refresh()
                }
                if p < 6 { pullArmed = true }
            }
            .overlay(alignment: .top) { pullIndicator }

            StickyCompactBar(t: t, title: "Home",
                trailing: AnyView(liveTimeChip(short: true)),
                visible: collapsed)
        }
        .background(t.bg.ignoresSafeArea())
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Home")
                .font(t.sans(28, weight: .semibold))
                .foregroundStyle(t.fg)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TitleOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY)
                })
            Spacer()
            liveTimeChip(short: false)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .onPreferenceChange(TitleOffsetKey.self) { y in
            let c = y < -12
            if c != collapsed { collapsed = c }
        }
    }

    /// Freshness across all pinned stops — the newest successful arrival
    /// fetch decides whether we render the chip as live/stale/offline.
    private var freshness: Freshness {
        Freshness.from(store.newestRefresh(amongst: m.pins.map(\.code)))
    }

    private func liveTimeChip(short: Bool) -> some View {
        let label = formattedTime(date: Date(), use24h: m.use24h)
        let f = freshness
        let statusLabel = (f == .live) ? "LIVE" : f.label
        return HStack(spacing: 8) {
            // Dot colour follows the freshness state — green = live (<30s),
            // amber = stale (30s–5min), red = offline (>5min or error).
            // The shadow is only applied for the live state so a stale chip
            // doesn't read as a confident "live" signal.
            Circle().fill(f.color(t)).frame(width: 7, height: 7)
                .shadow(color: f == .live ? t.live.opacity(0.55) : .clear, radius: 4)
            Text(short ? statusLabel : "\(statusLabel) · \(label)")
                .font(t.mono(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(t.dim)
        }
        // The AppModel `tick` updates every second; binding to it forces the
        // chip to re-render on each tick so the timestamp + freshness stay
        // current without subscribing to the lastFetched dictionary.
        .id(m.tick / 5)
    }

    private var savedRoutesHeader: some View {
        HStack {
            // Count rides next to the label so the user can see at a glance
            // how many stops they're tracking — a small literacy boost over
            // the previous static "SAVED ROUTES" string.
            Text("SAVED ROUTES · \(visibleCards.count)")
                .font(t.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.dim)
            Spacer()
            Button {
                editing.toggle()
                Feedback.shared.tap()
            } label: {
                Text(editing ? "Done" : "Edit")
                    .font(t.sans(13, weight: editing ? .semibold : .medium))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(PressableRowStyle(scale: 0.94))
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    }

    @ViewBuilder private var pullIndicator: some View {
        Group {
            if refreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(t.dim)
            } else if pullY > 4 {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(t.dim)
                    .rotationEffect(.degrees(pullY > 80 ? 180 : 0))
                    .opacity(min(1, Double(pullY) / 50))
                    .animation(.easeOut(duration: 0.18), value: pullY > 80)
            }
        }
        .offset(y: refreshing ? 8 : min(max(0, pullY - 26), 28))
        .animation(.easeOut(duration: 0.2), value: refreshing)
    }

    // MARK: empty + error states

    private var emptyState: some View {
        VStack(spacing: 14) {
            // A larger, on-brand glyph — bookmark with a subtle accent ring
            // — reads as the empty state of a *pinning* surface, not a
            // generic empty list.
            ZStack {
                Circle().fill(t.accent.opacity(0.10)).frame(width: 64, height: 64)
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(t.accent)
            }
            VStack(spacing: 6) {
                Text("Nothing pinned yet")
                    .font(t.sans(17, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text("Pin a stop from Nearby or Search and its live arrivals show up here — even when the app is closed.")
                    .font(t.sans(13)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { m.setTab(.nearby) } label: {
                    Label("Nearby", systemImage: "location.fill")
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(t.bg)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(PressableRowStyle(scale: 0.96))
                Button { m.searchOpen = true } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(t.fg)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .overlay(Capsule().stroke(t.line, lineWidth: 1))
                }
                .buttonStyle(PressableRowStyle(scale: 0.96))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64).padding(.horizontal, 24)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(t.crit.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(t.crit)
            }
            VStack(spacing: 4) {
                Text("Can't reach LTA right now")
                    .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
                Text(msg)
                    .font(t.sans(11)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text("Your pins and recent searches are safe — we'll keep retrying in the background.")
                    .font(t.sans(11)).foregroundStyle(t.dim.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await store.bootstrap() } } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.bg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(PressableRowStyle(scale: 0.96))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 18)
        .background(t.glassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.line, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // MARK: pinned cards
    //
    // Reorder via long-press+drag was removed because the SwiftUI gesture
    // chain (LongPress.sequenced(before: DragGesture)) claims touches on
    // every card and blocks the parent ScrollView's pan in iOS 26's
    // compositor — users couldn't scroll a screen filled with pinned
    // stops. Reorder can come back via a dedicated drag handle or an
    // Edit mode; tap-to-rename and the bookmark pin/unpin still work.

    private var reorderableCards: some View {
        VStack(spacing: 12) {
            ForEach(Array(visibleCards.enumerated()), id: \.element.id) { i, card in
                PinnedCardView(
                    card: card, t: t,
                    pinned: m.isPinned(card.stopCode),
                    isNew: card.stopCode == m.recentlyAddedId,
                    onOpen: { busNo in m.open(card, busNo: busNo) },
                    onPin: { m.togglePin(code: card.stopCode) },
                    onRename: { m.rename(code: card.stopCode, to: $0) },
                    hiddenServices: m.hiddenSet(code: card.stopCode,
                                                allNos: card.services.map(\.no)),
                    // Coachmark goes on the first card. Pulsing every card
                    // would scream; one example is enough.
                    coachmark: coachmarkActive && i == 0,
                    // The card holding the soonest primary lights up.
                    isGlobalHero: card.stopCode == globalHeroCode,
                    editing: editing,
                    onMove: { source in
                        // Wrap the array mutation in withAnimation so
                        // SwiftUI interpolates the per-card move via the
                        // ForEach's identity matching — the cards slide
                        // into their new positions instead of snapping.
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            m.movePin(source, before: card.stopCode)
                        }
                    },
                    userPrimary: m.pin(forCode: card.stopCode)?.primary,
                    onSetPrimary: { busNo in
                        m.setPrimary(code: card.stopCode, busNo: busNo)
                    }
                )
                // Staggered entrance — each card fades + rises with a 60ms
                // per-index delay, capped at 7 slots so a long list still
                // finishes inside ~0.8s. Fires only on first appearance
                // (savedRoutesEntered guard).
                .opacity(savedRoutesEntered ? 1 : 0)
                .offset(y: savedRoutesEntered ? 0 : 14)
                .animation(.easeOut(duration: 0.42)
                                .delay(0.06 * Double(min(i, 7))),
                           value: savedRoutesEntered)

                // Primary-marking hint — printed under the first card
                // during the coachmark window so users discover the long-
                // press → "Make primary" action. Auto-dismisses with the
                // rest of the coachmark; never shown again afterwards.
                if i == 0 && coachmarkActive {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 11))
                        Text("Long-press any row to make it your primary")
                            .font(t.mono(11))
                    }
                    .foregroundStyle(t.dim)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            if !savedRoutesEntered { savedRoutesEntered = true }
            maybeStartCoachmark()
        }
    }

    /// Triggers the first-run coachmark exactly once. Fires only when
    /// there's a saved card to point *at* (so the pulse has somewhere to
    /// land), waits a brief beat so the staggered entrance lands first,
    /// then auto-dismisses after a glance window. The AppStorage flag
    /// makes the decision idempotent across launches.
    private func maybeStartCoachmark() {
        guard !coachmarkShown, !visibleCards.isEmpty, !coachmarkActive else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.4)) { coachmarkActive = true }
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.easeIn(duration: 0.3)) { coachmarkActive = false }
            coachmarkShown = true
        }
    }

    private func refresh() {
        Feedback.shared.tap()
        withAnimation { refreshing = true }
        for p in m.pins { store.ensureArrivals(stop: p.code, force: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation { refreshing = false }
        }
    }

    // MARK: helpers

    private var versionShort: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    fileprivate func formattedTime(date: Date, use24h: Bool) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let mm = String(format: "%02d", minute)
        if use24h {
            return "\(String(format: "%02d", hour)):\(mm)"
        }
        let h12 = ((hour + 11) % 12) + 1
        return "\(h12):\(mm) \(hour < 12 ? "am" : "pm")"
    }
}

// MARK: - HomeHeroCard

struct HomeHeroCard: View {
    let card: CardModel
    let service: Service
    let t: Theme

    var body: some View {
        let etaMin = service.etaSec / 60
        let followingMin = service.followingSec / 60
        let walk = card.walkMin

        let leaveIn = etaMin - walk
        let leaveLabel = leaveIn <= 1 ? "Leave now" : "Leave in \(leaveIn) min"
        let walkLabel = walk > 0 ? "\(walk) min walk" : "At the stop"

        let etaBig = etaMin <= 0 ? "Arr" : "\(etaMin)"
        let etaUnit = etaMin <= 0 ? "now" : "min"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                leftBlock(leaveLabel: leaveLabel, walkLabel: walkLabel)
                Spacer(minLength: 0)
                rightBlock(big: etaBig, unit: etaUnit, next: followingMin)
            }
            // The previous design stacked load/wheelchair/deck chips beneath
            // a divider here. Those are reference data, not the hero signal —
            // tapping the card opens DetailView which shows all of it. A
            // commuter glancing at this card for 0.4 seconds only needs to
            // decide "go now or not yet?", so we make that the only message.
        }
        .padding(18)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.lineHi, lineWidth: 1))
    }

    /// Hero card surface — routes through the shared `glassSurfaceHi()`
    /// helper so the whole app reaches Liquid Glass through a single source
    /// of truth. iOS 18–25 fall back to the opaque elevated tea tone.
    @ViewBuilder
    private var heroBackground: some View {
        t.glassSurfaceHi()
    }

    private func leftBlock(leaveLabel: String, walkLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(leaveLabel) · \(walkLabel)".uppercased())
                .font(t.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.dim)
            HStack(alignment: .center, spacing: 10) {
                busChip(service.no)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.dest)
                        .font(t.sans(17, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    Text("\(card.label.uppercased()) · STOP \(card.stopCode)")
                        .font(t.mono(11)).tracking(0.6)
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
            }
        }
    }

    private func rightBlock(big: String, unit: String, next: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(big)
                    .font(.system(size: big == "Arr" ? 40 : 54, weight: .semibold,
                                  design: .monospaced))
                    .tracking(-1.2)
                    .foregroundStyle(t.accent)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.4), value: big)
                Text(unit)
                    .font(t.mono(14))
                    .foregroundStyle(t.accent)
            }
            Text(next > 0 ? "arriving · then \(next)" : "arriving")
                .font(t.mono(11)).foregroundStyle(t.dim)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.4), value: next)
        }
    }

    private func busChip(_ no: String) -> some View {
        Text(no)
            .font(t.mono(15, weight: .semibold))
            .foregroundStyle(t.bg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(t.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
