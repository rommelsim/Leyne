// HiddenStopsView — manages the stops a user has hidden from Nearby (via the
// long-press "Hide From Nearby" action). Swipe a row to bring a stop back.
// Reached from Settings → Hidden stops, which only surfaces while something is
// hidden. Mirrors ManageAlertsView's list styling.

import SwiftUI

struct HiddenStopsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    private var t: Theme { m.t }

    /// Hidden stop codes, name-sorted for a stable order.
    private var codes: [String] {
        m.hiddenNearby.sorted { ds.stopName($0) < ds.stopName($1) }
    }

    var body: some View {
        List {
            if codes.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(codes, id: \.self) { row($0) }
                } footer: {
                    Text("Hidden stops won't show in Nearby. Swipe a stop to bring it back.")
                        .font(t.sans(12))
                        .foregroundStyle(t.faint)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.bg.ignoresSafeArea())
        .navigationTitle("Hidden stops")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .tint(t.accent)
    }

    private func row(_ code: String) -> some View {
        let name = ds.stopName(code)
        let road = ds.roadName(code)
        return HStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.dim)
                .frame(width: 36, height: 36)
                .background(t.surfaceHi,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? code : name)
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                Text(road.isEmpty ? "Stop \(code)" : "Stop \(code) · \(road)")
                    .font(t.mono(12))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .listRowBackground(t.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                fb.success(); m.unhideNearby(code: code)
            } label: {
                Label("Unhide", systemImage: "eye")
            }
            // Restorative, so green — and an explicit tint so the List's
            // `.tint(t.accent)` can't blank the glyph (same gotcha fixed in
            // ManageAlertsView).
            .tint(t.soon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name.isEmpty ? code : name), Stop \(code)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(t.dim)
            Text("Nothing hidden")
                .font(t.sans(17, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Stops you hide from Nearby will show up here.")
                .font(t.sans(13))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}
