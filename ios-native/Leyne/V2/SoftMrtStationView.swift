// SoftMrtStationView — station detail view for a tapped MrtGeoStation.
//
// Since LTA does not publish per-station arrival times, this view focuses on:
//   • Hero header — large station name, prominent coloured line-code pills,
//     walk/distance meta, and a thin coloured rule as the station's visual hook.
//   • Live crowd — per-line crowd level with a clear indicator + label.
//   • Disruption alerts — shown only when a relevant line is affected.
//   • Lift maintenance — shown only when items exist for this station.
//   • Empty state — calm "No live updates" card when nothing is available.
//
// Back affordance mirrors SoftBusView/SoftStopView: circular circleButton +
// enableSwipeBack() for left-edge interactive-pop.

import SwiftUI

struct SoftMrtStationView: View {
    let station: MrtGeoStation
    /// Walk minutes from the caller's context (nearest list). Nil when opened
    /// from Search (no distance context available).
    var distanceM: Int? = nil
    var walkMin: Int? = nil

    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    let onBack: () -> Void

    private var t: Theme { m.t }

    /// The MRTLine cases relevant to this station (derived from code prefixes).
    private var relevantLines: [MRTLine] {
        station.codes
            .compactMap { lineFromCode($0) }
            .reduce(into: [MRTLine]()) { result, line in
                if !result.contains(line) { result.append(line) }
            }
    }

    /// Alerts for any of this station's lines.
    private var stationAlerts: [TrainAlert] {
        ds.trainAlerts.filter { alert in
            guard let line = alert.line else { return false }
            return relevantLines.contains(line)
        }
    }

    /// Lift maintenance items at this station (by name match).
    private var stationLifts: [LiftMaintenance] {
        let nameLower = station.name.lowercased()
        return ds.liftMaintenance.filter { item in
            item.stationName.lowercased().contains(nameLower)
                || nameLower.contains(item.stationName.lowercased())
        }
    }

    /// True when there is no crowd/disruption/lift data at all to show.
    private var isCompletelyEmpty: Bool {
        stationAlerts.isEmpty && stationLifts.isEmpty && relevantLines.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                heroHeader
                if !stationAlerts.isEmpty { alertsCard }
                crowdSection
                if !stationLifts.isEmpty  { liftsCard }
                if isCompletelyEmpty      { emptyCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .refreshable { fetchCrowdForStation(force: true) }
        .onAppear {
            fetchCrowdForStation(force: false)
            AnalyticsService.log(.stopViewed(code: station.codes.first ?? station.name,
                                             kind: .mrt))
        }
    }

    // MARK: - Top bar (matches SoftStopView / SoftBusView exactly)

    /// Back button + trailing save star — same chrome as SoftStopView/SoftBusView.
    private var topBar: some View {
        HStack {
            Button { onBack() } label: {
                circleButton(icon: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            saveButton
        }
        .padding(.top, 4)
    }

    private var saveButton: some View {
        let saved = m.isMrtSaved(station)
        return Button {
            Feedback.shared.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                m.toggleMrtSaved(station)
            }
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(saved ? t.soon : t.fg)
                .frame(width: 44, height: 44)
                .background(t.surface, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Remove from saved" : "Save station")
    }

    /// A 44×44 circular icon button matching SoftStopView's circleButton exactly.
    private func circleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 44, height: 44)
            .background(t.surface, in: Circle())
            .overlay(Circle().stroke(t.line, lineWidth: 1))
    }

    // MARK: - Hero header

    /// Large station identity block: multi-colour line bar · station name · pills · meta.
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Horizontal multi-colour rule — one colour segment per distinct line,
            // left-to-right. Interchanges show all their colours side-by-side.
            // Falls back to accent when no codes are present.
            if station.codes.isEmpty {
                let ruleColor = relevantLines.first?.color ?? t.accent
                MrtLineColorBar(color: ruleColor, width: 36, height: 4, axis: .horizontal)
            } else {
                MrtLineColorBar(codes: station.codes, width: 36, height: 4, axis: .horizontal)
            }

            // Station name + line pills on the same row — name leading,
            // pills trailing. Name shrinks before pills disappear.
            HStack(alignment: .center, spacing: 10) {
                Text(station.name)
                    .font(t.sans(31, weight: .bold))
                    .foregroundStyle(t.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .layoutPriority(1)
                if !station.codes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(station.codes, id: \.self) { code in
                            MrtCodePill(t: t, code: code)
                        }
                    }
                }
            }

            // Walk / distance meta — only when context is available.
            if let w = walkMin, let d = distanceM {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.soon)
                    Text("\(max(1, w)) min walk")
                        .font(t.mono(12.5))
                        .foregroundStyle(t.soon)
                    Text("·")
                        .font(t.mono(12.5))
                        .foregroundStyle(t.faint)
                    Text("\(d) m")
                        .font(t.mono(12.5))
                        .foregroundStyle(t.dim)
                }
            }
        }
    }

    // MARK: - Live crowd section

    @ViewBuilder
    private var crowdSection: some View {
        if !relevantLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("Crowd now")

                ForEach(relevantLines, id: \.self) { line in
                    crowdCard(line)
                }
            }
        }
    }

    /// A card showing the crowd level for one line at this station.
    @ViewBuilder
    private func crowdCard(_ line: MRTLine) -> some View {
        let allStations = ds.crowdByLine[line]
        let match = allStations?.first { entry in
            station.codes.contains(entry.code)
        }

        HStack(spacing: 12) {
            // Line badge
            Text(line.rawValue)
                .font(t.mono(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(line.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.displayName + " Line")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)

                // Crowd level indicator
                if allStations == nil {
                    // Loading
                    HStack(spacing: 6) {
                        ProgressView().tint(t.dim).scaleEffect(0.75)
                        Text("Loading…")
                            .font(t.mono(12))
                            .foregroundStyle(t.dim)
                    }
                } else if let entry = match {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(crowdColor(entry.level))
                            .frame(width: 9, height: 9)
                        Text(crowdLabel(entry.level))
                            .font(t.sans(13, weight: .semibold))
                            .foregroundStyle(entry.level == .unknown ? t.dim : t.fg)
                        if entry.level != .unknown {
                            Text(crowdSublabel(entry.level))
                                .font(t.mono(11))
                                .foregroundStyle(t.dim)
                        }
                    }
                } else {
                    Text("Unavailable")
                        .font(t.mono(12))
                        .foregroundStyle(t.faint)
                }
            }

            Spacer(minLength: 0)

            // Station code badge (right-aligned)
            if let entry = match, entry.level != .unknown {
                Text(entry.code)
                    .font(t.mono(11))
                    .foregroundStyle(t.faint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Disruption alerts card

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Service alert\(stationAlerts.count == 1 ? "" : "s")")

            ForEach(stationAlerts) { alert in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        // Coloured line bar
                        MRTLineBar(color: alert.line?.color ?? t.dim)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.orange)
                                Text(alert.title)
                                    .font(t.sans(14, weight: .semibold))
                                    .foregroundStyle(t.fg)
                            }
                            Text(alert.detail)
                                .font(t.sans(12))
                                .foregroundStyle(t.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Free-service chips
                    if alert.freeBus || alert.freeShuttle {
                        HStack(spacing: 6) {
                            if alert.freeBus    { freeChip(icon: "bus.fill",  label: "Free bus") }
                            if alert.freeShuttle { freeChip(icon: "tram.fill", label: "Free shuttle") }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Lift maintenance card

    private var liftsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Lift maintenance")

            VStack(spacing: 0) {
                ForEach(Array(stationLifts.enumerated()), id: \.element.id) { i, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 16)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stationName)
                                .font(t.sans(13, weight: .semibold))
                                .foregroundStyle(t.fg)
                            Text(item.detail)
                                .font(t.sans(12))
                                .foregroundStyle(t.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)

                    if i < stationLifts.count - 1 {
                        Rectangle().fill(t.line).frame(height: 1)
                            .padding(.leading, 40)
                    }
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Empty state card

    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text("All clear")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text("No live updates for this station right now.")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Section eyebrow

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }

    // MARK: - Helpers

    private func lineFromCode(_ code: String) -> MRTLine? {
        let prefix = String(code.prefix(2)).uppercased()
        switch prefix {
        case "NS":         return .NS
        case "EW", "CG":  return .EW
        case "NE":         return .NE
        case "CC", "CE":  return .CC
        case "DT":         return .DT
        case "TE":         return .TE
        default:           return nil
        }
    }

    private func fetchCrowdForStation(force: Bool) {
        ds.refreshTrainAlertsIfStale(force: force)
        ds.refreshLiftMaintenanceIfStale(force: force)
        for line in relevantLines {
            ds.refreshCrowd(line: line, force: force)
        }
    }

    private func freeChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.dim)
            Text(label)
                .font(t.sans(11))
                .foregroundStyle(t.fg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.surfaceHi, in: Capsule())
    }

    private func crowdColor(_ l: CrowdLevel) -> Color {
        switch l {
        case .low:      return .green
        case .moderate: return .orange
        case .high:     return .red
        case .unknown:  return t.faint
        }
    }

    private func crowdLabel(_ l: CrowdLevel) -> String {
        switch l {
        case .low:      return "Low"
        case .moderate: return "Moderate"
        case .high:     return "High"
        case .unknown:  return "—"
        }
    }

    private func crowdSublabel(_ l: CrowdLevel) -> String {
        switch l {
        case .low:      return "Not crowded"
        case .moderate: return "Getting busy"
        case .high:     return "Very crowded"
        case .unknown:  return ""
        }
    }
}
