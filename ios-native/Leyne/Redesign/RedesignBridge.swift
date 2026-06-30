// Live-data bridge for the SG Transit redesign (iOS).
//
// The redesign's view layer is written against the compact `RD*` view-models
// (RDStop / RDArrival / RDStation …). This file adapts the app's real LTA
// DataMall domain types (Service / NearbyStop / MrtGeoStation / TrainAlert)
// into those view-models, so the redesign renders genuine live data without
// rewriting every screen. There is no mock content here — everything flows
// from `DataStore.shared`.

import SwiftUI
import CoreLocation

// MARK: - Occupancy

func rdLoad(_ l: Load) -> RDLoad {
    switch l {
    case .sea: return .seats
    case .sda: return .standing
    case .lsd: return .packed
    }
}

/// Whole-minute ETA label for an arrival in seconds. "0" means arriving now.
func rdMinLabel(_ etaSec: Int) -> String {
    String(max(0, (etaSec + 30) / 60))
}

// MARK: - Arrivals

func rdArrival(_ s: Service) -> RDArrival {
    let then = s.followingSec > 0 ? "then \(max(1, (s.followingSec + 30) / 60))" : nil
    return RDArrival(route: s.no, dest: s.dest, load: rdLoad(s.load),
                     min: rdMinLabel(s.etaSec), then: then)
}

func rdArrivals(_ services: [Service]) -> [RDArrival] { services.map(rdArrival) }

// MARK: - Stops

/// Map a live nearby stop into the redesign's RDStop view-model.
func rdStop(_ n: NearbyStop) -> RDStop {
    let here = n.distanceM <= 40
    return RDStop(
        name: n.stopName,
        code: n.stopCode,
        dist: here ? "You're at this stop" : "\(n.walkMin) min walk · \(fmtDistance(n.distanceM))",
        distShort: here ? "You are here" : fmtDistance(n.distanceM),
        badge: here ? "YOU'RE HERE" : "\(n.walkMin) MIN WALK",
        arrivals: rdArrivals(n.services))
}

// MARK: - MRT interchange badges (item 3)

/// The rail line code(s) + colours for a bus-stop description, or [] when the
/// stop is not (next to) a recognised MRT/LRT station. Drives the small
/// line-coloured chip shown beside interchange stop names.
func rdMrtBadges(forStopNamed name: String) -> [MrtCode] {
    resolveMrtStation(name)?.codes ?? []
}

/// Readable foreground for a line-coloured badge — dark ink on the light
/// (orange) Circle Line, white on everything else.
func rdMrtBadgeFg(_ code: String) -> Color {
    let prefix = String(code.prefix(2)).uppercased()
    return (prefix == "CC" || prefix == "CE")
        ? Color(.sRGB, red: 0.22, green: 0.14, blue: 0, opacity: 1)
        : .white
}

/// Small line-coloured code chip(s) shown beside an interchange stop name
/// (item 3). Renders nothing when the stop isn't a recognised rail station.
struct RDMrtBadgeRow: View {
    let stopName: String
    var size: CGFloat = 10

    var body: some View {
        let codes = rdMrtBadges(forStopNamed: stopName)
        HStack(spacing: 4) {
            ForEach(codes, id: \.code) { c in
                Text(c.code)
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(rdMrtBadgeFg(c.code))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
