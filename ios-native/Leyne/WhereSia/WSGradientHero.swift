// WhereSia — the Home header.
//
// This file once held a generated "living sky" (an animated MeshGradient driven
// by time of day + weather). That was parked 2026-07-10 and REMOVED 2026-07-22
// in the minimal / sunlight-legibility pass: under direct sun a decorative
// gradient only raises the black level behind the text it sits under, and the
// research direction is that authority comes from what is removed. The header is
// now a flat, content-sized search entry over the page background — no fixed
// height, so no dead space below the field.
//
// No clock headline: the OS status bar already shows the time, so a second
// in-app clock was pure duplication (UX pass 2026-07-16).

import SwiftUI

/// The Home header: a tappable search field on the plain page background.
struct WSGreetingHero: View {
    var onSearchTap: () -> Void

    @Environment(\.ws) private var ws

    var body: some View {
        Button(action: onSearchTap) {
            HStack(spacing: 11) {
                WSIcon(glyph: .search, size: 16, weight: .medium, color: ws.dim)
                Text("Search stop, bus or station")
                    .font(ws.sans(15, weight: .medium))
                    .foregroundStyle(ws.dim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15).frame(height: 48)
            .background(Capsule().fill(ws.input))
            .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(WSCompressStyle())
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }
}
