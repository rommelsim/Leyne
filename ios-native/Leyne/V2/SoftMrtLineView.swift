// SoftMrtLineView — Glance Phase 2 visual line diagram.
//
// Spec (screenLine + .diagram / .dg-* CSS):
//   • Vertical coloured spine (line colour, `--x` unit = 7pt in prototype).
//   • Station nodes: normal = 14×14 hollow circle with line-colour border.
//   • Interchange nodes: 22×22, double ring (outer box-shadow in CSS → here
//     an `.overlay` stroke ring), showing connecting-line mini chips.
//   • Terminus caps: filled circle (dg-stop.term fills the node).
//   • You-are-here: brand-coloured node + expanding pulse ring animation.
//   • Crowd: ascending bars (Low=1, Moderate=2, High=3 bars filled) —
//     shape-encoded per spec ("never colour-alone").
//   • Direction segmented control → swaps direction of diagram.
//   • Circle line loop overview: small SVG-like circle drawn with SwiftUI.
//   • Tap any station node → pushes SoftMrtStationView inline (ZStack swap).
//
// Geometry: derived from a single unit `x = 7`. Spine x-offset = 20pt.
// Node sizes:
//   normal:       14×14  (2x)
//   interchange:  22×22  (3.14x)
//   terminus:     14×14 filled
//   you:          22×22 brand fill + pulse
//
// Data:
//   • Ordered stations derived from MrtGeo.all, sorted by the numeric part of
//     their line-specific code (e.g. NS1 < NS2 … < NS27). This gives the
//     correct geographic sequence without embedding a separate data file.
//   • Nearest station (for you-are-here) derived from MrtGeo.nearestStation.
//   • Live crowd from ds.crowdByLine[line].
//   • Alert from ds.trainAlerts.
//   • Lift maintenance from ds.liftMaintenance (used for station alert dots).

import SwiftUI
import CoreLocation

struct SoftMrtLineView: View {
    let line: MRTLine
    let onBack: () -> Void

    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    @StateObject private var loc = LocationManager.shared

    // 0 = toward terminus B (ascending code order); 1 = toward terminus A
    @State private var direction: Int = 0
    @State private var stationDetail: MrtGeoStation?

    private var t: Theme { m.t }

    // TfL line-diagram unit: derive all geometry from this one value.
    private let x: CGFloat = 7
    private var spineX: CGFloat { 20 }
    private var spineWidth: CGFloat { x }

    // MARK: - Derived data

    /// All stations on this line, sorted in ascending code-number order.
    /// Code prefix mapping mirrors `lineFromCode` in SoftMrtStationView.
    private var orderedStations: [MrtGeoStation] {
        let prefix = lineCodes(for: line)
        var result: [(Int, MrtGeoStation)] = []
        for station in MrtGeo.all {
            let matchingCode = station.codes.first(where: { code in
                prefix.contains(where: { code.uppercased().hasPrefix($0) })
            })
            if let mc = matchingCode {
                let num = extractNum(mc)
                result.append((num, station))
            }
        }
        result.sort { $0.0 < $1.0 }
        return result.map { $0.1 }
    }

    /// Displayable station list — reversed when direction == 1.
    private var displayStations: [MrtGeoStation] {
        direction == 1 ? orderedStations.reversed() : orderedStations
    }

    private var terminusA: String { orderedStations.first?.name ?? "" }
    private var terminusB: String { orderedStations.last?.name ?? "" }

    /// The station nearest to the user on this line, for "you are here".
    private var nearestOnLine: MrtGeoStation? {
        guard let loc = loc.location else { return nil }
        let prefix = lineCodes(for: line)
        return orderedStations.min(by: { a, b in
            haversineMeters(loc.coordinate, a) < haversineMeters(loc.coordinate, b)
        })
    }

    private var alert: TrainAlert? {
        ds.trainAlerts.first { $0.line == line }
    }

    var body: some View {
        ZStack {
            if let station = stationDetail {
                SoftMrtStationView(station: station,
                                   distanceM: nil,
                                   walkMin: nil,
                                   onBack: {
                                       withAnimation(.easeInOut(duration: 0.25)) {
                                           stationDetail = nil
                                       }
                                   })
                    .transition(.move(edge: .trailing))
            } else {
                lineContent
                    .transition(.move(edge: .leading))
            }
        }
    }

    private var lineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                lineHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 14)

                Rectangle().fill(t.line).frame(height: 1)

                if let a = alert {
                    alertBanner(a)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // Circle line: show loop overview pill
                if line == .CC {
                    loopOverview
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // Direction segmented control
                directionControl
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // Crowd legend
                crowdLegend
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                // Visual line diagram
                diagram
                    .padding(.top, 6)
                    .padding(.bottom, 28)
            }
        }
        .background(t.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .refreshable {
            ds.refreshTrainAlertsIfStale(force: true)
            ds.refreshCrowd(line: line, force: true)
        }
        .onAppear {
            loc.startIfAuthorized()
            ds.refreshTrainAlertsIfStale(force: false)
            ds.refreshCrowd(line: line, force: false)
        }
    }

    // MARK: - Line header

    private var lineHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // Line badge
            let needsDark = line == .CC || line == .EW
            Text(line.rawValue)
                .font(t.mono(18, weight: .bold))
                .foregroundStyle(needsDark ? Color(hex: "161616") : Color.white)
                .frame(width: 52, height: 52)
                .background(line.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(line.displayName + " Line")
                    .font(t.sans(22, weight: .bold))
                    .foregroundStyle(t.fg)

                let disrupted = alert != nil
                HStack(spacing: 6) {
                    Circle()
                        .fill(disrupted ? t.warn : t.brand)
                        .frame(width: 8, height: 8)
                    Text(disrupted ? "Delays" : "Normal service")
                        .font(t.sans(13))
                        .foregroundStyle(disrupted ? t.warnText : t.dim)
                }
            }

            Spacer(minLength: 0)

            // Back button — this diagram is a pushed navigation page (not a
            // bottom sheet), so it uses a back chevron, not a downward "dismiss"
            // chevron. Popping returns to the MRT network board.
            Button { onBack() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 36, height: 36)
                    .background(t.surfaceHi, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
        }
    }

    // MARK: - Alert banner

    private func alertBanner(_ alert: TrainAlert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.warnText)
                Text(alert.title)
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
            }
            Text(alert.detail)
                .font(t.sans(13))
                .foregroundStyle(t.dim)
                .fixedSize(horizontal: false, vertical: true)

            if alert.freeBus || alert.freeShuttle {
                HStack(spacing: 6) {
                    if alert.freeBus    { freeChip(icon: "bus.fill",  label: "Free bus rides") }
                    if alert.freeShuttle { freeChip(icon: "tram.fill", label: "Free MRT shuttle") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.warnBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Circle line loop overview
    //
    // Matches prototype: `<svg … stroke="var(--cc)" …><circle/></svg>
    // Loop line — runs both directions`.

    private var loopOverview: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(line.color, lineWidth: 5)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 34, height: 34)

            Text("Loop line — runs in both directions")
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(t.dim)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glanceCard(fill: t.surface)
    }

    // MARK: - Direction control
    //
    // Segmented button pair: "Towards [termB]" / "Towards [termA]".
    // The displayed `termA`/`termB` labels always refer to the original
    // ascending-order termini so they stay stable; swapping direction just
    // reverses `displayStations`.

    private var directionControl: some View {
        HStack(spacing: 0) {
            dirButton(label: "Towards \(terminusB)", tag: 0)
            dirButton(label: "Towards \(terminusA)", tag: 1)
        }
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(4)
        .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dirButton(label: String, tag: Int) -> some View {
        Button {
            Feedback.shared.tap()
            withAnimation(.easeInOut(duration: 0.2)) { direction = tag }
        } label: {
            Text(label)
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(direction == tag ? t.fg : t.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    direction == tag
                    ? AnyShapeStyle(t.surface.shadow(.drop(color: Color.black.opacity(0.08),
                                                           radius: 4, y: 2)))
                    : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(direction == tag ? .isSelected : [])
    }

    // MARK: - Crowd legend
    //
    // Ascending-bars shape. Three pairs — Seats / Standing / Crowded.
    // Same bar glyph as on the diagram rows so the legend directly decodes
    // what the user sees inline.

    private var crowdLegend: some View {
        HStack(spacing: 14) {
            legendItem(level: .low,      label: "Seats")
            legendItem(level: .moderate, label: "Standing")
            legendItem(level: .high,     label: "Crowded")
            Spacer(minLength: 0)
        }
    }

    private func legendItem(level: CrowdLevel, label: String) -> some View {
        HStack(spacing: 5) {
            crowdBars(level, compact: true)
            Text(label)
                .font(t.mono(11, weight: .medium))
                .foregroundStyle(t.dim)
        }
    }

    // MARK: - Diagram
    //
    // A ZStack: the spine is position-absolute in the prototype (left: 20px);
    // here we use an HStack with a fixed-width leading column anchoring the
    // spine and nodes, and trailing content for name + chips + crowd.

    private var diagram: some View {
        let stations = displayStations
        let nearestId = nearestOnLine?.id
        let count = stations.count

        // Each row has minHeight 52pt. The spine runs from the centre of row 0's
        // node to the centre of the last row's node. Placing the spine as an
        // overlay behind the VStack — keyed to the VStack's actual height — avoids
        // a GeometryReader chicken-and-egg. We draw it from top to bottom and let
        // the row nodes punch holes in it visually (white fill on top of spine).
        return VStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                let isFirst = index == 0
                let isLast  = index == count - 1
                let isTerm  = isFirst || isLast
                let isYou   = station.id == nearestId
                let isIx    = isInterchange(station)

                diagramRow(station, isTerm: isTerm, isYou: isYou, isIx: isIx)
            }
        }
        // Spine overlay — aligns to leading edge at spineX, trimmed by
        // node-half (7pt) at each end so it doesn't jut past the termini.
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: spineWidth / 2, style: .continuous)
                .fill(line.color)
                .frame(width: spineWidth)
                .padding(.top, 26)         // half of first-row height → centres on terminus node
                .padding(.bottom, 26)      // symmetric at last row
                .frame(maxHeight: .infinity)
                // The `.padding(.horizontal, 16)` below is applied AFTER this
                // overlay, so it already shifts the spine right by 16 — adding
                // 16 here again double-counted it and pushed the spine off the
                // station nodes. Offset is measured within the padded frame.
                .offset(x: spineX - spineWidth / 2)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
    }

    private func diagramRow(
        _ station: MrtGeoStation,
        isTerm: Bool,
        isYou: Bool,
        isIx: Bool
    ) -> some View {
        // Node geometry — "x" unit = 7pt, spine at x=20pt from left edge.
        // Leading column = 58pt: places spine at 20pt and leaves room for the
        // 22pt interchange node (centred on spine). Content starts at 58pt.
        let leadW: CGFloat      = 58
        let normalNodeD: CGFloat = 14
        let bigNodeD: CGFloat   = 22
        let nodeD: CGFloat      = (isIx || isYou) ? bigNodeD : normalNodeD

        // Crowd data for this station on this line
        let crowdEntry = ds.crowdByLine[line]?.first { station.codes.contains($0.code) }

        return Button {
            Feedback.shared.tap()
            withAnimation(.easeInOut(duration: 0.22)) { stationDetail = station }
        } label: {
            HStack(alignment: .center, spacing: 0) {
                // --- Leading column: holds the node, centred on the spine ---
                // The spine is rendered behind the whole diagram; this column
                // only positions the node dot. We use a fixed width so every
                // row's text starts at the same x coordinate.
                ZStack {
                    if isYou {
                        youPulse(diameter: nodeD)
                    } else if isTerm {
                        Circle()
                            .fill(line.color)
                            .frame(width: normalNodeD, height: normalNodeD)
                    } else if isIx {
                        Circle()
                            .fill(t.surface)
                            .frame(width: nodeD, height: nodeD)
                            .overlay(Circle().stroke(line.color, lineWidth: 3))
                            .overlay(Circle().stroke(t.fg.opacity(0.18), lineWidth: 1.5).padding(-3))
                    } else {
                        Circle()
                            .fill(t.surface)
                            .frame(width: nodeD, height: nodeD)
                            .overlay(Circle().stroke(line.color, lineWidth: 3))
                    }
                }
                // Centre the node on spineX within the leading column.
                .frame(width: leadW, height: 52, alignment: .leading)
                .padding(.leading, spineX - nodeD / 2)
                .accessibilityHidden(true)

                // --- Content column: name + interchange chips + crowd ---
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Station name — terminus is heavier, you-are-here is brand coloured.
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(station.name)
                                .font(isTerm ? t.sans(17, weight: .bold)
                                      : isYou ? t.sans(15.5, weight: .bold)
                                      : t.sans(15, weight: .medium))
                                .foregroundStyle(isYou ? t.brand : t.fg)
                            if isYou {
                                Text("· nearest")
                                    .font(t.sans(12, weight: .medium))
                                    .foregroundStyle(t.brand)
                            }
                        }

                        // Interchange connecting-line chips
                        if isIx {
                            HStack(spacing: 4) {
                                ForEach(connectingLineCodes(station), id: \.self) { code in
                                    miniChip(code)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Crowd glyph (ascending bars, shape-encoded)
                    if let entry = crowdEntry {
                        crowdBars(entry.level, compact: false)
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, isTerm ? 12 : 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessLabel(station, isYou: isYou, crowd: crowdEntry?.level))
        .accessibilityHint("Open station detail")
    }

    // MARK: - You-are-here pulse
    //
    // Brand-coloured node + expanding ring animation.
    // Matches `.dg-stop.you .dg-node { animation: youring 2s ease-out infinite }`.

    private func youPulse(diameter: CGFloat) -> some View {
        ZStack {
            // Expanding pulse ring
            Circle()
                .fill(t.brand.opacity(0.20))
                .frame(width: diameter + 14, height: diameter + 14)
                .modifier(PulseRing(color: t.brand))

            // Filled node
            Circle()
                .fill(t.brand)
                .frame(width: diameter, height: diameter)
        }
    }

    // MARK: - Crowd bars
    //
    // Three ascending-height bars. `compact` = smaller for legend; normal for diagram.
    // Shape encodes the level (fill count 1/2/3) in addition to colour.

    private func crowdBars(_ level: CrowdLevel, compact: Bool) -> some View {
        let filled: Int
        let barColor: Color
        switch level {
        case .low:      filled = 1; barColor = t.go
        case .moderate: filled = 2; barColor = t.warn
        case .high:     filled = 3; barColor = t.crit
        case .unknown:  filled = 0; barColor = t.faint
        }
        let w: CGFloat = compact ? 3   : 3.5
        let heights: [CGFloat] = compact
            ? [4, 7, 10]
            : [5, 8, 12]

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < filled ? barColor : t.line)
                    .frame(width: w, height: heights[i])
            }
        }
        .accessibilityLabel(crowdAccessLabel(level))
        .accessibilityHidden(false)
    }

    // MARK: - Mini line chip (for interchange connecting lines)

    private func miniChip(_ code: String) -> some View {
        let prefix = String(code.prefix(2)).uppercased()
        let displayPrefix: String = prefix == "CG" ? "EW" : prefix == "CE" ? "CC" : prefix
        let needsDark = displayPrefix == "CC" || displayPrefix == "EW"
        return Text(displayPrefix)
            .font(t.mono(10, weight: .bold))
            .foregroundStyle(needsDark ? Color(hex: "161616") : Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(mrtLineColorFor(code), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Free service chip

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

    // MARK: - Helpers

    /// Returns the 2-letter code prefixes for a given MRTLine, including branch codes.
    private func lineCodes(for line: MRTLine) -> [String] {
        switch line {
        case .NS: return ["NS"]
        case .EW: return ["EW", "CG"]
        case .NE: return ["NE"]
        case .CC: return ["CC", "CE"]
        case .DT: return ["DT"]
        case .TE: return ["TE"]
        }
    }

    /// True when a station has codes from more than one line (interchange).
    private func isInterchange(_ station: MrtGeoStation) -> Bool {
        let prefixes = Set(station.codes.map { code -> String in
            let p = String(code.prefix(2)).uppercased()
            // Normalise branch codes to their parent line
            if p == "CG" { return "EW" }
            if p == "CE" { return "CC" }
            return p
        })
        return prefixes.count > 1
    }

    /// Returns codes for the connecting lines at an interchange (excluding this line).
    private func connectingLineCodes(_ station: MrtGeoStation) -> [String] {
        let myPrefixes = Set(lineCodes(for: line))
        // Return one representative code per connecting line prefix
        var seen: Set<String> = []
        var result: [String] = []
        for code in station.codes {
            let p = String(code.prefix(2)).uppercased()
            let norm = (p == "CG") ? "EW" : (p == "CE") ? "CC" : p
            guard !myPrefixes.contains(p), !myPrefixes.contains(norm) else { continue }
            guard seen.insert(norm).inserted else { continue }
            result.append(code)
        }
        return result
    }

    /// Extracts the numeric suffix from a station code like "NS17" → 17.
    private func extractNum(_ code: String) -> Int {
        Int(code.drop(while: { !$0.isNumber })) ?? 0
    }

    private func haversineMeters(_ a: CLLocationCoordinate2D, _ s: MrtGeoStation) -> Double {
        haversine(a.latitude, a.longitude, s.lat, s.lon)
    }

    private func crowdAccessLabel(_ l: CrowdLevel) -> String {
        switch l {
        case .low:      return "Low crowd"
        case .moderate: return "Moderate crowd"
        case .high:     return "High crowd"
        case .unknown:  return "Crowd unknown"
        }
    }

    private func accessLabel(_ s: MrtGeoStation, isYou: Bool, crowd: CrowdLevel?) -> String {
        let you = isYou ? ", nearest to you" : ""
        let c = crowd.map { ", \(crowdAccessLabel($0))" } ?? ""
        return "\(s.name)\(you)\(c)"
    }
}

// MARK: - Pulse ring animation modifier

/// Expanding concentric ring that fades out — matches the `.youring` CSS keyframe.
private struct PulseRing: ViewModifier {
    let color: Color
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color.opacity(animate ? 0 : 0.45), lineWidth: 2)
                    .scaleEffect(animate ? 1.6 : 0.7)
                    .animation(
                        .easeOut(duration: 2).repeatForever(autoreverses: false),
                        value: animate
                    )
            )
            .onAppear { animate = true }
    }
}
