// SoftMrtNewsView — News & advisories for the MRT network.
//
// Pushed from the MRT tab's ••• menu.
// Shows:
//   • Advisories: LTA travel-advisory text from train alerts.
//   • Lift maintenance: the network-wide lift maintenance list
//     (moved here from SoftMrtView main screen).

import SwiftUI

struct SoftMrtNewsView: View {
    @Environment(AppModel.self) var m: AppModel
    private let ds = DataStore.shared
    let onBack: () -> Void

    private var t: Theme { m.t }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar

                // Title
                Text("News & advisories")
                    .font(t.sans(28, weight: .bold))
                    .foregroundStyle(t.fg)

                advisoriesSection
                liftMaintenanceSection
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
            ds.refreshLiftMaintenanceIfStale(force: true)
        }
        .onAppear {
            ds.refreshTrainAlertsIfStale(force: false)
            ds.refreshLiftMaintenanceIfStale(force: false)
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

    // MARK: - Advisories section

    @ViewBuilder
    private var advisoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Advisories")

            let alerts = ds.trainAlerts
            if alerts.isEmpty {
                calmCard(
                    icon: "checkmark.circle.fill",
                    title: "No advisories",
                    body: "All lines are running normally."
                )
            } else {
                ForEach(alerts) { alert in
                    advisoryCard(alert)
                }
            }
        }
    }

    private func advisoryCard(_ alert: TrainAlert) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let line = alert.line {
                    MRTLineBar(color: line.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(alert.title)
                            .font(t.sans(14, weight: .semibold))
                            .foregroundStyle(t.fg)
                    }
                    Text(alert.detail)
                        .font(t.sans(13))
                        .foregroundStyle(t.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if alert.freeBus || alert.freeShuttle {
                HStack(spacing: 6) {
                    if alert.freeBus    { freeChip(icon: "bus.fill",  label: "Free bus rides") }
                    if alert.freeShuttle { freeChip(icon: "tram.fill", label: "Free MRT shuttle") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Lift maintenance section

    @ViewBuilder
    private var liftMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Lift maintenance")

            let items = ds.liftMaintenance
            if items.isEmpty {
                calmCard(
                    icon: "checkmark.circle.fill",
                    title: "No maintenance underway",
                    body: "All network lifts are operating normally."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
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

                        if i < items.count - 1 {
                            Rectangle().fill(t.line).frame(height: 1)
                                .padding(.leading, 40)
                        }
                    }
                }
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Helpers

    private func calmCard(icon: String, title: String, body: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text(body)
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
