// SoftStopView — Leyne 3.0 Stop detail (per Flow Prototype.html): a clean
// header (back · name · code·road · distance), an ETA / Distance / Bus-no.
// sort, and a stack of minimal arrival cards — neutral service badge + a
// big confidence-treated ETA. Tapping a card opens the Bus view, where the
// destination, crowd, route and alert controls live. The honest footer
// appears when any arrival is aging or scheduled-only.

import SwiftUI

/// How the stop's arrivals are ordered.
enum StopSort: Hashable {
    case arrival   // soonest first
    case distance  // nearest bus first (live GPS); ghost/no-signal last
    case service   // by bus number (natural numeric order)
}

struct SoftStopView: View {
    let stopCode: String

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void
    let onOpenBus: (String) -> Void

    @State private var sort: StopSort = .arrival

    private var t: Theme { m.t }
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    arrivalContent
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .refreshable { await ds.refreshArrivals(stop: stopCode) }
        }
        .onAppear { ds.ensureArrivals(stop: stopCode) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { fb.select(); onBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 38, height: 38)
                    .background(t.surface, in: Circle())
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(stopName)
                    .font(t.sans(24, weight: .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(t.mono(11.5))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let d = stopDistanceLabel {
                Text(d)
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(t.dim)
                    .padding(.top, 9)
            }
        }
        .padding(.top, 4)
    }

    private var stopName: String {
        let n = ds.stopName(stopCode)
        return n.isEmpty ? stopCode : n
    }

    private var subtitle: String {
        let road = ds.roadName(stopCode)
        return road.isEmpty ? "Stop \(stopCode)" : "\(stopCode) · \(road)"
    }

    /// Walk distance from the user to this stop (header chip), if known.
    private var stopDistanceLabel: String? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[stopCode] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return fmtDistance(Int(d.rounded()))
    }

    // MARK: Arrivals

    @ViewBuilder
    private var arrivalContent: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
            sortControl
            let sorted = sortedServices(services)
            VStack(spacing: 10) {
                ForEach(sorted, id: \.no) { bus in
                    arrivalCard(bus)
                }
            }
            honestFooter(services)
        case .some(.empty):
            emptyArrivals(message: "No buses in operation right now.")
        case .some(.error(let e)):
            emptyArrivals(message: e)
        default:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private var sortControl: some View {
        SortChipRow(t: t, selection: $sort, options: [
            (.arrival, "ETA"),
            (.distance, "Distance"),
            (.service, "Bus no."),
        ])
    }

    private func sortedServices(_ s: [Service]) -> [Service] {
        switch sort {
        case .arrival:
            return s.sorted { $0.etaSec < $1.etaSec }
        case .distance:
            // Nearest live bus first. Arrivals with no GPS (ghost / not
            // monitored) have no honest distance, so they sort last.
            return s.sorted { busDistance($0) < busDistance($1) }
        case .service:
            return s.sorted { $0.no.localizedStandardCompare($1.no) == .orderedAscending }
        }
    }

    /// Metres from a bus's live GPS position to this stop, or .max when the
    /// bus isn't transmitting a position (so it sinks to the bottom).
    private func busDistance(_ bus: Service) -> Double {
        guard let lat = bus.busLat, let lon = bus.busLon,
              let stop = ds.stopByCode[stopCode] else { return .greatestFiniteMagnitude }
        return haversine(lat, lon, stop.Latitude, stop.Longitude)
    }

    private func arrivalCard(_ bus: Service) -> some View {
        let conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed)
        let imminent = conf == .live && bus.etaSec <= 60
        return Button {
            fb.select()
            onOpenBus(bus.no)
        } label: {
            HStack(spacing: 14) {
                Text(bus.no)
                    .font(t.mono(17, weight: .bold))
                    .foregroundStyle(t.fg)
                    .frame(minWidth: 50, minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
                ConfidenceETA(eta: fmtETA(bus.etaSec), confidence: conf, t: t, size: 22, weight: .bold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(imminent ? t.accent.opacity(0.5) : t.line,
                        lineWidth: imminent ? 1.5 : 1))
            .shadow(color: imminent ? t.accent.opacity(0.12) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Bus \(bus.no), \(arrivalA11y(bus, conf))")
        .accessibilityHint("Opens bus \(bus.no)")
    }

    private func arrivalA11y(_ bus: Service, _ conf: ArrivalConfidence) -> String {
        let eta = fmtETA(bus.etaSec)
        let when = eta.big == "Arr" ? "arriving now" : "\(eta.big) \(eta.small)"
        switch conf {
        case .live: return when
        case .stale: return "\(when), estimated"
        case .unconfirmed: return "\(when), scheduled only"
        case .none: return "no service"
        }
    }

    /// Honest footer — only when at least one arrival is aging or
    /// scheduled-only, so the softened/outlined cards above read as a
    /// deliberate truth signal, not a glitch.
    @ViewBuilder
    private func honestFooter(_ services: [Service]) -> some View {
        let hasGhost = services.contains { !$0.monitored }
        let hasStale = feed != .live && services.contains { $0.monitored }
        if hasGhost || hasStale {
            HStack(spacing: 7) {
                ConfidenceDot(confidence: hasGhost ? .unconfirmed : .stale, t: t, size: 6)
                Text("aging & scheduled-only arrivals shown honestly")
                    .font(t.mono(10.5))
                    .foregroundStyle(t.faint)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        }
    }

    private func emptyArrivals(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "tram.fill")
                .font(.system(size: 22))
                .foregroundStyle(t.dim)
            Text(message)
                .font(t.sans(14))
                .foregroundStyle(t.fg)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
