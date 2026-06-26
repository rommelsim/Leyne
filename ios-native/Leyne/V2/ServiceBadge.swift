// Service-number badge — accent-filled rounded square showing a bus
// service number ("80", "158", "21A"). Three sizes used across the
// Soft prototype: sm (36), md (44–48), lg (52–56). Width adapts to
// fit longer service strings (e.g. "21A").

import SwiftUI

enum ServiceBadgeSize {
    case sm, md, lg

    var dim: CGFloat {
        switch self {
        case .sm: return 36
        case .md: return 48
        case .lg: return 52
        }
    }
    var radius: CGFloat {
        switch self {
        case .sm: return 10
        case .md: return 14
        case .lg: return 16
        }
    }
    var font: CGFloat {
        switch self {
        case .sm: return 14
        case .md: return 18
        case .lg: return 22
        }
    }
}

struct ServiceBadge: View {
    let svc: String
    let t: Theme
    var size: ServiceBadgeSize = .md
    /// When true, badge is filled inverted (surface bg, accent text).
    /// Used inside route timeline "BUS {svc}" chips that sit on accent.
    var inverted: Bool = false

    var body: some View {
        // Indigo accent badge (was stark black/white) — softer and cohesive with
        // the indigo map pins + app accent.
        let fill = inverted ? t.surface : t.meBlue
        let fg = inverted ? t.meBlue : Color.white
        Text(svc)
            .font(t.sans(size.font, weight: .semibold))
            .foregroundStyle(fg)
            .frame(minWidth: size.dim, minHeight: size.dim)
            .padding(.horizontal, 6)
            .background(fill, in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
    }
}
