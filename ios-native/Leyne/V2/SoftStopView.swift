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
    @State private var expanded = false

    /// How many services to show before the "Show more" expander kicks in.
    private let collapsedCount = 6

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

            // Star menu — pin/unpin this stop, or save a specific bus here,
            // without leaving the page (replaces the old save-sheet-only flow).
            Menu {
                Button {
                    fb.select(); m.togglePin(code: stopCode)
                } label: {
                    Label(isPinned ? "Unpin from Saved" : "Save to Saved",
                          systemImage: isPinned ? "star.slash" : "star")
                }
                Button {
                    fb.select(); showSave = true
                } label: {
                    Label("Save a bus here…", systemImage: "bus")
                }
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPinned ? t.soon : t.fg)
                    .frame(width: 44, height: 44)
                    .background(t.surface, in: Circle())
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
            }
            .onTapGesture { fb.tap() }
            .accessibilityLabel(isPinned ? "\(stopName) saved — saving options" : "Save \(stopName)")

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
                // LIVE when the feed is live; otherwise the freshness label.
                if feed == .live {
                    HStack(spacing: 4) {
                        Circle().fill(t.soon).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(t.mono(10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(t.soon)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live feed")
                } else if let label = updatedLabel {
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

    /// Section title above the grouped arrivals list.
    private var sectionHeader: some View {
        Text("All arriving buses")
            .font(t.sans(15, weight: .semibold))
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private var arrivalContent: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
            let sorted = sortedServices(services)
            let canCollapse = sorted.count > collapsedCount
            let shown = (expanded || !canCollapse) ? sorted
                                                   : Array(sorted.prefix(collapsedCount))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.no) { i, bus in
                    if i > 0 { rowDivider }
                    busRow(bus)
                }
                if canCollapse {
                    rowDivider
                    showMoreRow(total: sorted.count)
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(t.line, lineWidth: 1))
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

    /// Full-bleed hairline separating rows inside the grouped card.
    private var rowDivider: some View {
        Rectangle().fill(t.line).frame(height: 1)
    }

    // MARK: - Bus row

    /// One service row inside the grouped card: badge · destination · its next
    /// three arrival times in columns. The whole row opens the bus view.
    private func busRow(_ bus: Service) -> some View {
        let conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed)
        let badge = serviceBadgeColors(etaSec: bus.etaSec, confidence: conf, t: t)

        return Button {
            fb.select()
            onOpenBus(bus.no)
        } label: {
            HStack(spacing: 12) {
                ServiceBadge(svc: bus.no, t: t, size: .md,
                             fillOverride: badge.fill, fgOverride: badge.fg)

                Text(destLabel(bus))
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                etaColumns(bus, confidence: conf)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Bus \(bus.no) to \(bus.dest), \(arrivalA11y(bus, conf))")
        .accessibilityHint("Opens bus \(bus.no)")
    }

    /// Up to three arrival columns ("Arr · 13 · 24 min") split by hairlines.
    /// The lead column carries proximity colour + a live signal; the rest ink.
    private func etaColumns(_ bus: Service, confidence: ArrivalConfidence) -> some View {
        let etas = arrivalTimes(bus)
        return HStack(spacing: 0) {
            ForEach(Array(etas.enumerated()), id: \.offset) { i, sec in
                if i > 0 {
                    Rectangle().fill(t.line).frame(width: 1, height: 30)
                        .padding(.horizontal, 10)
                }
                etaColumn(sec, lead: i == 0, confidence: confidence)
            }
        }
    }

    private func etaColumn(_ sec: Int, lead: Bool, confidence: ArrivalConfidence) -> some View {
        let eta = fmtETA(sec)
        let arriving = eta.big == "Arr"
        let color = lead ? etaColor(etaSec: sec, confidence: confidence, t: t) : t.fg
        let ghost = confidence == .unconfirmed
        return VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if ghost {
                    Text("~").font(t.mono(11, weight: .regular))
                        .foregroundStyle(t.faint).accessibilityHidden(true)
                }
                Text(arriving ? "Arr" : eta.big)
                    .font(t.mono(20, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if lead && arriving && confidence == .live {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.soon)
                        .offset(y: -7)
                        .accessibilityHidden(true)
                }
            }
            Text(arriving ? "now" : eta.small)
                .font(t.mono(10))
                .foregroundStyle(t.dim)
        }
        .frame(minWidth: 34)
    }

    /// "Show more" / "Show less" expander at the foot of the grouped card.
    private func showMoreRow(total: Int) -> some View {
        Button {
            fb.tap()
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? "Show less" : "Show more")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(expanded ? "Show fewer buses" : "Show all \(total) buses")
    }

    // MARK: - Helpers

    private func destLabel(_ bus: Service) -> String {
        bus.dest.isEmpty ? "Bus \(bus.no)" : "To \(bus.dest)"
    }

    /// 1–3 upcoming arrival times (seconds) for a service, dropping any that
    /// aren't strictly later than the previous one.
    private func arrivalTimes(_ bus: Service) -> [Int] {
        var out = [bus.etaSec]
        if bus.followingSec > bus.etaSec { out.append(bus.followingSec) }
        if let d = bus.thirdDate {
            let third = Int(d.timeIntervalSinceNow)
            if third > (out.last ?? 0) { out.append(max(0, third)) }
        }
        return out
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
