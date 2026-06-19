// TripResultsView — Glance Phase 4 trip results shell.
//
// ─── IMPORTANT: UI-COMPLETE SHELL — NO ROUTING ENGINE ────────────────────────
// This view has NO real trip-planning or routing backend. The trip options shown
// are derived from real nearby stops and MRT line data (real stop names, real bus
// numbers where available) but the journey legs, durations, fares, and transfer
// sequences are PLAUSIBLE EXAMPLES, not computed routes.
//
// Wire this to a real routing engine (e.g. LTA JourneyPlanner API, or an in-app
// graph) before relying on any of the output for real navigation. Until then, the
// shell deliberately surfaces this to the user with a "Route planning coming soon"
// disclaimer visible at the top.
// ─────────────────────────────────────────────────────────────────────────────
//
// What IS real:
//   • From location = "Current location" (GPS from AppModel.location)
//   • Destination label = passed in from Search
//   • Nearest-stop names + bus service numbers pulled from DataStore.nearby
//   • MRT line colours via MRTLine.color / mrtLineColorFor
//   • Filter chip row (Best / Fewest transfers / Least walking / Rain-safe)
//
// Prototype mapping (screenTrip / .trip__* / .modestrip):
//   .trip__top  → duration hero + clock window + fare HStack
//   .modestrip  → inline leg strip: walk→bus→MRT glyph sequence with line colour
//   .trip__meta → transfer count + live indicator
//   .seg        → filter chip row

import SwiftUI

// MARK: - Trip option data (shell — NOT from a routing engine)

/// One leg in a sample itinerary. Legs are purely illustrative until a
/// routing engine provides real journey plans.
enum TripLegKind {
    case walk(minutes: Int)
    case bus(no: String, stopCode: String)
    case mrt(line: MRTLine)
}

struct SampleTripOption: Identifiable {
    let id = UUID()
    let durationMin: Int
    let departTime: String   // "HH:mm" — clock window start; illustrative
    let arriveTime: String   // "HH:mm" — clock window end; illustrative
    let fare: String         // "$X.XX" — illustrative adult cash fare
    let legs: [TripLegKind]
    let transferCount: Int
    let walkingMinutes: Int
    let isLive: Bool         // show a LIVE dot — true for the first option
    let tags: [String]       // e.g. ["Fewest transfers", "Least walking"]
}

// MARK: - Filter

enum TripFilter: String, CaseIterable {
    case best      = "Best"
    case transfers = "Fewest transfers"
    case walking   = "Least walking"
    case rain      = "Rain-safe"
}

// MARK: - TripResultsView

struct TripResultsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @Environment(\.dismiss) private var dismiss

    let destination: String
    let nearbyStops: [NearbyStop]

    // Navigation callbacks (mirrors Search's conventions)
    var onOpenStop: ((String) -> Void)?
    var onOpenBus: ((String, String) -> Void)?

    @State private var activeFilter: TripFilter = .best

    private var t: Theme { m.t }

    // Build sample trips once at render time from real nearby data where possible.
    private var sampleTrips: [SampleTripOption] {
        buildSampleTrips(from: nearbyStops)
    }

    private var filteredTrips: [SampleTripOption] {
        switch activeFilter {
        case .best:
            return sampleTrips.sorted { $0.durationMin < $1.durationMin }
        case .transfers:
            return sampleTrips.sorted {
                $0.transferCount == $1.transferCount
                    ? $0.durationMin < $1.durationMin
                    : $0.transferCount < $1.transferCount
            }
        case .walking:
            return sampleTrips.sorted {
                $0.walkingMinutes == $1.walkingMinutes
                    ? $0.durationMin < $1.durationMin
                    : $0.walkingMinutes < $1.walkingMinutes
            }
        case .rain:
            // "Rain-safe" heuristic: fewer walking minutes.
            return sampleTrips.sorted { $0.walkingMinutes < $1.walkingMinutes }
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header — "From → To" with back / dismiss button
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Shell disclaimer
                        shellDisclaimer
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        // Filter chips
                        filterChipRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)

                        // Trip option cards
                        if filteredTrips.isEmpty {
                            emptyTrips
                                .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredTrips) { trip in
                                    tripCard(trip)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
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

            VStack(alignment: .leading, spacing: 2) {
                Text("Current location → \(destination)")
                    .font(t.rounded(17, .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Leave now")
                    .font(t.sans(12, weight: .medium))
                    .foregroundStyle(t.dim)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Shell disclaimer

    private var shellDisclaimer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(t.warnText)

            Text("Route planning coming soon — these are illustrative options only.")
                .font(t.sans(12))
                .foregroundStyle(t.warnText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.warnText.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }

    // MARK: Filter chips (prototype .seg)

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TripFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: TripFilter) -> some View {
        let active = activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { activeFilter = filter }
        } label: {
            Text(filter.rawValue)
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(active ? t.contrastFg : t.dim)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    active ? AnyShapeStyle(t.fg) : AnyShapeStyle(t.surface),
                    in: Capsule()
                )
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Trip option card (prototype .trip)

    private func tripCard(_ trip: SampleTripOption) -> some View {
        // Tapping a trip with a bus leg routes to the first bus stop.
        let firstBusLeg: (String, String)? = {
            for leg in trip.legs {
                if case .bus(let no, let stopCode) = leg { return (stopCode, no) }
            }
            return nil
        }()

        return Button {
            fb.select()
            if let (stopCode, svcNo) = firstBusLeg {
                onOpenBus?(stopCode, svcNo)
            } else if let firstStop = nearbyStops.first {
                onOpenStop?(firstStop.stopCode)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: duration hero + clock + fare
                tripTopRow(trip)
                    .padding(.bottom, 10)

                // Inline mode strip (walk / bus / MRT glyphs in journey order)
                modeStrip(trip.legs)
                    .padding(.bottom, 8)

                // Meta row: transfer count + live dot
                tripMetaRow(trip)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glanceCard(fill: t.surface)
    }

    // Prototype .trip__top
    private func tripTopRow(_ trip: SampleTripOption) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(trip.durationMin) min")
                .font(t.rounded(26, .heavy))
                .foregroundStyle(t.fg)

            Text("\(trip.departTime) – \(trip.arriveTime)")
                .font(t.rounded(13, .semibold).monospacedDigit())
                .foregroundStyle(t.dim)

            Spacer(minLength: 0)

            Text(trip.fare)
                .font(t.rounded(14, .bold).monospacedDigit())
                .foregroundStyle(t.dim)
        }
    }

    // Prototype .modestrip — horizontal row of walk/bus/MRT segments with arrows
    private func modeStrip(_ legs: [TripLegKind]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.faint)
                }
                legIcon(leg)
            }
        }
    }

    @ViewBuilder
    private func legIcon(_ leg: TripLegKind) -> some View {
        switch leg {
        case .walk(let minutes):
            HStack(spacing: 3) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.dim)
                Text("\(minutes)'")
                    .font(t.rounded(11, .semibold))
                    .foregroundStyle(t.dim)
            }

        case .bus(let no, _):
            // Compact bus badge: 24×24 ink square (prototype size)
            Text(no)
                .font(t.rounded(12, .bold))
                .foregroundStyle(t.bg)
                .frame(width: 28, height: 28)
                .background(t.fg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

        case .mrt(let line):
            // MRT line chip with official line colour
            Text(line.rawValue)
                .font(t.rounded(11, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(line.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // Prototype .trip__meta
    private func tripMetaRow(_ trip: SampleTripOption) -> some View {
        HStack(spacing: 8) {
            if trip.isLive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(t.go)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(t.rounded(10, .bold))
                        .foregroundStyle(t.go)
                        .tracking(0.5)
                }
            }

            let transferLabel = trip.transferCount == 0 ? "No transfers"
                : trip.transferCount == 1 ? "1 transfer"
                : "\(trip.transferCount) transfers"

            Text(transferLabel)
                .font(t.sans(12, weight: .medium))
                .foregroundStyle(t.dim)

            if !trip.tags.isEmpty {
                Text("·")
                    .font(t.sans(12))
                    .foregroundStyle(t.faint)
                Text(trip.tags.joined(separator: " · "))
                    .font(t.sans(12, weight: .medium))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Empty state

    private var emptyTrips: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 36))
                .foregroundStyle(t.faint)
                .padding(.bottom, 4)
            Text("No routes right now")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Route planning is coming soon. Check LTA's Journey Planner in the meantime.")
                .font(t.sans(12))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }
}

// MARK: - Sample trip builder

/// Builds plausible illustrative trip options from real nearby stops.
/// Uses actual stop names and bus numbers where available, but durations,
/// fares, and sequences are NOT real journey plans.
private func buildSampleTrips(from nearby: [NearbyStop]) -> [SampleTripOption] {
    let now = Date()
    let cal = Calendar.current
    let fmt: (Date) -> String = { d in
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // Pick the first stop as the boarding point, and lift its first two bus
    // numbers if available — this is what makes the strip "real-ish".
    let boardStop = nearby.first
    let busA = boardStop?.services.first?.no ?? "88"
    let busAStop = boardStop?.stopCode ?? "53061"
    let busB = nearby.count > 1 ? (nearby[1].services.first?.no ?? "67") : "67"
    let busBStop = nearby.count > 1 ? nearby[1].stopCode : busAStop

    let depart0 = now
    let depart1 = now.addingTimeInterval(2 * 60)
    let depart2 = now.addingTimeInterval(1 * 60)

    return [
        SampleTripOption(
            durationMin: 24,
            departTime: fmt(depart0),
            arriveTime: fmt(depart0.addingTimeInterval(24 * 60)),
            fare: "$1.79",
            legs: [
                .walk(minutes: 4),
                .bus(no: busA, stopCode: busAStop),
                .walk(minutes: 2),
                .mrt(line: .EW),
                .walk(minutes: 3),
            ],
            transferCount: 1,
            walkingMinutes: 9,
            isLive: true,
            tags: []
        ),
        SampleTripOption(
            durationMin: 27,
            departTime: fmt(depart1),
            arriveTime: fmt(depart1.addingTimeInterval(27 * 60)),
            fare: "$1.55",
            legs: [
                .walk(minutes: 6),
                .mrt(line: .NS),
                .walk(minutes: 4),
            ],
            transferCount: 0,
            walkingMinutes: 10,
            isLive: false,
            tags: ["Fewest transfers"]
        ),
        SampleTripOption(
            durationMin: 31,
            departTime: fmt(depart2),
            arriveTime: fmt(depart2.addingTimeInterval(31 * 60)),
            fare: "$1.40",
            legs: [
                .walk(minutes: 2),
                .bus(no: busB, stopCode: busBStop),
                .bus(no: busA, stopCode: busAStop),
                .walk(minutes: 1),
            ],
            transferCount: 1,
            walkingMinutes: 3,
            isLive: false,
            tags: ["Least walking", "Rain-safe"]
        ),
    ]
}
