// SoftStopView — Leyne 2.4.0 Stop detail: a clean header (back · name ·
// code·road · distance), a freshness line, an ETA / Bus-no. / Distance sort,
// and a stack of arrival cards — a proximity-coloured service badge, the
// destination + occupancy, and a big proximity-coloured ETA. Tapping a card
// opens the Bus view. Colour carries proximity + crowding only; confidence
// stays the whisper "~". An honest footer notes LTA estimates.

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
    @State private var showSave = false
    @State private var saveSel = 0
    @State private var hint: String? = nil

    private var t: Theme { m.t }
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    updatedRow
                    arrivalContent
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .refreshable { await ds.refreshArrivals(stop: stopCode) }
        }
        .onAppear { ds.ensureArrivals(stop: stopCode) }
        .overlay(alignment: .bottom) {
            if let hint {
                Text(hint)
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.contrastFg)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(t.contrast, in: Capsule())
                    .padding(.bottom, 100)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSave) {
            SaveSheet(
                t: t,
                title: "Save this stop",
                subtitle: "Choose how you want to save it.",
                options: [
                    SaveOption(icon: "mappin.and.ellipse", title: "Save stop",
                               subtitle: "See all arriving buses at this stop"),
                    SaveOption(icon: "bus", title: "Save a bus here",
                               subtitle: "Track a specific bus at this stop"),
                ],
                selection: $saveSel
            ) { applyStopSave() }
            .presentationDetents([.height(380)])
        }
    }

    private var pinButton: some View {
        Button { fb.select(); showSave = true } label: {
            Image(systemName: "mappin")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isPinned ? t.contrastFg : t.soon)
                .frame(width: 38, height: 38)
                .background(isPinned ? AnyShapeStyle(t.soon) : AnyShapeStyle(t.surface), in: Circle())
                .overlay(Circle().stroke(isPinned ? Color.clear : t.soon, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "\(stopName) saved — edit favourite" : "Save \(stopName) to favourites")
    }

    private func applyStopSave() {
        showSave = false
        if saveSel == 0 {
            if !isPinned { m.pins.append(Pin(code: stopCode, nickname: "")) }
        } else {
            showHint("Tap a bus below to track it here")
        }
    }

    private func showHint(_ s: String) {
        withAnimation { hint = s }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run { withAnimation { hint = nil } }
        }
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
                Text("\(d) away")
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(t.dim)
                    .padding(.top, 9)
            }
        }
        .padding(.top, 4)
    }

    /// Freshness line — "Updated N ago" with a refresh glyph, so the user can
    /// see how live the list is at a glance (matches the mockup).
    @ViewBuilder
    private var updatedRow: some View {
        if let label = updatedLabel {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(t.mono(11.5))
            }
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
        }
    }

    private var updatedLabel: String? {
        guard let last = ds.lastRefresh(stopCode) else { return nil }
        let s = Int(Date().timeIntervalSince(last))
        if s < 5  { return "Updated just now" }
        if s < 60 { return "Updated \(s) sec ago" }
        let m = s / 60
        return "Updated \(m) min ago"
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
            HStack(spacing: 10) {
                sortControl
                Spacer(minLength: 8)
                pinButton
            }
            let sorted = sortedServices(services)
            VStack(spacing: 10) {
                ForEach(Array(sorted.enumerated()), id: \.element.no) { i, bus in
                    arrivalCard(bus, lead: i == 0)
                }
            }
            footer
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
            (.service, "Bus no."),
            (.distance, "Distance"),
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

    private func arrivalCard(_ bus: Service, lead: Bool) -> some View {
        let conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed)
        let tier = ETATier.of(etaSec: bus.etaSec)
        let imminent = conf == .live && tier.isImminent
        let highlight = lead && imminent
        let badge = serviceBadgeColors(etaSec: bus.etaSec, confidence: conf, t: t)
        return Button {
            fb.select()
            onOpenBus(bus.no)
        } label: {
            HStack(spacing: 12) {
                ServiceBadge(svc: bus.no, t: t, size: .lg,
                             fillOverride: badge.fill, fgOverride: badge.fg)
                VStack(alignment: .leading, spacing: 4) {
                    Text(destLabel(bus))
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    OccupancyLabel(load: bus.load, t: t, size: 11.5)
                }
                Spacer(minLength: 6)
                etaDisplay(bus, conf: conf, imminent: imminent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(highlight ? t.soonBg : t.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(highlight ? t.soon.opacity(0.5) : t.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Bus \(bus.no) to \(bus.dest), \(arrivalA11y(bus, conf)), \(bus.load.label.lowercased())")
        .accessibilityHint("Opens bus \(bus.no)")
    }

    private func destLabel(_ bus: Service) -> String {
        bus.dest.isEmpty ? "Bus \(bus.no)" : "To \(bus.dest)"
    }

    /// Big proximity-coloured ETA with a matching dot, plus "Arriving soon"
    /// under an imminent live arrival. The whisper "~" still tells when the
    /// time is an estimate/scheduled.
    private func etaDisplay(_ bus: Service, conf: ArrivalConfidence, imminent: Bool) -> some View {
        let eta = fmtETA(bus.etaSec)
        let arriving = eta.big == "Arr"
        let color = etaColor(etaSec: bus.etaSec, confidence: conf, t: t)
        let whisper = conf == .stale || conf == .unconfirmed
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if arriving {
                    Text(eta.small)
                        .font(t.mono(20, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Text(eta.big)
                        .font(t.mono(24, weight: .bold))
                        .foregroundStyle(color)
                    Text(eta.small)
                        .font(t.mono(13, weight: .semibold))
                        .foregroundStyle(color.opacity(0.85))
                }
                if whisper {
                    Text("~")
                        .font(t.mono(12, weight: .regular))
                        .foregroundStyle(t.faint)
                        .accessibilityHidden(true)
                }
                Circle().fill(color).frame(width: 7, height: 7)
            }
            if imminent {
                Text("Arriving soon")
                    .font(t.sans(11, weight: .semibold))
                    .foregroundStyle(t.soon)
            }
        }
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

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text("Bus arrival times are estimates from LTA and may vary.")
                .font(t.sans(11))
        }
        .foregroundStyle(t.faint)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .center)
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
