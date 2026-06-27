// SoftMrtView — the MRT tab (Leyne 2.7 Phase 3 redesign).
//
// Layout (top → bottom):
//   1. Title "MRT" + ••• menu (system map / news & advisories).
//   2. Disruption banner — compact, only when a line is affected.
//   3. Closest to you — nearest stations, capped at 3.
//   4. Lines section — compact one-row-per-line list; tap → SoftMrtLineView.
//
// Lift maintenance has moved to SoftMrtNewsView.
// Live station crowd has moved to SoftMrtLineView (expanded inline was too long).

import SwiftUI
import CoreLocation

struct SoftMrtView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared
    @StateObject private var loc = LocationManager.shared

    /// Which card/sheet is presented (nil = none). SwiftUI reliably honours only
    /// ONE `.sheet` modifier per view, so the previous three separate sheets made
    /// the map (the first-declared) silently fail to present. Driving every sheet
    /// from this single enum via one `.sheet(item:)` is the fix.
    @State private var activeSheet: MrtSheet?

    /// The card SoftMrtView can present from its own content: a line detail or a
    /// station detail. Identifiable so it can drive a single `.sheet(item:)`.
    /// (The system map is NOT here — it presents from the nav-stack level via
    /// `onOpenSystemMap`, since a toolbar-triggered sheet on this `.searchable`
    /// view won't appear.)
    private enum MrtSheet: Identifiable {
        case line(MRTLine)
        case station(MrtGeoStation)

        var id: String {
            switch self {
            case .line(let line):   return "line-\(line.rawValue)"
            case .station(let stn): return "station-\(stn.id)"
            }
        }
    }

    /// Nearest stations within the user's search radius, rebuilt on location or
    /// radius changes. Capped at 3 per the redesign.
    @State private var nearestStations: [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] = []

    /// The absolute nearest station, regardless of radius — used for the
    /// empty-state "nearest outside radius" hint.
    @State private var absoluteNearest: (station: MrtGeoStation, distanceM: Int, walkMin: Int)? = nil

    let onOpenLine: (MRTLine) -> Void
    let onOpenNews: () -> Void
    /// Search-result taps that aren't MRT stations route back to the Bus tab.
    let onOpenStop: (String) -> Void
    let onOpenBus: (String, String) -> Void
    /// Presents the shared Alerts sheet (service status / your alerts) — mirrors
    /// the Home bell so disruptions are reachable from the MRT tab too.
    let onOpenAlerts: () -> Void
    /// Presents the zoomable MRT system map. Routed up to the nav-stack level
    /// (handled by SoftRoot) rather than an in-view `.sheet`: a sheet presented
    /// from THIS `.searchable` view's toolbar button does not reliably appear,
    /// which is why the map button looked dead. The alerts bell works for the
    /// same reason — it presents from an ancestor, not from here.
    let onOpenSystemMap: () -> Void

    /// Drives the native iOS 26 `.searchable` bar; focusing it swaps the network
    /// view for live results.
    @State private var searchText = ""
    @State private var searchActive = false

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
        Group {
            if searchActive {
                // Same engine + results as Home, embedded under MRT's native
                // search bar. Station results open the existing station card;
                // stop / bus results route back to the Bus tab.
                SoftSearchView(
                    externalText: $searchText,
                    onClose: { searchActive = false },
                    onOpenStop: onOpenStop,
                    onOpenBus: onOpenBus,
                    onOpenMrtStation: { activeSheet = .station($0) }
                )
                .transition(.opacity)
            } else {
                networkScroll
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: searchActive)
        // `.automatic` lets the search bar ride in the scroll view's header so
        // it slides away as the page scrolls down and returns on scroll up.
        .searchable(text: $searchText, isPresented: $searchActive,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search stops, buses, stations")
        // Compact inline title fills the previously-empty nav bar (no more dead
        // space); the search field rides in the drawer below it. The map button
        // keeps the top-right corner it has always occupied on MRT, with the new
        // alerts bell to its left. Order matters: SwiftUI renders the LAST
        // trailing item at the corner, so mapButton is declared last.
        .navigationTitle("MRT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { alertsBell }
            ToolbarItem(placement: .topBarTrailing) { mapButton }
        }
        .background(t.bg.ignoresSafeArea())
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
        // One `.sheet(item:)` drives the content-triggered cards — a line detail
        // or a station detail. (The system map is presented from the nav-stack
        // level; see onOpenSystemMap.)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .line(let line):
                SoftMrtLineView(line: line, onBack: { activeSheet = nil })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .station(let station):
                SoftMrtStationView(station: station,
                                   distanceM: nil,
                                   walkMin: nil,
                                   onBack: { activeSheet = nil })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// The network / nearest-stations view, shown when search is not active.
    private var networkScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                topDisruptionBanner
                // One native ad per screen. NativeAdCard renders EmptyView when
                // no ad is loaded or ads are suppressed; no gap otherwise.
                NativeAdCard()
                networkSection
            }
            .padding(20)
        }
        .refreshable { refresh(force: true) }
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
        // "MRT" + map button now live in the nav bar; this stays as the section
        // subtitle under the search field.
        Text("Stations near you")
            .font(t.sans(15, weight: .semibold))
            .foregroundStyle(t.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Top-right button — opens the zoomable system map. (Previously a ••• menu
    /// that also held "News & advisories"; that content now lives in the
    /// Alerts tab, so this collapses to a direct map button.)
    private var mapButton: some View {
        // Plain toolbar button — iOS 26 sizes and glass-styles it.
        Button {
            Feedback.shared.tap()
            onOpenSystemMap()
        } label: {
            Image(systemName: "map.fill")
        }
        .accessibilityLabel("System map")
    }

    /// Trailing alerts bell — mirrors the Home tab so service disruptions and the
    /// user's alerts are reachable here too. Raises the same shared Alerts sheet;
    /// the unseen badge uses the system `bell.badge.fill` dot.
    private var alertsBell: some View {
        Button {
            Feedback.shared.select(); onOpenAlerts()
        } label: {
            Image(systemName: m.unseenAlertCount > 0 ? "bell.badge.fill" : "bell.fill")
        }
        .accessibilityLabel(m.unseenAlertCount > 0
            ? "Alerts, \(m.unseenAlertCount) new"
            : "Alerts")
    }

    // MARK: - Top disruption banner

    @ViewBuilder
    private var topDisruptionBanner: some View {
        let count = disruptedLines.count
        if count > 0 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.warn)
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
            .background(t.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.soon)
                Text("All lines running normally")
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }
        }
    }

    // MARK: - Nearest stations section

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }

    // MARK: - Nearest featured tile (grid header, spans full width)

    /// The user's nearest station as the Network grid's featured header tile —
    /// full width above the 2-column line grid. Walk eyebrow + station name +
    /// line-code pills + walk/distance meta. Opens the station detail as a card.
    private func nearestFeaturedTile(
        _ entry: (station: MrtGeoStation, distanceM: Int, walkMin: Int)
    ) -> some View {
        let station = entry.station
        return Button {
            Feedback.shared.tap()
            activeSheet = .station(station)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Eyebrow — walk glyph + "Nearest MRT"
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.soon)
                    Text("Nearest MRT")
                        .font(t.mono(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(t.dim)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.faint)
                }
                // Station name + line-code pills
                HStack(alignment: .center, spacing: 8) {
                    Text(station.name)
                        .font(t.sans(20, weight: .bold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        ForEach(station.codes, id: \.self) { code in
                            MrtCodePill(t: t, code: code)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // Meta — walk minutes · distance
                HStack(spacing: 5) {
                    Text("\(max(1, entry.walkMin)) min")
                        .foregroundStyle(t.soon)
                    Text("·").foregroundStyle(t.faint)
                    Text("\(entry.distanceM) m away")
                        .foregroundStyle(t.dim)
                }
                .font(t.mono(12.5))
            }
            .contentShape(Rectangle())
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Nearest MRT, \(station.name), \(max(1, entry.walkMin)) minute walk")
    }

    // MARK: - Network section (nearest station + line grid)

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Network")
            // Your nearest station as the grid's featured header tile (full
            // width), folded in from the old "Closest to you" section. Opens
            // its detail as a card. Shown only when located.
            if let nearest = nearestStations.first {
                nearestFeaturedTile(nearest)
            }
            // A 2-column grid of colour tiles instead of a row-per-line list —
            // more glanceable, and each tile taps into the per-line detail.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(MRTLine.allCases, id: \.self) { line in
                    lineTile(line, alert: disruptedLines[line])
                }
            }
        }
    }

    /// One MRT line as a tappable colour tile: line badge + at-a-glance status
    /// chip on top, line name + status text below. Opens the per-line detail.
    private func lineTile(_ line: MRTLine, alert: TrainAlert?) -> some View {
        let disrupted = alert != nil
        return Button {
            Feedback.shared.tap()
            activeSheet = .line(line)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(line.rawValue)
                        .font(t.mono(13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 28)
                        .background(line.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer(minLength: 0)
                    Image(systemName: disrupted ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(disrupted ? t.warn : t.soon)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.displayName)
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(disrupted ? "Disrupted" : "Normal service")
                        .font(t.sans(11))
                        .foregroundStyle(disrupted ? t.warn : t.dim)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(disrupted ? t.warn.opacity(0.4) : t.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(line.displayName) Line, \(disrupted ? "disrupted" : "operating normally")")
    }
}

extension CrowdLevel: Hashable {}

// Lets a tapped line drive a `.sheet(item:)` card presentation.
extension MRTLine: Identifiable { public var id: String { rawValue } }
