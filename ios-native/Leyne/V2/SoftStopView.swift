// SoftStopView — Leyne 2.4.0 Stop detail: a top bar with back + pin + more
// actions, a large title block with stop name / code·road / walk distance /
// freshness, a "Buses arriving" / "● LIVE" section header, and a card-per-
// service list matching SoftNearbyStopCard's visual language. Each card has a
// green service badge, destination + following arrivals, and a prominent ETA
// pill. Confidence: "~" whisper only for ghost arrivals — never over-honesty.

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
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    titleBlock
                    arrivalSection
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

    // MARK: - Top bar

    /// Back · (spacer) · star · ellipsis — circular 44×44 buttons.
    private var topBar: some View {
        HStack(spacing: 10) {
            // Back
            Button { fb.select(); onBack() } label: {
                circleButton(icon: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            // Star / favourite toggle — wired to the existing SaveSheet flow.
            Button { fb.select(); showSave = true } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPinned ? t.soon : t.fg)
                    .frame(width: 44, height: 44)
                    .background(t.surface, in: Circle())
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "\(stopName) saved — edit favourite" : "Save \(stopName) to favourites")

            // Sort menu — exposes the three sort options.
            Menu {
                Picker("Sort by", selection: $sort) {
                    Label("By ETA", systemImage: "clock").tag(StopSort.arrival)
                    Label("By bus number", systemImage: "number").tag(StopSort.service)
                    Label("By distance", systemImage: "location").tag(StopSort.distance)
                }
            } label: {
                circleButton(icon: "ellipsis")
            }
            .onTapGesture { fb.tap() }
            .accessibilityLabel("Sort options")
        }
        .padding(.top, 4)
    }

    /// A 44×44 circular icon button using the standard surface/line style.
    private func circleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 44, height: 44)
            .background(t.surface, in: Circle())
            .overlay(Circle().stroke(t.line, lineWidth: 1))
    }

    // MARK: - Title block

    /// Large stop name, code·road subtitle, walk + distance row, freshness.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stop name — large bold
            Text(stopName)
                .font(t.sans(31, weight: .bold))
                .foregroundStyle(t.fg)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.75)

            // Code · road
            Text(subtitle)
                .font(t.mono(13))
                .foregroundStyle(t.dim)
                .lineLimit(1)

            // Walk + distance + freshness in one row
            HStack(spacing: 0) {
                // Walk info (only if location is available)
                if let walkInfo = walkDistanceInfo {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(t.soon)
                        Text(walkInfo.walk)
                            .font(t.mono(13, weight: .medium))
                            .foregroundStyle(t.soon)
                        Text("·")
                            .font(t.mono(13))
                            .foregroundStyle(t.faint)
                        Text(walkInfo.dist)
                            .font(t.mono(13))
                            .foregroundStyle(t.dim)
                    }
                }
                Spacer(minLength: 0)
                // Freshness — right-aligned
                if let label = updatedLabel {
                    Text(label)
                        .font(t.mono(12))
                        .foregroundStyle(t.dim)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Section header + arrivals

    private var arrivalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            arrivalContent
        }
    }

    /// "Buses arriving" left + "● LIVE" right.
    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text("Buses arriving")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer(minLength: 0)
            if feed == .live {
                HStack(spacing: 4) {
                    Circle().fill(t.soon).frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(t.mono(10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(t.soon)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live feed")
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private var arrivalContent: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
            let sorted = sortedServices(services)
            VStack(spacing: 10) {
                ForEach(Array(sorted.enumerated()), id: \.element.no) { _, bus in
                    busRow(bus)
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

    // MARK: - Bus row card

    private func busRow(_ bus: Service) -> some View {
        let conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed)
        let tier = ETATier.of(etaSec: bus.etaSec)
        let badge = serviceBadgeColors(etaSec: bus.etaSec, confidence: conf, t: t)

        return Button {
            fb.select()
            onOpenBus(bus.no)
        } label: {
            HStack(spacing: 12) {
                // Service badge — green when soon, amber when mid, neutral otherwise
                ServiceBadge(svc: bus.no, t: t, size: .md,
                             fillOverride: badge.fill, fgOverride: badge.fg)

                // Destination + following arrivals
                VStack(alignment: .leading, spacing: 3) {
                    Text(destLabel(bus))
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    let following = followingText(bus)
                    if !following.isEmpty {
                        Text(following)
                            .font(t.mono(12))
                            .foregroundStyle(t.dim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                // ETA pill — prominent green when live+soon, neutral for ghost/far
                etaPill(bus, conf: conf, tier: tier)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Bus \(bus.no) to \(bus.dest), \(arrivalA11y(bus, conf))")
        .accessibilityHint("Opens bus \(bus.no)")
    }

    /// Prominent ETA pill — green pill for live/soon, neutral surface for ghost/far.
    /// Ghost arrivals are never painted green; "~" prefix signals unconfirmed.
    private func etaPill(_ bus: Service, conf: ArrivalConfidence, tier: ETATier) -> some View {
        let eta = fmtETA(bus.etaSec)
        let isLiveSoon = (conf == .live || conf == .stale) && (tier == .imminent || tier == .soon)
        let ghost = conf == .unconfirmed
        let pillBg: Color = isLiveSoon ? t.soonBg : t.surfaceHi
        let pillFg: Color = isLiveSoon ? t.soon : t.fg

        let etaText: String = {
            let prefix = ghost ? "~" : ""
            if eta.big == "Arr" { return "\(prefix)Arr" }
            return "\(prefix)\(eta.big) \(eta.small)"
        }()

        return Text(etaText)
            .font(t.mono(14, weight: .semibold))
            .foregroundStyle(pillFg)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(pillBg, in: Capsule())
            .accessibilityHidden(true) // label carried by parent button
    }

    // MARK: - Helpers

    private func destLabel(_ bus: Service) -> String {
        bus.dest.isEmpty ? "Bus \(bus.no)" : "To \(bus.dest)"
    }

    /// "18 min   29 min" secondary arrivals line; empty string when none.
    private func followingText(_ bus: Service) -> String {
        var parts: [String] = []
        if bus.followingSec > bus.etaSec {
            let e = fmtETA(bus.followingSec)
            parts.append(e.big == "Arr" ? "Arr" : "\(e.big) \(e.small)")
        }
        if let d = bus.thirdDate {
            let sec = Int(d.timeIntervalSinceNow)
            if sec > (bus.followingSec > bus.etaSec ? bus.followingSec : bus.etaSec) {
                let e = fmtETA(max(0, sec))
                parts.append(e.big == "Arr" ? "Arr" : "\(e.big) \(e.small)")
            }
        }
        return parts.joined(separator: "   ")
    }

    private func arrivalA11y(_ bus: Service, _ conf: ArrivalConfidence) -> String {
        let eta = fmtETA(bus.etaSec)
        let when = eta.big == "Arr" ? "arriving now" : "\(eta.big) \(eta.small)"
        switch conf {
        case .live:        return when
        case .stale:       return "\(when), estimated"
        case .unconfirmed: return "\(when), scheduled only"
        case .none:        return "no service"
        }
    }

    private func sortedServices(_ s: [Service]) -> [Service] {
        switch sort {
        case .arrival:
            return s.sorted { $0.etaSec < $1.etaSec }
        case .distance:
            return s.sorted { busDistance($0) < busDistance($1) }
        case .service:
            return s.sorted { $0.no.localizedStandardCompare($1.no) == .orderedAscending }
        }
    }

    private func busDistance(_ bus: Service) -> Double {
        guard let lat = bus.busLat, let lon = bus.busLon,
              let stop = ds.stopByCode[stopCode] else { return .greatestFiniteMagnitude }
        return haversine(lat, lon, stop.Latitude, stop.Longitude)
    }

    // MARK: - Data helpers

    private var stopName: String {
        let n = ds.stopName(stopCode)
        return n.isEmpty ? stopCode : n
    }

    private var subtitle: String {
        let road = ds.roadName(stopCode)
        return road.isEmpty ? "Stop \(stopCode)" : "Stop \(stopCode) · \(road)"
    }

    private struct WalkInfo { let walk: String; let dist: String }

    /// Walk + distance info if the user's location is known.
    private var walkDistanceInfo: WalkInfo? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[stopCode] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        let walkMin = max(1, Int((d / 80).rounded()))   // ~80 m/min walking pace
        let distStr = fmtDistance(Int(d.rounded()))
        return WalkInfo(walk: "\(walkMin) min walk", dist: distStr)
    }

    private var updatedLabel: String? {
        guard let last = ds.lastRefresh(stopCode) else { return nil }
        let s = Int(Date().timeIntervalSince(last))
        if s < 5  { return "Updated now" }
        if s < 60 { return "Updated \(s)s ago" }
        let m = s / 60
        return "Updated \(m) min ago"
    }

    // MARK: - Save / pin flow (unchanged behaviour)

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

    // MARK: - Footer / empty

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
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
