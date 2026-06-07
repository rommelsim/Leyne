// StopAlertSheet — the stop-level "Arrival Alerts" sheet, opened from the Nearby
// card long-press menu. Unlike NotifyWhenSheet (which is per-bus, set from the
// Stop/Bus views), this is stop-first: the header is the STOP, and on Done it
// arms an arrival alert for the stop's SOONEST bus — the quick "ping me before a
// bus reaches this stop" path. Lead options + copy come from AlertTiming so it
// stays consistent with the per-bus sheet.
//
// Delivery maps to the app's existing pieces: Push = the BusAlert itself
// (upsertAlert schedules the notification); Live Activity = the lock-screen
// tracker (startLiveActivity), mirroring the Bus view's combined affordance.

import SwiftUI

struct StopAlertSheet: View {
    let stopCode: String
    let stopName: String
    let road: String

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    /// Dismiss callback (the parent owns the sheet presentation).
    let onClose: () -> Void

    @State private var lead: Int = AlertTiming.defaultLead(.arrival)
    @State private var push: Bool = true
    @State private var liveActivity: Bool = true
    /// Set when Done is tapped but the stop has no live bus to target.
    @State private var noBus: Bool = false

    private var t: Theme { m.t }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    leadSection
                    deliverySection
                    footer
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    // MARK: Top bar — Cancel · title · Done

    private var topBar: some View {
        HStack {
            Button { fb.tap(); onClose() } label: {
                Text("Cancel").font(t.sans(15)).foregroundStyle(t.dim)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
            Text("Arrival Alerts")
                .font(t.sans(16, weight: .semibold))
                .foregroundStyle(t.fg)
            Spacer(minLength: 8)

            Button { commit() } label: {
                Text("Done")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Header — the stop the alert is about

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.soonBg)
                Image(systemName: "bus.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.soon)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(stopName.isEmpty ? stopCode : stopName)
                    .font(t.sans(16, weight: .bold))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                Text(road.isEmpty ? "Stop \(stopCode)" : "Stop \(stopCode) · \(road)")
                    .font(t.mono(12.5))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(t.line, lineWidth: 1))
    }

    // MARK: Lead-time radio list (shares AlertTiming with NotifyWhenSheet)

    private var leadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "clock", title: "Notify me when",
                          subtitle: "Ping me before the next bus reaches this stop.")
            VStack(spacing: 0) {
                let options = AlertTiming.leadOptions(.arrival)
                ForEach(Array(options.enumerated()), id: \.element) { i, opt in
                    if i > 0 {
                        Rectangle().fill(t.line).frame(height: 1).padding(.horizontal, 6)
                    }
                    leadRow(opt)
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
    }

    private func leadRow(_ opt: Int) -> some View {
        let selected = lead == opt
        let arriving = opt <= 1
        return Button { fb.select(); lead = opt } label: {
            HStack(spacing: 12) {
                Image(systemName: arriving ? "bus.fill" : "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? t.soon : t.dim)
                    .frame(width: 34, height: 34)
                    .background(selected ? t.soonBg : t.surfaceHi,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlertTiming.leadLabel(opt))
                        .font(t.sans(15, weight: .medium))
                        .foregroundStyle(t.fg)
                    Text(AlertTiming.leadSubLabel(opt))
                        .font(t.mono(12))
                        .foregroundStyle(t.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? t.soon : t.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(AlertTiming.leadLabel(opt))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Delivery prefs

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "iphone", title: "Alert delivery",
                          subtitle: "Choose where you want to be alerted.")
            VStack(spacing: 0) {
                deliveryRow(on: $push, title: "Push notification",
                            subtitle: "Sent to this device")
                Rectangle().fill(t.line).frame(height: 1).padding(.horizontal, 6)
                deliveryRow(on: $liveActivity, title: "Lock screen (Live Activity)",
                            subtitle: "Follow this bus in real time")
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
    }

    private func deliveryRow(on: Binding<Bool>, title: String, subtitle: String) -> some View {
        Button { fb.select(); on.wrappedValue.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.sans(15, weight: .medium)).foregroundStyle(t.fg)
                    Text(subtitle).font(t.sans(12)).foregroundStyle(t.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(on.wrappedValue ? t.soon : t.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on.wrappedValue ? [.isSelected] : [])
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: noBus ? "exclamationmark.circle" : "bell")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(noBus ? t.warn : t.faint)
            Text(noBus
                 ? "No buses to alert on right now — try again when one's due."
                 : "You can manage or turn off alerts anytime in Settings.")
                .font(t.sans(12))
                .foregroundStyle(noBus ? t.warn : t.faint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(t.soon)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
                Text(subtitle).font(t.sans(12)).foregroundStyle(t.dim)
            }
        }
        .padding(.leading, 2)
    }

    // MARK: Commit — target the soonest bus

    /// Arms the alert against the stop's soonest live service. Push schedules the
    /// notification (via the BusAlert); Live Activity starts the lock-screen
    /// tracker — mirroring the Bus view's combined affordance. With no live bus,
    /// surface an inline note instead of fabricating a target.
    private func commit() {
        guard let soonest = m.liveServices(code: stopCode, tracked: []).first else {
            fb.tap()
            noBus = true
            return
        }
        if push {
            let alert = BusAlert(
                kind: .arrival, busNo: soonest.no, stopCode: stopCode,
                stopName: stopName, dest: soonest.dest, boardStopCode: stopCode,
                leadMinutes: lead)
            m.upsertAlert(alert)
        }
        if liveActivity, !m.isLiveActivityActive(soonest, stopCode: stopCode) {
            m.startLiveActivity(soonest, stopName: stopName, stopCode: stopCode)
        }
        fb.success()
        onClose()
    }
}
