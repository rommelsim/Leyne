// MapHandoffToast — top-of-screen pill that flashes "Opening Apple Maps…"
// for ~1.6s before the system map app actually opens. Mirrors the proto's
// MapToast (`proto-app.jsx:272-301`). The caller toggles `kind`; this view
// auto-dismisses by setting `kind = .none` after the timeout.

import SwiftUI

enum MapHandoffKind: Equatable {
    case none, apple, google

    var label: String? {
        switch self {
        case .none:   return nil
        case .apple:  return "Opening Apple Maps…"
        case .google: return "Opening Google Maps…"
        }
    }
}

struct MapHandoffToast: View {
    let t: Theme
    @Binding var kind: MapHandoffKind

    var body: some View {
        if let label = kind.label {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text(label)
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.fg)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Capsule().fill(.regularMaterial)
                    } else {
                        Capsule().fill(t.surface.opacity(0.94))
                    }
                }
            )
            .overlay(Capsule().stroke(t.line, lineWidth: 1))
            .shadow(color: .black.opacity(t.isDark ? 0.3 : 0.08),
                    radius: 16, x: 0, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: kind) {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { kind = .none }
            }
        }
    }
}
