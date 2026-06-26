// SoftAlertsView — the "Alerts" tab (replaces the old Settings tab).
//
// One place for everything alert-shaped:
//   • Service status — live line disruptions / advisories (breakdown + news)
//     and network lift maintenance, pulled from the LTA feeds.
//   • Your alerts — a row into the personal bus arrival/destination alerts
//     (ManageAlertsView), folding in what the old Home bell used to open.
//   • A gear (top-right) opens the trimmed Settings as a sheet — Appearance,
//     Haptics, Hidden stops — so those still have a home.
//
// Service-status cards mirror SoftMrtNewsView so the visual language matches.

import SwiftUI

struct SoftAlertsView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var ds = DataStore.shared

    private var t: Theme { m.t }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                advisoriesSection
                liftMaintenanceSection
                yourAlertsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            ds.refreshTrainAlertsIfStale(force: true)
            ds.refreshLiftMaintenanceIfStale(force: true)
        }
        .onAppear {
            ds.refreshTrainAlertsIfStale(force: false)
            ds.refreshLiftMaintenanceIfStale(force: false)
        }
    }

    // MARK: - Header

    private var header: some View {
        // Title + gear now live in the nav bar; this stays as the subtitle.
        Text("Service status & your notifications")
            .font(t.sans(14, weight: .medium))
            .foregroundStyle(t.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Advisories (disruptions / news)

    @ViewBuilder
    private var advisoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Service status")

            let alerts = ds.trainAlerts
            if alerts.isEmpty {
                calmCard(
                    icon: "checkmark.circle.fill",
                    title: "All lines running normally",
                    body: "No disruptions or advisories right now."
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
                    if alert.freeBus { freeChip(icon: "bus.fill", label: "Free bus rides") }
                    if alert.freeShuttle { freeChip(icon: "tram.fill", label: "Free MRT shuttle") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Lift maintenance

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

    // MARK: - Your alerts (personal bus notifications)

    private var yourAlertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Your alerts")
            NavigationLink {
                ManageAlertsView().toolbar(.hidden, for: .tabBar)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .frame(width: 32, height: 32)
                        .background(t.surfaceHi,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bus arrival alerts")
                            .font(t.sans(15, weight: .medium))
                            .foregroundStyle(t.fg)
                        Text(m.alerts.isEmpty ? "None set yet" : "\(m.alerts.count) set")
                            .font(t.sans(12))
                            .foregroundStyle(t.dim)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.faint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared helpers (mirror SoftMrtNewsView)

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
