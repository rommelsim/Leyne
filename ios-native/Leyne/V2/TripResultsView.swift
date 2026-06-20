// TripResultsView — Glance trip-planning placeholder.
//
// ─── HONEST PLACEHOLDER — NO ROUTING ENGINE ──────────────────────────────────
// Leyne has no journey-planning backend yet. The previous version rendered
// fabricated itineraries (made-up durations, fares, transfer counts, a "LIVE"
// dot, and a "Rain-safe" filter the app can't evaluate) behind a fine-print
// "illustrative only" banner. In a transit context people act on the first
// number they see, so real-looking fake data is a trust risk that outweighs the
// exploratory value. This screen is now honest: it states that planning is
// coming, and routes the user to the thing that DOES work today — live
// departures at a nearby stop.
//
// Re-introduce real itinerary cards only when wired to an actual routing engine
// (LTA Journey Planner API or an in-app graph).
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct TripResultsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @Environment(\.dismiss) private var dismiss

    let destination: String
    let nearbyStops: [NearbyStop]

    // Navigation callbacks (mirror Search's conventions). `onOpenBus` is retained
    // for call-site compatibility even though this placeholder only opens stops.
    var onOpenStop: ((String) -> Void)?
    var onOpenBus: ((String, String) -> Void)?

    private var t: Theme { m.t }

    private var hasDestination: Bool {
        !destination.isEmpty && destination.lowercased() != "destination"
    }

    // MARK: Body

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        comingSoonCard
                        if !nearbyStops.isEmpty { nearbyStopsSection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                fb.select()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(t.surfaceHi)
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.fg)
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text("Plan a trip")
                    .font(t.rounded(17, .bold))
                    .foregroundStyle(t.fg)
                if hasDestination {
                    Text("to \(destination)")
                        .font(t.sans(12, weight: .medium))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Coming-soon card (honest, no fabricated routes)

    private var comingSoonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(t.brand)
                .frame(width: 52, height: 52)
                .background(t.brand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text("Trip planning is coming soon")
                .font(t.rounded(20, .bold))
                .foregroundStyle(t.fg)

            Text("Door-to-door journeys across bus and MRT aren’t ready yet. For now, jump straight to live departures at a stop near you.")
                .font(t.sans(14))
                .foregroundStyle(t.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glanceCard(fill: t.surface)
    }

    // MARK: Nearby stops (real, actionable)

    private var nearbyStopsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Departures near you")
            VStack(spacing: 9) {
                ForEach(nearbyStops.prefix(6)) { stop in
                    nearbyStopRow(stop)
                }
            }
        }
    }

    private func nearbyStopRow(_ stop: NearbyStop) -> some View {
        // Up to three service numbers as a quick preview of what runs here.
        let preview = stop.services.prefix(3).map { $0.no }

        return Button {
            fb.select()
            onOpenStop?(stop.stopCode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 44, height: 44)
                    .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.stopName.isEmpty ? stop.stopCode : stop.stopName)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        if stop.walkMin > 0 {
                            Text("\(stop.walkMin) min walk")
                                .font(t.sans(12.5, weight: .semibold))
                                .foregroundStyle(t.brand)
                            Text("·").font(t.sans(12.5)).foregroundStyle(t.ink3)
                        }
                        Text(preview.isEmpty ? "Stop \(stop.stopCode)"
                                             : preview.joined(separator: " · "))
                            .font(t.sans(12.5))
                            .foregroundStyle(t.ink3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glanceCard(fill: t.surface)
        .accessibilityLabel("\(stop.stopName), \(max(0, stop.walkMin)) minute walk, see departures")
    }

    // MARK: Eyebrow

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }
}
