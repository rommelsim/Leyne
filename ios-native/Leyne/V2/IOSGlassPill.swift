// IOSGlassPill — backdrop-blurred pill used for the floating tab bar
// and for top-bar back/pin pills on Stop / Bus / Search screens. On
// iOS 26 lifts to Liquid Glass; on earlier iOS falls back to a tinted
// surface fill.

import SwiftUI

struct IOSGlassPill<Content: View>: View {
    let t: Theme
    let content: Content

    init(t: Theme, @ViewBuilder _ content: () -> Content) {
        self.t = t
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    if #available(iOS 26.0, *) {
                        Rectangle().fill(.regularMaterial)
                    } else {
                        t.surface.opacity(0.92)
                    }
                }
                    .clipShape(Capsule())
            )
            .overlay(
                Capsule().stroke(t.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(t.isDark ? 0.3 : 0.06),
                    radius: t.isDark ? 16 : 20,
                    x: 0, y: t.isDark ? 4 : 6)
    }
}

/// Top-bar back/pin pill used on Stop / Bus screens.
struct GlassPillButton: View {
    let t: Theme
    let icon: String
    let label: String
    /// When non-nil, the button is rendered as filled accent (e.g. pinned).
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(t.sans(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(filled ? t.onAccent : t.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Group {
                    if filled {
                        Capsule().fill(t.accent)
                    } else {
                        if #available(iOS 26.0, *) {
                            Capsule().fill(.regularMaterial)
                        } else {
                            Capsule().fill(t.surface.opacity(0.92))
                        }
                    }
                }
            )
            .overlay(
                Capsule().stroke(filled ? Color.clear : t.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
