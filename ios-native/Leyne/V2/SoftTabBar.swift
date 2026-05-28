// SoftTabBar — floating Liquid Glass pill with 4 tab icons. Mirrors
// the prototype's tabbar (Home / Nearby / Settings / Search). Pinned
// to the bottom; consumer pads its own ScrollView content so the bar
// doesn't occlude the last row.

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
        HStack(spacing: 4) {
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
        .background(
            ZStack {
                if #available(iOS 26.0, *) {
                    Capsule().fill(.regularMaterial)
                } else {
                    Capsule().fill(t.surface.opacity(0.94))
                }
            }
        )
        .overlay(Capsule().stroke(t.line, lineWidth: 1))
        .shadow(color: .black.opacity(t.isDark ? 0.3 : 0.06),
                radius: t.isDark ? 16 : 20,
                x: 0, y: t.isDark ? 4 : 6)
    }
}
