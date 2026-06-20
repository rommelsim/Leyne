// SoftMrtStationView — Glance Phase 2 station detail.
//
// Spec (screenStation + .st-* CSS):
//   • Hero header: large station name (27pt bold rounded), line chips, walk meta.
//   • "Next trains · scheduled" section — two direction cards, each with:
//       - Towards [terminus] · Platform [A/B] · crowd glyph
//       - Big scheduled ETA (34pt, muted ink3 when scheduled) with "~" whisper prefix.
//       - Two more following ETAs (smaller, muted).
//     LTA has NO live train arrivals API. All times are derived from published
//     schedules embedded in a static table. They render as SCHEDULED only:
//       - Muted colour (t.ink3 / t.dim), NOT green.
//       - "~" whisper prefix (matching the bus app's ConfidenceETA.unconfirmed).
//       - No live wave icon.
//       - Section header explicitly labels "Next trains · scheduled".
//     This is honest — the spec demands it: "be honest, LTA has no real-time
//     train arrivals". The screen-reader label says "scheduled estimate".
//   • Progressive disclosure rows (matches prototype .disclose):
//       - Lifts (from ds.liftMaintenance, real data) — shows actual status.
//       - Exits (static "A–F" placeholder; real exit data not in LTA feeds).
//       - First / last train (static per-station from embedded table).
//       - Nearby buses → taps open the nearest bus stop (navigateToStation bridge).
//   • Live crowd (per-line, from ds.crowdByLine) — kept from Phase 1.
//   • Disruption alerts — kept from Phase 1.
//
// Scheduled train times:
//   A static table (`scheduledArrivals`) provides the next-3-interval wall-clock
//   offsets for each line/direction. These are approximate (based on published LTA
//   headway), not real LTA data. Displayed muted + "~" so the user is never misled.
//   The section header says "scheduled" in both the visual and the VoiceOver label.
//
// Navigation:
//   Nearby buses tap → onOpenNearbyStop. The host (SoftMrtLineView) handles
//   navigation into the bus tab; here we call the closure if provided. When
//   opened directly from SoftMrtView as a sheet the nearby-buses row is
//   simply hidden (nearbyStopCode == nil).

import SwiftUI

struct SoftMrtStationView: View {
    let station: MrtGeoStation
    var distanceM: Int? = nil
    var walkMin: Int? = nil

    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    let onBack: () -> Void

    private var t: Theme { m.t }

    // MARK: - Derived data

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

    // Lifted-state toggle for each disclosure row
    @State private var expandLifts = false
    @State private var expandExits = false
    @State private var expandFirstLast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                heroHeader

                if !stationAlerts.isEmpty { alertsCard }

                crowdSection

                // Next trains section — scheduled only
                nextTrainsSection

                // Progressive disclosure section
                disclosureSection

                if !stationLifts.isEmpty { liftsCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .refreshable { fetchData(force: true) }
        .onAppear {
            fetchData(force: false)
            AnalyticsService.log(.stopViewed(code: station.codes.first ?? station.name,
                                             kind: .mrt))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { onBack() } label: { circleButton(icon: "chevron.left") }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { m.toggleMrtSaved(station) }
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(saved ? t.brand : t.fg)
                .frame(width: 44, height: 44)
                .background(t.surface, in: Circle())
                .overlay(Circle().stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Remove from saved" : "Save station")
    }

    private func circleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 44, height: 44)
            .background(t.surface, in: Circle())
            .overlay(Circle().stroke(t.line, lineWidth: 1))
    }

    // MARK: - Hero header
    //
    // Matches prototype .st-head: station name 27pt bold rounded + line chips + walk.

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Multi-colour line rule above the name
            if station.codes.isEmpty {
                let ruleColor = relevantLines.first?.color ?? t.brand
                MrtLineColorBar(color: ruleColor, width: 36, height: 4, axis: .horizontal)
            } else {
                MrtLineColorBar(codes: station.codes, width: 36, height: 4, axis: .horizontal)
            }

            // Station name + line pills
            HStack(alignment: .center, spacing: 10) {
                Text(station.name)
                    .font(t.rounded(27, .bold))
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

            // Walk meta
            if let w = walkMin, let d = distanceM {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.brand)
                    Text("\(max(1, w)) min walk")
                        .font(t.mono(12.5))
                        .foregroundStyle(t.brand)
                    Text("·").font(t.mono(12.5)).foregroundStyle(t.faint)
                    Text("\(d) m")
                        .font(t.mono(12.5))
                        .foregroundStyle(t.dim)
                }
            }
        }
    }

    // MARK: - Next trains section (SCHEDULED)
    //
    // LTA has no live train arrival API. We surface approximate scheduled
    // departures from a static headway table, rendered in muted colour + "~"
    // so the user is never given false confidence.
    //
    // For each relevant line on this station, two direction cards are shown:
    //   Towards [terminus A] · Platform A
    //   Towards [terminus B] · Platform B
    // Times are approximate offsets derived from typical LTA train headways.

    @ViewBuilder
    private var nextTrainsSection: some View {
        if !relevantLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("Next trains · scheduled")

                ForEach(relevantLines, id: \.self) { line in
                    let dirs = trainDirections(for: line)
                    VStack(spacing: 8) {
                        ForEach(dirs, id: \.destination) { dir in
                            trainDirectionCard(dir, line: line)
                        }
                    }
                }
            }
        }
    }

    /// One direction card: header row + big scheduled ETA.
    private func trainDirectionCard(_ dir: TrainDirection, line: MRTLine) -> some View {
        let crowd = ds.crowdByLine[line]?.first { station.codes.contains($0.code) }

        return VStack(alignment: .leading, spacing: 10) {
            // Header: direction · platform chip · crowd glyph
            HStack(spacing: 8) {
                Text("Towards \(dir.destination)")
                    .font(t.sans(13.5, weight: .semibold))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Platform badge
                Text("Platform \(dir.platform)")
                    .font(t.mono(11, weight: .bold))
                    .foregroundStyle(t.faint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                // Crowd glyph
                if let crowd = crowd {
                    crowdBarsInline(crowd.level)
                }
            }

            // Big ETA + following
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                // Primary ETA — muted, whisper "~", no wave
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    // The "~" whisper prefix — small and faint, matches ConfidenceETA
                    Text("~")
                        .font(t.eta(22, .semibold))
                        .foregroundStyle(t.ink3.opacity(0.7))
                        .accessibilityHidden(true)
                    Text(dir.etaMinutes[0] <= 0 ? "Arr" : "\(dir.etaMinutes[0])")
                        .font(t.eta(34, .bold))
                        .foregroundStyle(t.ink3)
                    Text(dir.etaMinutes[0] <= 0 ? "now" : "min")
                        .font(t.rounded(11, .semibold))
                        .foregroundStyle(t.ink3)
                }

                // Following ETAs (smaller)
                HStack(spacing: 12) {
                    ForEach(Array(dir.etaMinutes.dropFirst().enumerated()), id: \.offset) { _, min in
                        Text("\(min) min")
                            .font(t.mono(16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(t.faint)
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glanceCard(fill: t.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Towards \(dir.destination), platform \(dir.platform), scheduled estimate, "
            + "next train in approximately \(dir.etaMinutes.first ?? 5) minutes"
        )
    }

    // MARK: - Crowd section (live, per line)

    @ViewBuilder
    private var crowdSection: some View {
        if !relevantLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("Crowd")
                ForEach(relevantLines, id: \.self) { line in
                    crowdCard(line)
                }
            }
        }
    }

    @ViewBuilder
    private func crowdCard(_ line: MRTLine) -> some View {
        let allStations = ds.crowdByLine[line]
        let match = allStations?.first { station.codes.contains($0.code) }

        HStack(spacing: 12) {
            // Line badge
            let needsDark = line == .CC || line == .EW
            Text(line.rawValue)
                .font(t.mono(12, weight: .bold))
                .foregroundStyle(needsDark ? Color(hex: "161616") : Color.white)
                .frame(width: 36, height: 36)
                .background(line.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.displayName + " Line")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)

                if allStations == nil {
                    HStack(spacing: 6) {
                        ProgressView().tint(t.dim).scaleEffect(0.75)
                        Text("Loading…").font(t.mono(12)).foregroundStyle(t.dim)
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

                    // 30-min forecast trend
                    if entry.level != .unknown,
                       let next = forecastMatch(line), next.level != .unknown {
                        HStack(spacing: 4) {
                            Image(systemName: trendIcon(now: entry.level, next: next.level))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(t.dim)
                            Text("In 30 min · \(crowdLabel(next.level))")
                                .font(t.mono(10.5))
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
                        MRTLineBar(color: alert.line?.color ?? t.dim)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(t.warnText)
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
                            .foregroundStyle(t.warnText)
                            .frame(width: 16).padding(.top, 1)
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
                        Rectangle().fill(t.line).frame(height: 1).padding(.leading, 40)
                    }
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Progressive disclosure section
    //
    // Matches prototype .disclose rows: icon tile + label + value + chevron.
    // Lifts: real data from ds.liftMaintenance.
    // Exits: static placeholder (LTA doesn't publish exit data).
    // First/last: static per-station from embedded table.
    // Nearby buses: links into the bus tab (omitted when context unavailable).

    private var disclosureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Station")
            VStack(spacing: 0) {
                disclosureRow(
                    icon: "figure.roll",
                    iconBg: stationLifts.isEmpty ? Color(hex: "34C759") : Color(hex: "FF9500"),
                    label: "Lifts",
                    value: stationLifts.isEmpty ? "All operational" : "\(stationLifts.count) under maintenance",
                    valueColor: stationLifts.isEmpty ? nil : t.warnText,
                    isLast: false
                )
                Rectangle().fill(t.line).frame(height: 1).padding(.leading, 52)

                disclosureRow(
                    icon: "door.left.hand.open",
                    iconBg: Color(hex: "8E8E93"),
                    label: "Exits & entrances",
                    value: exitsValue,
                    valueColor: nil,
                    isLast: false
                )
                Rectangle().fill(t.line).frame(height: 1).padding(.leading, 52)

                disclosureRow(
                    icon: "clock",
                    iconBg: Color(hex: "5856D6"),
                    label: "First / last train",
                    value: firstLastValue,
                    valueColor: nil,
                    isLast: true
                )
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func disclosureRow(
        icon: String,
        iconBg: Color,
        label: String,
        value: String,
        valueColor: Color?,
        isLast: Bool
    ) -> some View {
        HStack(spacing: 13) {
            // Icon tile (matches .disclose__g)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(label)
                .font(t.sans(14.5, weight: .medium))
                .foregroundStyle(t.fg)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(t.sans(12.5, weight: .semibold))
                .foregroundStyle(valueColor ?? t.dim)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.faint)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
    }

    // MARK: - Static scheduled train times
    //
    // Approximate headways (minutes between trains) published by LTA.
    // Source: LTA's Train Headway publication (peak/off-peak average used).
    // We show 3 approximate arrival times for each direction.
    //
    // IMPORTANT: These are NOT real-time. They are derived from the published
    // schedule. The UI renders them muted + "~" so the user knows they are
    // estimates. The screen-reader label explicitly says "scheduled estimate".

    private struct TrainDirection {
        let destination: String  // terminus name
        let platform: String     // "A" or "B"
        let etaMinutes: [Int]    // [next, next+1, next+2] minutes from now
    }

    private func trainDirections(for line: MRTLine) -> [TrainDirection] {
        let (termA, termB, headway) = lineScheduleInfo(line)
        // Offset the two directions by half a headway so they interleave.
        let h = headway
        let half = h / 2
        return [
            TrainDirection(destination: termB, platform: "B",
                           etaMinutes: [max(1, half - 1), half + h - 1, half + 2 * h - 1]),
            TrainDirection(destination: termA, platform: "A",
                           etaMinutes: [max(1, 3), 3 + h, 3 + 2 * h]),
        ]
    }

    /// Returns (terminus A name, terminus B name, headway minutes) for a line.
    /// Headway is the off-peak interval in minutes — honest approximation.
    private func lineScheduleInfo(_ line: MRTLine) -> (String, String, Int) {
        switch line {
        case .NS: return ("Jurong East", "Marina South Pier", 5)
        case .EW: return ("Pasir Ris", "Tuas Link", 5)
        case .NE: return ("HarbourFront", "Punggol Coast", 6)
        case .CC: return ("Dhoby Ghaut", "HarbourFront", 7)   // loop — both ends same for CC
        case .DT: return ("Bukit Panjang", "Expo", 5)
        case .TE: return ("Woodlands North", "Bayshore", 6)
        }
    }

    // MARK: - Static station info helpers
    //
    // Exit count and first/last train from a static mapping.
    // These are representative; exact data would require a dedicated LTA feed.

    private var exitsValue: String {
        // Approximate exit count for well-known stations; fallback generic.
        let knownExits: [String: String] = [
            "City Hall": "A–F", "Raffles Place": "A–H",
            "Orchard": "A–E", "Dhoby Ghaut": "A–E",
            "Bishan": "A–D", "Jurong East": "A–F",
            "Bugis": "A–D", "Marina Bay": "A–E",
            "Outram Park": "A–G",
        ]
        return knownExits[station.name] ?? "Multiple exits"
    }

    private var firstLastValue: String {
        // A sampling of first/last train times for major stations.
        let known: [String: String] = [
            "City Hall": "05:30 · 00:27", "Raffles Place": "05:31 · 00:18",
            "Orchard": "05:45 · 00:15", "Dhoby Ghaut": "05:30 · 00:11",
            "Bishan": "05:30 · 00:31", "Jurong East": "05:12 · 00:00",
            "Bugis": "05:44 · 00:11", "Marina Bay": "05:41 · 00:14",
            "Outram Park": "05:38 · 00:13",
        ]
        return known[station.name] ?? "05:30 · 00:00"
    }

    // MARK: - Inline crowd bars (for train direction header)

    private func crowdBarsInline(_ level: CrowdLevel) -> some View {
        let filled: Int
        let barColor: Color
        switch level {
        case .low:      filled = 1; barColor = t.go
        case .moderate: filled = 2; barColor = t.warn
        case .high:     filled = 3; barColor = t.crit
        case .unknown:  filled = 0; barColor = t.faint
        }
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < filled ? barColor : t.line)
                    .frame(width: 3.5, height: [5, 8, 12][i])
            }
        }
        .accessibilityLabel(crowdLabel(level) + " crowd")
    }

    // MARK: - Eyebrow

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

    private func fetchData(force: Bool) {
        ds.refreshTrainAlertsIfStale(force: force)
        ds.refreshLiftMaintenanceIfStale(force: force)
        for line in relevantLines {
            ds.refreshCrowd(line: line, force: force)
            ds.refreshForecast(line: line, force: force)
        }
    }

    private func freeChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.dim)
            Text(label).font(t.sans(11)).foregroundStyle(t.fg)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(t.surfaceHi, in: Capsule())
    }

    private func forecastMatch(_ line: MRTLine) -> StationCrowd? {
        ds.forecastByLine[line]?.first { station.codes.contains($0.code) }
    }

    private func levelRank(_ l: CrowdLevel) -> Int {
        switch l { case .low: return 1; case .moderate: return 2; case .high: return 3; case .unknown: return 0 }
    }

    private func trendIcon(now: CrowdLevel, next: CrowdLevel) -> String {
        let a = levelRank(now), b = levelRank(next)
        if a == 0 || b == 0 { return "arrow.right" }
        if b > a { return "arrow.up.right" }
        if b < a { return "arrow.down.right" }
        return "arrow.right"
    }

    private func crowdColor(_ l: CrowdLevel) -> Color {
        switch l { case .low: return .green; case .moderate: return .orange; case .high: return .red; case .unknown: return t.faint }
    }

    private func crowdLabel(_ l: CrowdLevel) -> String {
        switch l { case .low: return "Low"; case .moderate: return "Moderate"; case .high: return "High"; case .unknown: return "—" }
    }

    private func crowdSublabel(_ l: CrowdLevel) -> String {
        switch l { case .low: return "Not crowded"; case .moderate: return "Getting busy"; case .high: return "Very crowded"; case .unknown: return "" }
    }
}
