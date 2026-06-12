// SoftMrtView — the MRT line-status board (Leyne 2.7).
//
// A calm, glanceable board built from three LTA DataMall feeds:
//   • TrainServiceAlerts  → per-line operating status (running / disrupted)
//   • FacilitiesMaintenance v2 → lifts currently under maintenance (network-wide)
//   • PCDRealTime         → live per-station crowdedness, fetched lazily when a
//                           line is expanded
//
// Free for everyone. Real-time disruption notifications are wired separately in
// DataStore so users are buzzed even when the tab isn't open.

import SwiftUI

struct SoftMrtView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared

    /// The line whose live station crowd is currently expanded (one at a time).
    @State private var expandedLine: MRTLine?

    private var t: Theme { m.t }

    /// Disrupted lines keyed by palette enum, derived from the LTA alerts.
    private var disruptedLines: [MRTLine: TrainAlert] {
        var map: [MRTLine: TrainAlert] = [:]
        for alert in ds.trainAlerts {
            if let line = alert.line { map[line] = alert }
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title
                overallBanner
                liftMaintenanceCard
                linesList
            }
            .padding(20)
        }
        .background(t.bg.ignoresSafeArea())
        .refreshable { refresh(force: true) }
        .onAppear { refresh(force: false) }
    }

    /// Refresh the always-on feeds (alerts + lift maintenance) plus the crowd
    /// for the currently-open line.
    private func refresh(force: Bool) {
        ds.refreshTrainAlertsIfStale(force: force)
        ds.refreshLiftMaintenanceIfStale(force: force)
        if let line = expandedLine { ds.refreshCrowd(line: line, force: force) }
    }

    // ─── Title ────────────────────────────────────────────
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MRT")
                .font(t.sans(32, weight: .bold))
                .foregroundStyle(t.fg)
            Text("Live line status")
                .font(t.sans(14, weight: .medium))
                .foregroundStyle(t.dim)
        }
    }

    // ─── Disruption banner — only shown when a line is down ───
    // No "all clear" banner: the per-line list already shows each line
    // "Operating normally", so a green summary would just be noise.
    @ViewBuilder
    private var overallBanner: some View {
        let count = disruptedLines.count
        if count > 0 {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) line\(count == 1 ? "" : "s") disrupted")
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text("Tap a line below for details.")
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // ─── Lift maintenance (network-wide) ──────────────────
    @ViewBuilder
    private var liftMaintenanceCard: some View {
        let items = ds.liftMaintenance
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Lift maintenance")
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Spacer(minLength: 0)
                    Text("\(items.count)")
                        .font(t.mono(12, weight: .bold))
                        .foregroundStyle(t.dim)
                }
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(t.faint).frame(width: 5, height: 5)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 1) {
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
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // ─── Per-line rows (expand → live station crowd) ──────
    private var linesList: some View {
        VStack(spacing: 10) {
            ForEach(MRTLine.allCases, id: \.self) { line in
                lineRow(line, alert: disruptedLines[line])
            }
        }
    }

    private func lineRow(_ line: MRTLine, alert: TrainAlert?) -> some View {
        let disrupted = alert != nil
        let isExpanded = expandedLine == line
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Feedback.shared.tap()
                let willExpand = !isExpanded
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    expandedLine = willExpand ? line : nil
                }
                if willExpand { ds.refreshCrowd(line: line) }
            } label: {
                lineHeader(line, alert: alert, disrupted: disrupted, expanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                crowdSection(line)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func lineHeader(_ line: MRTLine, alert: TrainAlert?,
                            disrupted: Bool, expanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Line colour chip with the two-letter code.
            Text(line.rawValue)
                .font(t.mono(13))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(line.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.displayName + " Line")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                if let alert {
                    Text(alert.detail)
                        .font(t.sans(13))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Operating normally")
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: disrupted ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(disrupted ? Color.orange : Color.green.opacity(0.7))
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.faint)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
    }

    // ─── Live station crowd (PCDRealTime) ─────────────────
    @ViewBuilder
    private func crowdSection(_ line: MRTLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 12)

            if let items = ds.crowdByLine[line] {
                if items.isEmpty {
                    Text("Crowd data unavailable right now.")
                        .font(t.sans(13))
                        .foregroundStyle(t.faint)
                } else {
                    crowdLegend
                        .padding(.bottom, 10)
                    VStack(spacing: 11) {
                        ForEach(sortedCrowd(items)) { stop in
                            crowdRow(stop)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(t.dim)
                    Text("Loading live crowd…")
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                }
                .padding(.vertical, 2)
            }
        }
        // Smooth the loading → loaded height change (data arrives async, outside
        // the expand's withAnimation).
        .animation(.easeInOut(duration: 0.28), value: ds.crowdByLine[line]?.count)
    }

    private var crowdLegend: some View {
        HStack(spacing: 12) {
            ForEach([CrowdLevel.low, .moderate, .high], id: \.self) { level in
                HStack(spacing: 5) {
                    Circle().fill(crowdColor(level)).frame(width: 7, height: 7)
                    Text(crowdLabel(level))
                        .font(t.mono(11, weight: .medium))
                        .foregroundStyle(t.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func crowdRow(_ stop: StationCrowd) -> some View {
        HStack(spacing: 10) {
            Circle().fill(crowdColor(stop.level)).frame(width: 9, height: 9)
            Text(stop.name)
                .font(t.sans(15))
                .foregroundStyle(stop.level == .unknown ? t.dim : t.fg)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(crowdLabel(stop.level))
                .font(t.mono(12, weight: .medium))
                .foregroundStyle(t.dim)
        }
    }

    // ─── Helpers ──────────────────────────────────────────
    /// Stations in line order — sort by the numeric suffix of the code
    /// ("EW1" < "EW2" < … < "EW33").
    private func sortedCrowd(_ items: [StationCrowd]) -> [StationCrowd] {
        items.sorted { codeNum($0.code) < codeNum($1.code) }
    }

    private func codeNum(_ code: String) -> Int {
        Int(code.drop(while: { !$0.isNumber })) ?? 0
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
}

extension CrowdLevel: Hashable {}
