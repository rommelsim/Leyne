// WhereSia — Alerts (screen 8).
//
// User arrival/destination reminders up top, train disruptions + station
// facility outages below, all wired to DataStore.trainAlerts +
// liftMaintenance and AppModel.alerts. Toggle PAUSES an alert in place
// (never deletes); swipe or the trailing Remove button deletes; EDIT drags
// to reorder.
//
// Soft Blue "4b" pass (2026-07-24 rollout, see docs/soft-blue-design.md):
// ported wholesale from the greendark board. Per the spec's component
// inventory, Alerts gets NO gradient hero (a status list misrepresents a
// disruption feed as "the one live thing to look at") — instead a plain
// white summary card (count + disruption count) sits above the list. The
// user's own alert cards lose their mint stroke for a plain white card with
// blue-tinted chip accents; train disruption cards lose their amber
// fill/glow border for a white card + `SoftDisruptionChip` row (warning as
// text, not a decorative edge) per the porting table. `WSPulseDot` →
// `SoftPulseDot`. All data + mutation paths (pause, delete, reorder,
// trainAlerts, liftMaintenance, markAllAlertsSeen) are unchanged — only how
// they're drawn.

import SwiftUI

struct WSAlertsView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var editMode: EditMode = .inactive

    private var isEmpty: Bool {
        m.alerts.isEmpty && store.trainAlerts.isEmpty && store.liftMaintenance.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty {
                emptyState
            } else {
                summaryCard
                List {
                    if !m.alerts.isEmpty {
                        ForEach(m.alerts) { alert in
                            row(editable: true) { yourAlertCard(alert) }
                        }
                        .onDelete { offsets in
                            for id in offsets.map({ m.alerts[$0].id }) { m.removeAlert(id: id) }
                        }
                        .onMove { m.moveAlerts(fromOffsets: $0, toOffset: $1) }
                    }

                    if !store.trainAlerts.isEmpty {
                        ForEach(store.trainAlerts) { a in
                            row { trainCard(a) }
                        }
                    }

                    if !store.liftMaintenance.isEmpty {
                        row { liftSection }
                    }

                    // One native ad per screen, after the live alert cards.
                    NativeAdCard()
                        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .deleteDisabled(true).moveDisabled(true)

                    // Breathing room only — the system tab bar insets the
                    // list itself now (was 90pt of manual clearance).
                    Color.clear.frame(height: 8)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .deleteDisabled(true).moveDisabled(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(SoftBlue.bg)
                .environment(\.editMode, $editMode)
                .wsEntrance()
            }
        }
        .background(SoftBlue.bg.ignoresSafeArea())
        // Native nav bar + native Edit button (owner 2026-07-25).
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)   // owner 2026-07-25: large titles left a big empty band at the top
        .toolbar {
            if !m.alerts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation(SoftMotion.flow) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .sensoryFeedback(.selection, trigger: editMode)
                }
            }
        }
        .onAppear {
            store.refreshTrainAlertsIfStale(force: true)
            store.refreshLiftMaintenanceIfStale(force: true)
            m.markAllAlertsSeen()
        }
    }

    /// Status-first summary card (owner feedback 2026-07-25: "4 alerts" said
    /// nothing). Leads with the NETWORK state — normal service is the calm
    /// headline; disruptions take it over in amber. Lift outages are context
    /// on the sub-line, never counted as "alerts".
    private var summaryCard: some View {
        let disruptions = store.trainAlerts.count
        let lifts = store.liftMaintenance.count
        return HStack(spacing: 10) {
            SoftPulseDot(color: disruptions > 0 ? SoftBlue.amber : SoftBlue.blue, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(disruptions > 0
                     ? "\(disruptions) line \(disruptions == 1 ? "disruption" : "disruptions")"
                     : "All MRT lines running normally")
                    .font(ws.sans(14.5, weight: .semibold))
                    .foregroundStyle(disruptions > 0 ? SoftBlue.amber : SoftBlue.ink)
                if lifts > 0 {
                    Text("\(lifts) \(lifts == 1 ? "lift" : "lifts") out of service")
                        .font(ws.sans(12)).foregroundStyle(SoftBlue.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .softCard(radius: 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Shared row chrome: each row is its own card, transparent list gutter.
    private func row<Content: View>(editable: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
            .deleteDisabled(!editable)
            .moveDisabled(!editable)
    }

    // MARK: your alerts

    private func yourAlertCard(_ alert: BusAlert) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bus \(alert.busNo) · \(alert.stopName)")
                    .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                Text(alert.enabled ? "Alert set · \(leadText(alert))" : "Paused")
                    .font(ws.sans(11.5, weight: .medium)).foregroundStyle(SoftBlue.sub)
            }
            .opacity(alert.enabled ? 1 : 0.55)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    m.setAlertEnabled(id: alert.id, !alert.enabled)
                } label: {
                    Image(systemName: alert.enabled ? "bell.fill" : "bell.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(alert.enabled ? SoftBlue.blue : SoftBlue.sub)
                        .frame(width: 30, height: 30)
                        .background(alert.enabled ? SoftBlue.chipBg : Color.clear, in: Circle())
                        .frame(width: 44, height: 44)   // 44pt hit area overhangs the 30pt dot
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .frame(width: 30, height: 30)   // layout stays dot-sized
                .accessibilityLabel(alert.enabled ? "Pause alert" : "Resume alert")
                Button {
                    m.removeAlert(id: alert.id)
                } label: {
                    Text("Remove").font(ws.sans(12, weight: .semibold)).foregroundStyle(SoftBlue.red)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                }
                .buttonStyle(SoftPressStyle())
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .softCard(radius: 18)
    }

    private func leadText(_ a: BusAlert) -> String {
        if a.kind == .arrival { return "on arrival" }
        return a.leadMinutes > 0 ? "\(a.leadMinutes) min before" : "before your stop"
    }

    // MARK: train disruptions

    private func trainCard(_ a: TrainAlert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LineBullet(code: a.lineCode, isLineCode: true)
                Text(wsLineNames(from: [a.lineCode]))
                    .font(ws.sans(13.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                Spacer(minLength: 0)
                SoftPulseDot(color: SoftBlue.amber)
            }
            SoftDisruptionChip(text: a.title)
            Text(a.detail).font(ws.sans(12, weight: .medium)).foregroundStyle(SoftBlue.sub).lineSpacing(4)
            if a.freeBus || a.freeShuttle {
                HStack(spacing: 6) {
                    if a.freeBus { freeBadge("FREE BUS") }
                    if a.freeShuttle { freeBadge("FREE SHUTTLE") }
                }
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .softCard(radius: 18)
    }

    private func freeBadge(_ text: String) -> some View {
        Text(text).font(ws.sans(9, weight: .bold)).tracking(0.5)
            .foregroundStyle(SoftBlue.amber)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(SoftBlue.amber.opacity(0.12), in: Capsule())
    }

    // MARK: stations / lift outages (quiet, grouped)

    // One compact grouped card, not a loud amber card per lift: routine
    // maintenance shouldn't out-shout line delays (design reserves the
    // amber-tinted chip for train disruptions; facilities use the quiet
    // icon-row idiom). Amber survives only on the icon tile.
    private var liftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIFTS OUT OF SERVICE")
                .font(ws.sans(11, weight: .bold)).tracking(1.2).foregroundStyle(SoftBlue.sub)
            VStack(spacing: 0) {
                ForEach(Array(store.liftMaintenance.enumerated()), id: \.element.id) { i, lift in
                    liftRow(lift)
                    if i < store.liftMaintenance.count - 1 { SoftRowDivider() }
                }
            }
            .padding(.horizontal, 16)
            .softCard(radius: 18)
        }
    }

    /// One lift-outage row: line pill for identity, and tappable through to
    /// the station screen when the station name resolves in the geo DB
    /// (owner feedback 2026-07-25 — rows were inert and line-less).
    /// Pill codes for a lift outage's station: the code(s) on the affected
    /// line first (Clementi on the EWL → "EW23"), every code if none match,
    /// and the raw line code when the station isn't in the geo DB at all.
    private func stationCodes(_ lift: LiftMaintenance) -> [String] {
        guard let station = MrtGeo.all.first(where: {
            $0.name.caseInsensitiveCompare(lift.stationName) == .orderedSame
        }) else { return [lift.line] }
        let prefix = lift.line.hasSuffix("L") ? String(lift.line.dropLast()) : lift.line
        let onLine = station.codes.filter { $0.hasPrefix(prefix) }
        return onLine.isEmpty ? Array(station.codes.prefix(2)) : onLine
    }

    @ViewBuilder
    private func liftRow(_ lift: LiftMaintenance) -> some View {
        let station = MrtGeo.all.first {
            $0.name.caseInsensitiveCompare(lift.stationName) == .orderedSame
        }
        Button {
            if let station { push(.mrtStation(station)) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                WSIcon(glyph: .lift, size: 14, color: SoftBlue.amber)
                    .frame(width: 26, height: 26)
                    .background(SoftBlue.amber.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(lift.stationName)
                            .font(ws.sans(13, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                        // The STATION's pill code, not the bare line code
                        // (owner 2026-07-25: "Clementi is EW23 green"). The
                        // feed only names a line, so the codes come from the
                        // geo DB; an interchange shows both of its codes, and
                        // the line code is the fallback when the station name
                        // doesn't resolve.
                        ForEach(stationCodes(lift), id: \.self) { code in
                            // The fallback entry IS the line code, so it needs
                            // line-code colouring; station codes get theirs
                            // from the code itself.
                            LineBullet(code: code, isLineCode: code == lift.line)
                        }
                    }
                    Text(wsFacilityText(lift.detail))
                        .font(ws.sans(11.5, weight: .medium)).foregroundStyle(SoftBlue.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if station != nil {
                    WSIcon(glyph: .chevron, size: 12, color: SoftBlue.sub)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(station == nil)
    }

    // MARK: empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SoftPulseDot(color: SoftBlue.blue, size: 7)
                Text("All MRT lines running normally")
                    .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .softCard(radius: 18)
            Text("Bus arrival alerts you set will appear here.")
                .font(ws.sans(12)).foregroundStyle(SoftBlue.sub)
                .padding(.horizontal, 4)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 6)
    }
}
