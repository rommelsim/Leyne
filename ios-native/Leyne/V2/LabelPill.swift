// LabelPill — small "Home" / "Work" / "Gym" / "Class" chip on pinned
// stop cards. Two variants per the Soft prototype: solid accent on the
// hero card; tinted accent (accentTint bg, accent fg) on secondary
// grid cards.

import SwiftUI

struct LabelPill: View {
    let text: String
    let t: Theme
    var variant: Variant = .solid

    enum Variant { case solid, tinted }

    var body: some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(variant == .solid ? t.onAccent : t.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                variant == .solid ? t.accent : t.liveBg,
                in: Capsule()
            )
    }
}
