// SoftTabBar — floating Liquid Glass pill with 4 tab icons. Mirrors
// the prototype's tabbar (Home / Nearby / Settings / Search). Pinned
// to the bottom; consumer pads its own ScrollView content so the bar
// doesn't occlude the last row.
//
// SoftBottomBar combines the tab pill with the AdMob banner sitting
// above it — this is what tabbed views (Home / Nearby / Settings)
// actually mount.

import SwiftUI

enum SoftTab: String, CaseIterable {
    case home, nearby, settings, search

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .nearby:   return "location.fill"
        case .settings: return "gearshape.fill"
        case .search:   return "magnifyingglass"
        }
    }
}

struct SoftTabBar: View {
    let t: Theme
    @Binding var selection: SoftTab
    var onSelect: ((SoftTab) -> Void)? = nil

    var body: some View {
        let bar = HStack(spacing: 4) {
            ForEach(SoftTab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                    onSelect?(tab)
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(active ? t.onAccent : t.fg)
                        .frame(width: 56, height: 40)
                        .background(
                            active ? AnyShapeStyle(t.accent)
                                   : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)

        // iOS 26's Liquid Glass replaces the legacy `.regularMaterial`
        // backdrop. `.glassEffect` is the new system primitive — it
        // bends, blurs and refracts the content underneath in a way
        // that the older material can't. We layer a subtle stroke +
        // shadow on top so the bar reads as a distinct floating
        // element even when nothing varied is behind it to refract.
        // Fall back to a translucent surface on iOS 25 and below.
        if #available(iOS 26.0, *) {
            bar
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    t.fg.opacity(t.isDark ? 0.12 : 0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(t.isDark ? 0.35 : 0.10),
                        radius: t.isDark ? 14 : 18,
                        x: 0, y: t.isDark ? 4 : 6)
        } else {
            bar
                .background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(t.surface.opacity(0.4)))
                .overlay(Capsule().stroke(t.line, lineWidth: 1))
                .shadow(color: .black.opacity(t.isDark ? 0.3 : 0.06),
                        radius: t.isDark ? 16 : 20,
                        x: 0, y: t.isDark ? 4 : 6)
        }
    }
}

// MARK: - SoftBottomBar (ad banner + tab pill)

/// Bottom-of-screen composite mounted by every tabbed Soft view. Stacks
/// the AdMob banner above the floating SoftTabBar pill so the ad sits
/// in the same gutter on every screen. The banner self-suppresses when
/// `AdConfig.adsEnabled` is off or `screenshotMode` is on, leaving the
/// tab pill flush with the safe area.
struct SoftBottomBar: View {
    let t: Theme
    @Binding var selection: SoftTab
    var onSelect: ((SoftTab) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            if AdConfig.adsEnabled && !AdConfig.screenshotMode {
                // AdBanner's inner ZStack uses a Color fill that has no
                // intrinsic max-height — left unbounded inside a VStack
                // ⟶ ZStack(alignment: .bottom) chain, it grew to fill
                // the entire screen and pushed the tab pill off the
                // bottom. The explicit 50pt clamp matches the AdMob
                // banner unit's size.
                AdBanner()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12,
                                                style: .continuous))
                    .padding(.horizontal, 16)
            }
            SoftTabBar(t: t, selection: $selection, onSelect: onSelect)
        }
    }
}
