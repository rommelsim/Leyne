// Home tab — pinned cards (long-press to reorder), Add tile, tips, footer.
// Header uses the iOS large-title → sticky-compact pattern on scroll.

import SwiftUI

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

struct TitleOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Top-of-scroll overscroll offset, for the custom pull-to-refresh.
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
        .background(t.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(visible ? t.line : .clear).frame(height: 1)
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -6)
        .animation(.easeInOut(duration: 0.22), value: visible)
        .allowsHitTesting(visible)
    }
}

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var collapsed = false
    @State private var refreshing = false
    @State private var dragId: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var overIndex: Int? = nil
    @State private var dragSnapshot: [CardModel]? = nil
    @State private var pullY: CGFloat = 0
    @State private var pullArmed = true

    private var t: Theme { m.t }
    // While reordering, render from a frozen snapshot so pointer-move events
    // don't rebuild every card (stopName/walkMin/liveServices) per frame.
    private var cards: [CardModel] {
        if dragId != nil, let snap = dragSnapshot { return snap }
        return m.allPinnedCards
    }

    private func refresh() {
        Feedback.shared.tap()
        withAnimation { refreshing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation { refreshing = false }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: PullKey.self,
                                value: geo.frame(in: .named("scroll")).minY)
                        })

                    LargeTitleHeader(t: t, title: "Home", subtitle: "Updated moments ago",
                                     onRefresh: refresh, refreshing: refreshing,
                                     collapsed: $collapsed)

                    sectionLabel("PINNED", hint: m.pins.isEmpty ? nil : "hold to reorder · tap label to rename")

                    pinnedSection

                    AddPinTile(t: t) { m.showAdd = true }
                        .padding(.horizontal, 16).padding(.top, 12)

                    sectionLabel("TIPS")
                    tipCard.padding(.horizontal, 16).padding(.bottom, 12)

                    Text("LYNE · BETA · v0.4")
                        .font(t.mono(10)).tracking(1).foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16).padding(.bottom, 8)
                }
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "scroll")
            // Only locked while a card is actually picked up for reorder;
            // normal touches scroll freely (gesture is simultaneous).
            .scrollDisabled(dragId != nil)
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
                trailing: AnyView(
                    Button { refresh() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .bold))
                            Text("LIVE").font(t.mono(10))
                        }.foregroundStyle(t.dim)
                    }),
                visible: collapsed)
        }
        .background(t.bg.ignoresSafeArea())
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

    private func sectionLabel(_ text: String, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(t.mono(10)).tracking(1.4).foregroundStyle(t.dim)
            Spacer()
            if let h = hint {
                Text(h).font(t.mono(10)).foregroundStyle(t.dim.opacity(0.7))
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var tipCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(t.accent.opacity(0.13))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "bell").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Let the phone tell you").font(t.sans(13, weight: .medium)).foregroundStyle(t.fg)
                Text("Cards will buzz when your bus is 2 minutes away. Stop refreshing.")
                    .font(t.sans(11)).foregroundStyle(t.dim).lineSpacing(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
    }

    // ─── Pinned section: empty / error / cards ────────────
    @ViewBuilder private var pinnedSection: some View {
        if case .error(let msg) = store.referenceState, m.pins.isEmpty {
            errorCard(msg)
        } else if m.pins.isEmpty {
            emptyState
        } else {
            reorderableCards.padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 26, weight: .light)).foregroundStyle(t.dim)
            Text("No pinned stops yet")
                .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
            Text("Pin a stop from Nearby or Search and its live arrivals show up here.")
                .font(t.sans(12)).foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
            Button { m.setTab(.nearby) } label: {
                Text("Browse Nearby")
                    .font(t.sans(13, weight: .medium)).foregroundStyle(t.bg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 24)
        .padding(.horizontal, 16)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24)).foregroundStyle(t.crit)
            Text("Couldn’t load live data").font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
            Text(msg).font(t.sans(11)).foregroundStyle(t.dim).multilineTextAlignment(.center)
            Button { Task { await store.bootstrap() } } label: {
                Text("Retry").font(t.sans(13, weight: .medium)).foregroundStyle(t.bg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(t.accent, in: Capsule())
            }.buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // ─── Long-press to reorder ────────────────────────────
    private var reorderableCards: some View {
        let ids = cards.map(\.id)
        return VStack(spacing: 12) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                let isDragging = card.id == dragId
                let shift = shiftFor(index: idx, ids: ids)
                PinnedCardView(
                    card: card, t: t,
                    pinned: m.isPinned(card.stopCode),
                    isNew: card.stopCode == m.recentlyAddedId,
                    onOpen: { busNo in m.open(card, busNo: busNo) },
                    onPin: { m.togglePin(code: card.stopCode) },
                    onRename: { m.rename(code: card.stopCode, to: $0) },
                    hiddenServices: m.hiddenSet(code: card.stopCode,
                                                allNos: card.services.map(\.no))
                )
                .scaleEffect(isDragging ? 1.03 : 1)
                .rotationEffect(.degrees(isDragging ? -1 : 0))
                .offset(y: isDragging ? dragOffset : CGFloat(shift) * 96)
                .zIndex(isDragging ? 20 : 0)
                .shadow(color: isDragging ? .black.opacity(0.22) : .clear,
                        radius: isDragging ? 18 : 0, y: 12)
                .animation(isDragging ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24),
                           value: overIndex)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.38)
                        .onEnded { _ in
                            Feedback.shared.select()
                            dragSnapshot = m.allPinnedCards
                            dragId = card.id
                            overIndex = idx
                        }
                        .sequenced(before: DragGesture())
                        .onChanged { value in
                            if case .second(true, let drag?) = value {
                                dragOffset = drag.translation.height
                                let step = Int((drag.translation.height / 108).rounded())
                                overIndex = max(0, min(ids.count - 1, idx + step))
                            }
                        }
                        .onEnded { _ in commitReorder(ids: ids) }
                )
            }
        }
    }

    private func shiftFor(index idx: Int, ids: [String]) -> Int {
        guard let dragId, let over = overIndex,
              let from = ids.firstIndex(of: dragId), from != idx else { return 0 }
        if from < idx && idx <= over { return -1 }
        if from > idx && idx >= over { return 1 }
        return 0
    }

    private func commitReorder(ids: [String]) {
        defer {
            dragId = nil; dragOffset = 0; overIndex = nil; dragSnapshot = nil
        }
        guard let dragId, let over = overIndex,
              let from = ids.firstIndex(of: dragId), from != over else { return }
        var next = ids
        let moved = next.remove(at: from)
        next.insert(moved, at: over)
        Feedback.shared.success()
        m.reorderPins(next)
    }
}
