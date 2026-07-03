// WhereSia — Alerts (screen 8).
//
// A native List (WhereSia-styled), grouped: Train service (line bullet +
// disruption text), Stations (facility / lift outages), and Your alerts —
// user reminders whose toggle PAUSES in place (never deletes), with EDIT for
// drag-to-reorder and swipe-to-delete for actual removal. Wired to
// DataStore.trainAlerts + liftMaintenance and AppModel.alerts.

import SwiftUI

struct WSAlertsView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                headerRow(WSSectionHeader(label: "Train service"))
                trainSection
                headerRow(WSSectionHeader(label: "Stations"))
                stationsSection
                headerRow(WSSectionHeader(label: "Your alerts"))
                yourSection
                Color.clear.frame(height: 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .deleteDisabled(true).moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
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
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("NOTIFICATIONS").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                Text("Alerts").font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
            }
            Spacer()
            if !m.alerts.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {
                    Text(editMode == .active ? "DONE" : "EDIT")
                        .font(ws.mono(11, weight: .bold)).tracking(0.8)
                        .foregroundStyle(ws.text)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .overlay(Capsule().stroke(ws.rule, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: editMode)
            }
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    /// Header line as a non-editable list row (pixel-exact WhereSia styling).
    private func headerRow(_ header: WSSectionHeader) -> some View {
        header
            .padding(.top, 18).padding(.bottom, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .deleteDisabled(true)
            .moveDisabled(true)
    }

    /// Shared row chrome for List rows.
    private func rowChrome<Content: View>(_ content: Content, editable: Bool = false) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(ws.rule)
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .deleteDisabled(!editable)
            .moveDisabled(!editable)
    }

    // MARK: train service

    @ViewBuilder private var trainSection: some View {
        if store.trainAlerts.isEmpty {
            rowChrome(calmRow("All lines running normally."))
        } else {
            ForEach(store.trainAlerts) { a in
                rowChrome(
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
                    .padding(.vertical, 15)
                )
            }
        }
    }

    // MARK: stations (lift maintenance)

    @ViewBuilder private var stationsSection: some View {
        if store.liftMaintenance.isEmpty {
            rowChrome(calmRow("No lift or facility outages reported."))
        } else {
            ForEach(store.liftMaintenance) { lift in
                rowChrome(
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
                    .padding(.vertical, 15)
                )
            }
        }
    }

    // MARK: your alerts

    @ViewBuilder private var yourSection: some View {
        if m.alerts.isEmpty {
            rowChrome(calmRow("No reminders set. Track a bus and tap “Alert me 1 stop before”."))
        } else {
            ForEach(m.alerts) { alert in
                rowChrome(
                    HStack(spacing: 13) {
                        // Toggle pauses in place; swipe (or EDIT) deletes.
                        HStack(spacing: 13) {
                            RouteTile(text: alert.busNo, size: .large)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.stopName).font(ws.sans(14.5, weight: .bold)).foregroundStyle(ws.text)
                                Text(alert.enabled ? alertDesc(alert) : "Paused — flip on to resume")
                                    .font(ws.sans(12, weight: .medium)).foregroundStyle(ws.dim)
                            }
                        }
                        .opacity(alert.enabled ? 1 : 0.55)
                        Spacer()
                        WSToggle(isOn: Binding(
                            get: { alert.enabled },
                            set: { on in m.setAlertEnabled(id: alert.id, on) }))
                    }
                    .padding(.vertical, 15),
                    editable: true
                )
            }
            .onDelete { offsets in
                for id in offsets.map({ m.alerts[$0].id }) { m.removeAlert(id: id) }
            }
            .onMove { m.moveAlerts(fromOffsets: $0, toOffset: $1) }
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
