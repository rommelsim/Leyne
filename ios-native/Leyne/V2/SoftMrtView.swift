// SoftMrtView — Glance Phase 2 "Rail" network status board.
//
// Layout (Glance spec → screenRail):
//   1. Title + map button.
//   2. Contextual disruption banner — only when ≥1 line is affected
//      (orange left-border card matching .alert style). Hidden when all clear
//      to keep the board calm — "all normal" is the default, not news.
//   3. Network section:
//      • Each line → a full-width `.glanceCard` row:
//          [line chip]  [line name]  [status dot + text]  [chevron]
//        Status: neutral `brand` dot for Normal, `warn` fill for Delays
//        (NOT green — avoids EW-line colour collision per spec comment
//        `.sdot { background: var(--brand) }`).
//   4. Near you:
//      • Up to 3 nearest stations — line chips + station name + crowd glyph
//        + walk time.  Opens station detail as a card.
//
// Data sources reused from existing SoftMrtView without change:
//   • ds.trainAlerts     → disruptedLines
//   • MrtGeo.nearestStations → nearestStations
//   • ds.crowdByLine     → crowd glyphs on near-you rows
//
// Navigation:
//   • Line row taps call onOpenLine(line) which the host (SoftRoot/mrtNavStack)
//     pushes as .line(line) — no sheet; diagram is a pushed page.
//   • Station rows call sheetStation to show SoftMrtStationView as a card.

import SwiftUI
import CoreLocation

struct SoftMrtView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    @StateObject private var loc = LocationManager.shared

    @State private var showMap = false
    @State private var sheetStation: MrtGeoStation?

    @State private var nearestStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] = []

    let onOpenLine: (MRTLine) -> Void
    let onOpenNews: () -> Void
    // Phase 5 IA: the Rail header owns its own trailing controls (map · alerts ·
    // settings) instead of a separately-overlaid cluster that collided with the
    // map button. Defaulted so any legacy caller still compiles.
    var onOpenAlerts: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private var t: Theme { m.t }

    /// Disrupted lines keyed by palette enum, derived from LTA alerts.
    private var disruptedLines: [MRTLine: TrainAlert] {
        var map: [MRTLine: TrainAlert] = [:]
        for alert in ds.trainAlerts {
            if let line = alert.line { map[line] = alert }
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                disruptionBanner
                NativeAdCard()
                networkSection
                nearYouSection
            }
            .padding(20)
        }
        .background(t.bg.ignoresSafeArea())
        .refreshable { refresh(force: true) }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { rebuildNearest(l) }
            refresh(force: false)
        }
        .onChange(of: loc.location) { _, newLoc in
            if let l = newLoc { rebuildNearest(l) }
        }
        .onChange(of: m.searchRadiusM) { _, _ in
            if let l = loc.location { rebuildNearest(l) }
        }
        .sheet(isPresented: $showMap) { MrtMapView() }
        .sheet(item: $sheetStation) { station in
            SoftMrtStationView(station: station,
                               distanceM: nil, walkMin: nil,
                               onBack: { sheetStation = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Nearest list builder

    private func rebuildNearest(_ loc: CLLocation) {
        nearestStations = MrtGeo.nearestStations(
            to: loc.coordinate, limit: 3, withinMeters: m.searchRadiusM)
    }

    private func refresh(force: Bool) {
        ds.refreshTrainAlertsIfStale(force: force)
        ds.refreshLiftMaintenanceIfStale(force: force)
        // Prefetch crowd for all lines so near-you glyphs are ready.
        for line in MRTLine.allCases {
            ds.refreshCrowd(line: line, force: force)
        }
        if let l = loc.location { rebuildNearest(l) }
    }

    // MARK: - Title

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MRT")
                    .font(t.sans(32, weight: .bold))
                    .foregroundStyle(t.fg)
                Text("Network status")
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 8)

            // Trailing controls: map · alerts · settings — all in one row so
            // nothing overlaps the map button anymore.
            HStack(spacing: 8) {
                headerCircleButton(icon: "map.fill", label: "System map") {
                    Feedback.shared.tap()
                    showMap = true
                }
                ZStack(alignment: .topTrailing) {
                    headerCircleButton(
                        icon: "bell.fill",
                        label: m.unseenAlertCount > 0
                            ? "Alerts, \(m.unseenAlertCount) unseen" : "Alerts"
                    ) {
                        Feedback.shared.tap()
                        onOpenAlerts()
                    }
                    if m.unseenAlertCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .offset(x: 1, y: -1)
                    }
                }
                headerCircleButton(icon: "gearshape.fill", label: "Settings") {
                    Feedback.shared.tap()
                    onOpenSettings()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A consistent glass-circle header button (map / bell / gear).
    private func headerCircleButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 38, height: 38)
                .background(t.surface, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Disruption banner
    //
    // Shown only when ≥1 line is disrupted — matches prototype .alert with a
    // left accent border in warn colour. Suppressed entirely when all clear
    // (the prototype doesn't render an "all clear" banner on Rail — it simply
    // omits the element).

    @ViewBuilder
    private var disruptionBanner: some View {
        let disrupted = Array(disruptedLines.keys).sorted(by: { $0.rawValue < $1.rawValue })
        if !disrupted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(disrupted, id: \.self) { line in
                    if let alert = disruptedLines[line] {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(t.warnText)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title)
                                    .font(t.sans(13.5, weight: .semibold))
                                    .foregroundStyle(t.fg)
                                Text(alert.detail)
                                    .font(t.sans(12))
                                    .foregroundStyle(t.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.warnBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(t.warn)
                                .frame(width: 4)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Network section (one row per line)

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Network")
            VStack(spacing: 9) {
                ForEach(MRTLine.allCases, id: \.self) { line in
                    lineRow(line, alert: disruptedLines[line])
                }
            }
        }
    }

    /// One line as a full-width status row.
    /// Line chip → name → status dot + label → chevron.
    /// Normal: neutral `brand` dot (NOT green — avoids EW-colour collision).
    /// Delayed: `warn` fill dot + warnText label.
    private func lineRow(_ line: MRTLine, alert: TrainAlert?) -> some View {
        let disrupted = alert != nil
        return Button {
            Feedback.shared.tap()
            onOpenLine(line)
        } label: {
            HStack(spacing: 12) {
                // Line identity chip
                lineChip(line)

                // Line name
                Text(line.displayName + " Line")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(disrupted ? t.warn : t.brand)
                        .frame(width: 8, height: 8)
                    Text(disrupted ? "Delays" : "Normal")
                        .font(t.sans(12.5, weight: .semibold))
                        .foregroundStyle(disrupted ? t.warnText : t.dim)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glanceCard(fill: t.surface)
        .accessibilityLabel("\(line.displayName) Line, \(disrupted ? "delays" : "normal service")")
    }

    // MARK: - Near you section

    @ViewBuilder
    private var nearYouSection: some View {
        if !nearestStations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("Near you")
                VStack(spacing: 9) {
                    ForEach(nearestStations, id: \.station.id) { entry in
                        nearYouRow(entry)
                    }
                }
            }
        }
    }

    private func nearYouRow(
        _ entry: (station: MrtGeoStation, distanceM: Int, walkMin: Int)
    ) -> some View {
        let station = entry.station
        // Find the first crowd entry for this station across all loaded lines.
        let crowdLevel: CrowdLevel? = {
            for code in station.codes {
                let prefix = String(code.prefix(2)).uppercased()
                guard let line = MRTLine.allCases.first(where: { $0.rawValue == prefix || (prefix == "CG" && $0 == .EW) || (prefix == "CE" && $0 == .CC) }) else { continue }
                if let entry = ds.crowdByLine[line]?.first(where: { station.codes.contains($0.code) }) {
                    return entry.level
                }
            }
            return nil
        }()

        return Button {
            Feedback.shared.tap()
            sheetStation = station
        } label: {
            HStack(spacing: 12) {
                // Line chips
                HStack(spacing: 4) {
                    ForEach(station.codes.prefix(3), id: \.self) { code in
                        miniLineChip(code)
                    }
                }

                // Station name
                Text(station.name)
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Crowd glyph (shape-encoded, never colour-alone)
                if let level = crowdLevel {
                    crowdGlyph(level)
                }

                // Walk time
                Text("\(max(1, entry.walkMin))m")
                    .font(t.mono(12, weight: .semibold))
                    .foregroundStyle(t.brand)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glanceCard(fill: t.surface)
        .accessibilityLabel("\(station.name) station, \(max(1, entry.walkMin)) minute walk")
    }

    // MARK: - Sub-components

    /// Coloured line code chip — small rounded square (matches prototype .linechip).
    /// Dark text on CC orange and EW green for WCAG AA contrast.
    private func lineChip(_ line: MRTLine) -> some View {
        let needsDarkText = line == .CC || line == .EW
        return Text(line.rawValue)
            .font(t.rounded(13, .bold))
            .foregroundStyle(needsDarkText ? Color(hex: "161616") : Color.white)
            .frame(width: 38, height: 28)
            .background(line.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Mini code chip for "near you" rows — smaller height to fit inline.
    private func miniLineChip(_ code: String) -> some View {
        let prefix = String(code.prefix(2)).uppercased()
        let color = mrtLineColorFor(code)
        let needsDark = prefix == "CC" || prefix == "EW" || prefix == "CG" || prefix == "CE"
        return Text(prefix == "CG" ? "EW" : prefix == "CE" ? "CC" : prefix)
            .font(t.mono(10, weight: .bold))
            .foregroundStyle(needsDark ? Color(hex: "161616") : Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Shape-encoded crowd glyph — three ascending bars, filled by level.
    /// The filled count encodes the level (Low=1, Moderate=2, High=3) so the
    /// reading doesn't rely on colour alone, per spec "crowd as SHAPE-encoded".
    private func crowdGlyph(_ level: CrowdLevel) -> some View {
        let filled: Int
        let barColor: Color
        switch level {
        case .low:      filled = 1; barColor = t.go
        case .moderate: filled = 2; barColor = t.warn
        case .high:     filled = 3; barColor = t.crit
        case .unknown:  filled = 0; barColor = t.faint
        }
        let heights: [CGFloat] = [5, 8, 12]
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < filled ? barColor : t.line)
                    .frame(width: 3.5, height: heights[i])
            }
        }
        .accessibilityLabel(crowdLabel(level))
        .accessibilityHidden(false)
    }

    private func crowdLabel(_ l: CrowdLevel) -> String {
        switch l {
        case .low:      return "Low crowd"
        case .moderate: return "Moderate crowd"
        case .high:     return "High crowd"
        case .unknown:  return "Crowd unknown"
        }
    }

    // MARK: - Eyebrow

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }
}

extension CrowdLevel: Hashable {}

// Lets a tapped line drive a `.sheet(item:)` card presentation.
extension MRTLine: Identifiable { public var id: String { rawValue } }
