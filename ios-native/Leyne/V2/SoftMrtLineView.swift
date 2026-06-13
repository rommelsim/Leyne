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

    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared

    @State private var showForecast = false

    private var t: Theme { m.t }

    /// The alert for this line, if any.
    private var alert: TrainAlert? {
        ds.trainAlerts.first { $0.line == line }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                lineHeader
                if let a = alert {
                    alertCard(a)
                }
                crowdSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(t.bg.ignoresSafeArea())
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { onBack() } label: {
                circleButton(icon: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func circleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 44, height: 44)
            .background(t.surface, in: Circle())
            .overlay(Circle().stroke(t.line, lineWidth: 1))
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
            eyebrow("Live station crowd")

            Picker("", selection: $showForecast) {
                Text("Now").tag(false)
                Text("Next 30 min").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: showForecast) { _, isForecast in
                if isForecast { ds.refreshForecast(line: line) }
            }

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
                    .padding(.bottom, 4)
                VStack(spacing: 11) {
                    ForEach(sortedCrowd(items)) { crowdRow($0) }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().tint(t.dim)
                Text("Loading…").font(t.sans(13)).foregroundStyle(t.dim)
            }
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

    // MARK: - Helpers

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
