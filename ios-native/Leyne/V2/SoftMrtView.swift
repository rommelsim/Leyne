// SoftMrtView — the MRT tab (Leyne 2.7 Phase 3 redesign).
//
// Layout (top → bottom):
//   1. Title "MRT" + ••• menu (system map / news & advisories).
//   2. Disruption banner — compact, only when a line is affected.
//   3. Saved stations section — user's saved MRT stations (omit when empty).
//   4. Closest to you — nearest stations, capped at 3.
//   5. Lines section — compact one-row-per-line list; tap → SoftMrtLineView.
//
// Lift maintenance has moved to SoftMrtNewsView.
// Live station crowd has moved to SoftMrtLineView (expanded inline was too long).

import SwiftUI
import CoreLocation

struct SoftMrtView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    @StateObject private var loc = LocationManager.shared

    /// Controls the full-screen system-map sheet.
    @State private var showMap = false

    /// Nearest stations within the user's search radius, rebuilt on location or
    /// radius changes. Capped at 3 per the redesign.
    @State private var nearestStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] = []

    /// The absolute nearest station, regardless of radius — used for the
    /// empty-state "nearest outside radius" hint.
    @State private var absoluteNearest: (station: MrtGeoStation, distanceM: Int, walkMin: Int)? = nil

    let onOpenLine: (MRTLine) -> Void
    let onOpenNews: () -> Void

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
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                topDisruptionBanner
                if !m.savedMrtStations.isEmpty { savedSection }
                nearestSection
                linesSection
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
        .sheet(isPresented: $showMap) {
            MrtMapView()
        }
    }

    // MARK: - Nearest list builder

    private func rebuildNearest(_ loc: CLLocation) {
        nearestStations = MrtGeo.nearestStations(
            to: loc.coordinate,
            limit: 3,
            withinMeters: m.searchRadiusM
        )
        absoluteNearest = MrtGeo.nearestStation(to: loc.coordinate)
    }

    private func refresh(force: Bool) {
        ds.refreshTrainAlertsIfStale(force: force)
        ds.refreshLiftMaintenanceIfStale(force: force)
        if let l = loc.location { rebuildNearest(l) }
    }

    // MARK: - Title block

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MRT")
                    .font(t.sans(32, weight: .bold))
                    .foregroundStyle(t.fg)
                Text("Stations near you")
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 8)
            moreMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Top-right ••• menu — system map and news/advisories.
    private var moreMenu: some View {
        Menu {
            Button {
                Feedback.shared.tap()
                showMap = true
            } label: {
                Label("System map", systemImage: "map.fill")
            }
            Button {
                Feedback.shared.tap()
                onOpenNews()
            } label: {
                Label("News & advisories", systemImage: "newspaper.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: - Top disruption banner

    @ViewBuilder
    private var topDisruptionBanner: some View {
        let count = disruptedLines.count
        if count > 0 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("\(count) line\(count == 1 ? "" : "s") disrupted")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                HStack(spacing: 4) {
                    ForEach(Array(disruptedLines.keys).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { line in
                        Text(line.rawValue)
                            .font(t.mono(10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(line.color, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.8))
                Text("All lines running normally")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }
        }
    }

    // MARK: - Saved stations section

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Saved")
            ForEach(m.savedMrtStations, id: \.id) { station in
                NavigationLink(value: SoftMrtRoute.station(station)) {
                    compactStationRow(station)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("\(station.name) MRT station, saved")
            }
        }
    }

    // MARK: - Nearest stations section

    @ViewBuilder
    private var nearestSection: some View {
        if nearestStations.isEmpty {
            if !loc.authorized {
                SoftEmptyState(
                    t: t,
                    onNearby: { loc.requestAndStart() },
                    onSearch: {}
                )
            } else if loc.location != nil {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Closest to you")
                    noStationWithinRadiusCard
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Closest to you")
                ForEach(nearestStations, id: \.station.id) { entry in
                    nearbyStationCard(entry.station,
                                      distanceM: entry.distanceM,
                                      walkMin: entry.walkMin)
                }
            }
        }
    }

    private var noStationWithinRadiusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tram")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(t.dim)
                Text("No MRT stations within \(radiusLabel(m.searchRadiusM)).")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
            }
            if let hint = absoluteNearest {
                Text("Nearest: \(hint.station.name) · \(hint.distanceM) m away — widen your radius in Settings.")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func radiusLabel(_ metres: Int) -> String {
        if metres < 1000 { return "\(metres) m" }
        let km = Double(metres) / 1000
        if metres % 1000 == 0 { return "\(Int(km)) km" }
        return String(format: "%.1f km", km)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }

    // MARK: - Nearby station card (with walk meta)

    private func nearbyStationCard(
        _ station: MrtGeoStation,
        distanceM: Int,
        walkMin: Int
    ) -> some View {
        NavigationLink(value: SoftMrtRoute.station(station, distanceM: distanceM, walkMin: walkMin)) {
            HStack(spacing: 0) {
                MrtLineColorBar(codes: station.codes, width: 4, height: 44)
                VStack(alignment: .center, spacing: 3) {
                    ForEach(station.codes, id: \.self) { code in
                        lineCodePill(code)
                    }
                }
                .frame(width: 52, alignment: .center)
                .padding(.leading, 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.soon)
                        Text("\(max(1, walkMin)) min")
                            .foregroundStyle(t.soon)
                        Text("·").foregroundStyle(t.faint)
                        Text("\(distanceM) m")
                            .foregroundStyle(t.dim)
                    }
                    .font(t.mono(12.5))
                }
                .padding(.leading, 8)

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .contentShape(Rectangle())
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(station.name) MRT station, \(max(1, walkMin)) minute walk")
    }

    // MARK: - Compact station row (saved section — no walk meta)

    private func compactStationRow(_ station: MrtGeoStation) -> some View {
        HStack(spacing: 0) {
            MrtLineColorBar(codes: station.codes, width: 4, height: 40)
            VStack(alignment: .center, spacing: 3) {
                ForEach(station.codes, id: \.self) { code in
                    lineCodePill(code)
                }
            }
            .frame(width: 52, alignment: .center)
            .padding(.leading, 10)

            Text(station.name)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .padding(.leading, 8)

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.faint)
        }
        .contentShape(Rectangle())
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1)
        )
    }

    private func lineCodePill(_ code: String) -> some View {
        Text(code)
            .font(t.mono(11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Uniform min width so stacked codes (e.g. EW24 + NS1 at an
            // interchange) are the SAME width and line up as a tidy column,
            // rather than each capsule hugging its text.
            .frame(minWidth: 48)
            .background(mrtLineColorFor(code), in: Capsule())
    }

    // MARK: - Lines section (compact one-row-per-line)

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Lines")
            VStack(spacing: 8) {
                ForEach(MRTLine.allCases, id: \.self) { line in
                    compactLineRow(line, alert: disruptedLines[line])
                }
            }
        }
    }

    private func compactLineRow(_ line: MRTLine, alert: TrainAlert?) -> some View {
        let disrupted = alert != nil
        return Button {
            Feedback.shared.tap()
            onOpenLine(line)
        } label: {
            HStack(spacing: 12) {
                // Line pill
                Text(line.rawValue)
                    .font(t.mono(12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(line.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Name
                Text(line.displayName + " Line")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Status dot
                Circle()
                    .fill(disrupted ? Color.orange : Color.green.opacity(0.8))
                    .frame(width: 8, height: 8)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(line.displayName) Line, \(disrupted ? "disrupted" : "operating normally")")
    }
}

extension CrowdLevel: Hashable {}
