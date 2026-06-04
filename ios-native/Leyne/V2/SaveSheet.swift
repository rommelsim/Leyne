// SaveSheet — the "Save this stop / Save this service" bottom card from the
// 2.4.0 pin flow. A title + subtitle, two (or more) radio option cards, and a
// Save button. Presented as a `.sheet` with a fitted detent from the Stop and
// Bus views when the user taps the pin/favourite button.

import SwiftUI

struct SaveOption: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

struct SaveSheet: View {
    let t: Theme
    let title: String
    let subtitle: String
    let options: [SaveOption]
    @Binding var selection: Int
    let saveTitle: String
    let onSave: () -> Void

    init(t: Theme, title: String, subtitle: String, options: [SaveOption],
         selection: Binding<Int>, saveTitle: String = "Save", onSave: @escaping () -> Void) {
        self.t = t; self.title = title; self.subtitle = subtitle
        self.options = options; self._selection = selection
        self.saveTitle = saveTitle; self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(t.sans(20, weight: .bold))
                    .foregroundStyle(t.fg)
                Text(subtitle)
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }

            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element.id) { i, opt in
                    optionRow(opt, selected: selection == i) {
                        withAnimation(.easeInOut(duration: 0.12)) { selection = i }
                    }
                }
            }

            Button(action: onSave) {
                Text(saveTitle)
                    .font(t.sans(16, weight: .bold))
                    .foregroundStyle(t.contrastFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(t.contrast, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDragIndicator(.visible)
    }

    private func optionRow(_ opt: SaveOption, selected: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: opt.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? t.soon : t.fg)
                    .frame(width: 40, height: 40)
                    .background(selected ? t.soonBg : t.surfaceHi,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(opt.title)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(opt.subtitle)
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                radio(selected)
            }
            .padding(12)
            .background(selected ? t.soonBg.opacity(0.5) : t.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? t.soon.opacity(0.6) : t.line, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func radio(_ selected: Bool) -> some View {
        if selected {
            ZStack {
                Circle().fill(t.soon).frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(t.contrastFg)
            }
        } else {
            Circle().strokeBorder(t.line, lineWidth: 1.5).frame(width: 22, height: 22)
        }
    }
}
