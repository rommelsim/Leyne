// WhereSia — Alerts (screen 8).
//
// Grouped: Train service (line bullet + disruption text), Stations (facility /
// lift outages), and Your alerts (user reminders with toggles). Wired to
// DataStore.trainAlerts + liftMaintenance and AppModel.alerts.

import SwiftUI

struct WSAlertsView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    trainSection
                    stationsSection
                    yourSection
                    Color.clear.frame(height: 24)
                }
            }
            .wsEntrance()
        }
        .background(ws.bg)
        .onAppear {
            store.refreshTrainAlertsIfStale(force: true)
            store.refreshLiftMaintenanceIfStale(force: true)
            m.markAllAlertsSeen()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("NOTIFICATIONS").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                Text("Alerts").font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    // MARK: train service

    private var trainSection: some View {
        Group {
            WSSectionHeader(label: "Train service")
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
            if store.trainAlerts.isEmpty {
                calmRow("All lines running normally.")
            } else {
                ForEach(store.trainAlerts) { a in
                    HStack(alignment: .top, spacing: 13) {
                        LineBullet(code: a.lineCode, size: .large, isLineCode: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.title).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                            Text(a.detail).font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim).lineSpacing(2)
                            if a.freeBus || a.freeShuttle {
                                HStack(spacing: 6) {
                                    if a.freeBus { miniBadge("FREE BUS") }
                                    if a.freeShuttle { miniBadge("FREE SHUTTLE") }
                                }.padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 15).padding(.horizontal, 22)
                    WSRowDivider().padding(.horizontal, 22)
                }
            }
        }
    }

    // MARK: stations (lift maintenance)

    private var stationsSection: some View {
        Group {
            WSSectionHeader(label: "Stations")
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
            if store.liftMaintenance.isEmpty {
                calmRow("No lift or facility outages reported.")
            } else {
                ForEach(store.liftMaintenance) { lift in
                    HStack(alignment: .top, spacing: 13) {
                        WSIcon(glyph: .lift, size: 20, color: ws.text)
                            .frame(width: 46, height: 40)
                            .background(ws.panel2)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ws.rule, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Lift out of service").font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                            Text("\(lift.stationName) — \(lift.detail)")
                                .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim).lineSpacing(2)
                        }
                        Spacer()
                        miniBadge("LIFT")
                    }
                    .padding(.vertical, 15).padding(.horizontal, 22)
                    WSRowDivider().padding(.horizontal, 22)
                }
            }
        }
    }

    // MARK: your alerts

    private var yourSection: some View {
        Group {
            WSSectionHeader(label: "Your alerts")
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
            if m.alerts.isEmpty {
                calmRow("No reminders set. Track a bus and tap “Alert me 1 stop before”.")
            } else {
                ForEach(m.alerts) { alert in
                    HStack(spacing: 13) {
                        RouteTile(text: alert.busNo, size: .large)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.stopName).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                            Text(alertDesc(alert)).font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                        }
                        Spacer()
                        WSToggle(isOn: Binding(
                            get: { true },
                            set: { on in if !on { m.removeAlert(id: alert.id) } }))
                    }
                    .padding(.vertical, 15).padding(.horizontal, 22)
                    WSRowDivider().padding(.horizontal, 22)
                }
            }
        }
    }

    private func alertDesc(_ a: BusAlert) -> String {
        a.kind == .arrival ? "Notify when it reaches this stop"
                           : "Notify before your destination"
    }

    // MARK: helpers

    private func calmRow(_ text: String) -> some View {
        Text(text).font(ws.sans(13, weight: .medium)).foregroundStyle(ws.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private func miniBadge(_ text: String) -> some View {
        Text(text).font(ws.mono(9.5, weight: .bold)).tracking(0.7).foregroundStyle(ws.dim)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ws.rule, lineWidth: 1))
    }
}
