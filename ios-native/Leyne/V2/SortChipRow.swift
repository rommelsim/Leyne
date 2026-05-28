// SortChipRow — single-selection pill chip row used on Nearby
// ("Distance / Arrival / Service") and Search ("Postal / Stop ID /
// Bus # / Place"). Selected = filled accent; unselected = surface fill.

import SwiftUI

struct SortChipRow<Value: Hashable>: View {
    let t: Theme
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let active = selection == opt.value
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(t.sans(13, weight: .medium))
                        .foregroundStyle(active ? t.onAccent : t.fg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            active ? AnyShapeStyle(t.accent)
                                   : AnyShapeStyle(t.surface),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
