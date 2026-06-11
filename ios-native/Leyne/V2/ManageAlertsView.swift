// ManageAlertsView — the central "Manage alerts" list, reachable from the
// confirmation sheet and from Settings. Splits the user's alerts into
// ACTIVE (the bus has a live arrival at the stop right now) and OTHER, with
// an Edit mode for deletion. Both kinds share one row design: a leading
// bell (arrival) / flag (destination) glyph, the destination/stop title, and
// a "<stopName> · <lead>" subtitle from `AlertTiming`.

import SwiftUI

struct ManageAlertsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    private var t: Theme { m.t }

    /// An alert is "active" when its boarding bus has a live arrival at its
    /// boarding stop right now — i.e. there's something imminent to ping
    /// about. Destination alerts use their boarding stop (where the bus is
    /// tracked from). Everything else is "other".
    private func isActive(_ a: BusAlert) -> Bool {
        guard case .loaded(let services) = ds.arrivals[a.boardStopCode] else { return false }
        return services.contains { $0.no == a.busNo && $0.arrivalDate != nil }
    }

    private var activeAlerts: [BusAlert] { m.alerts.filter(isActive) }
    private var otherAlerts: [BusAlert] { m.alerts.filter { !isActive($0) } }

    var body: some View {
        List {
            if m.alerts.isEmpty {
                emptyState
            } else {
                if !activeAlerts.isEmpty {
                    Section {
                        ForEach(activeAlerts) { alertRow($0) }
                    } header: {
                        sectionLabel("Active alerts")
                    }
                }
                if !otherAlerts.isEmpty {
                    Section {
                        ForEach(otherAlerts) { alertRow($0) }
                    } header: {
                        sectionLabel("Other alerts")
                    } footer: {
                        Text("You can turn off or edit alerts anytime.")
                            .font(t.sans(12))
                            .foregroundStyle(t.faint)
                            .padding(.top, 6)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.bg.ignoresSafeArea())
        .navigationTitle("Manage alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !m.alerts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .tint(t.accent)
        .onAppear {
            // Keep the alert stops fresh so the Active/Other split is honest.
            for a in m.alerts { ds.ensureArrivals(stop: a.boardStopCode) }
        }
    }

    // MARK: Row

    private func alertRow(_ a: BusAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.kind == .arrival ? "bell.fill" : "flag.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.soon)
                .frame(width: 36, height: 36)
                .background(t.soonBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(a))
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                Text("\(a.stopName) · \(a.kind == .arrival ? AlertTiming.arrivalRowSubtitle : AlertTiming.leadRowSubtitle(a.leadMinutes))")
                    .font(t.sans(12))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: a.kind == .arrival ? "bus.fill" : "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.faint)
        }
        .padding(.vertical, 4)
        .listRowBackground(t.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                fb.tap()
                m.removeAlert(id: a.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            // The List's `.tint(t.accent)` (for the EditButton) otherwise
            // bleeds into this swipe button, overriding the default system red
            // and rendering the trash glyph invisible. Pin it red explicitly.
            .tint(.red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(a)), \(a.stopName), "
            + "\(a.kind == .arrival ? AlertTiming.arrivalRowSubtitle : AlertTiming.leadRowSubtitle(a.leadMinutes))")
    }

    /// Title: the bus number for arrival (you're waiting for that service),
    /// the destination stop name for a destination alert.
    private func rowTitle(_ a: BusAlert) -> String {
        switch a.kind {
        case .arrival:     return "Bus \(a.busNo)"
        case .destination: return a.stopName
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(t.sans(13, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(t.dim)
            .textCase(nil)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(t.dim)
            Text("No alerts yet")
                .font(t.sans(17, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Set one from a bus or stop and it'll show up here.")
                .font(t.sans(13))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}
