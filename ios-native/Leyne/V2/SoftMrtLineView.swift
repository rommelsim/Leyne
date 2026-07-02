// SoftMrtLineView — per-line detail view pushed from the compact Lines list.
//
// Shows:
//   • Header: line pill + line name + running/disrupted status.
//   • If disrupted: the alert detail + free-bus/shuttle chips.
//   • Live station crowd for that line — Now / Next-30-min toggle,
//     crowd legend, sorted crowd rows.
//   • Loading and empty states.
//
// The crowd rendering is the inline expand from the old SoftMrtView, moved here.

import SwiftUI

struct SoftMrtLineView: View {
    let line: MRTLine
    let onBack: () -> Void

    @Environment(AppModel.self) var m: AppModel
    private let ds = DataStore.shared

    @State private var showForecast = false

    /// When set, the line card swaps to show this station's detail (tapped from
    /// the crowd list); the station view's own back button clears it to return.
    @State private var stationDetail: MrtGeoStation?

    private var t: Theme { m.t }

    /// The alert for this line, if any.
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
        // The sheet itself is the card, so the header + crowd list fill it
        // edge-to-edge (no inner inset card). The sheet surface is t.surface.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                lineHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 14)

                Rectangle().fill(t.line).frame(height: 1)

                if let a = alert {
                    alertCard(a)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }

                crowdSection
                    .padding(.top, 14)
                    .padding(.bottom, 20)
            }
        }
        .background(t.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .refreshable {
            ds.refreshTrainAlertsIfStale(force: true)
            ds.refreshCrowd(line: line, force: true)
            if showForecast { ds.refreshForecast(line: line, force: true) }
        }
        .onAppear {
            ds.refreshTrainAlertsIfStale(force: false)
            ds.refreshCrowd(line: line, force: false)
        }
    }

    // MARK: - Line header

    private var lineHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(line.rawValue)
                .font(t.mono(18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(line.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(line.displayName + " Line")
                    .font(t.sans(22, weight: .bold))
                    .foregroundStyle(t.fg)

                let disrupted = alert != nil
                HStack(spacing: 6) {
                    Circle()
                        .fill(disrupted ? Color.orange : Color.green.opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text(disrupted ? "Disrupted" : "Operating normally")
                        .font(t.sans(13))
                        .foregroundStyle(disrupted ? Color.orange : t.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Alert card

    private func alertCard(_ alert: TrainAlert) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
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
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Crowd section

    @ViewBuilder
    private var crowdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Now / +30 min toggle collapsed into the section header to free
            // vertical space (it used to take a full-width row of its own).
            HStack(spacing: 8) {
                eyebrow("Station crowd")
                Spacer(minLength: 8)
                Picker("", selection: $showForecast) {
                    Text("Now").tag(false)
                    Text(forecastTimeLabel).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: showForecast) { _, isForecast in
                    if isForecast { ds.refreshForecast(line: line) }
                }
            }
            .padding(.horizontal, 16)

            if showForecast {
                crowdList(ds.forecastByLine[line], emptyText: "Forecast unavailable right now.")
            } else {
                crowdList(ds.crowdByLine[line], emptyText: "Crowd data unavailable right now.")
            }
        }
        .animation(.easeInOut(duration: 0.28), value: ds.crowdByLine[line]?.count)
        .animation(.easeInOut(duration: 0.28), value: ds.forecastByLine[line]?.count)
    }

    @ViewBuilder
    private func crowdList(_ items: [StationCrowd]?, emptyText: String) -> some View {
        if let items {
            if items.isEmpty {
                Text(emptyText)
                    .font(t.sans(13))
                    .foregroundStyle(t.faint)
            } else {
                crowdLegend
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                let sorted = sortedCrowd(items)
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, stop in
                        crowdRow(stop)
                        if i < sorted.count - 1 {
                            // Full-bleed divider so the list fills the card width
                            // (matches the header divider above).
                            Rectangle().fill(t.line).frame(height: 1)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().tint(t.dim)
                Text("Loading…").font(t.sans(13)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
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
        // Resolve the geo station so the row can open the station detail.
        let station = MrtGeo.station(forCode: stop.code)
        return Button {
            guard let station else { return }
            Feedback.shared.tap()
            withAnimation(.easeInOut(duration: 0.22)) { stationDetail = station }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(stop.name)
                        .font(t.sans(15, weight: .medium))
                        .foregroundStyle(stop.level == .unknown ? t.dim : t.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    // Station code — wayfinding (how stations are referenced here).
                    Text(stop.code)
                        .font(t.mono(10.5, weight: .medium))
                        .foregroundStyle(t.faint)
                }
                Spacer(minLength: 8)
                crowdGlyph(stop.level)
                if station != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.faint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(CrowdRowButtonStyle(pressedColor: t.surfaceHi))
        .disabled(station == nil)
    }

    /// People-density indicator: three silhouettes, filled + coloured by level
    /// so Low reads visually sparse and High reads full (replaces the signal
    /// bars). The filled count carries the level too, not colour alone.
    private func crowdGlyph(_ level: CrowdLevel) -> some View {
        let filled = switch level {
        case .low:      1
        case .moderate: 2
        case .high:     3
        case .unknown:  0
        }
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(i < filled ? crowdColor(level) : t.line)
            }
        }
        .accessibilityLabel(crowdLabel(level))
    }

    /// Row style with a subtle pressed-background highlight so the tappable
    /// crowd rows feel responsive.
    private struct CrowdRowButtonStyle: ButtonStyle {
        let pressedColor: Color
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? pressedColor : Color.clear)
        }
    }

    // MARK: - Helpers

    private func sortedCrowd(_ items: [StationCrowd]) -> [StationCrowd] {
        items.sorted { codeNum($0.code) < codeNum($1.code) }
    }

    private func codeNum(_ code: String) -> Int {
        Int(code.drop(while: { !$0.isNumber })) ?? 0
    }

    /// Wall-clock time 30 minutes from now (e.g. "10:30 AM") for the forecast
    /// toggle — concrete instead of a vague "+30 min". Read in `body`, which
    /// re-renders on the app's ~1-second tick, so it rolls to the next minute
    /// on its own and always reflects the current time.
    private var forecastTimeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_SG")
        f.dateFormat = m.use24h ? "HH:mm" : "h:mm a"
        return f.string(from: Date().addingTimeInterval(30 * 60))
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

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(t.mono(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(t.dim)
            .padding(.leading, 2)
    }
}
