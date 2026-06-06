// NotifyConfirmView — the "You'll be notified!" confirmation shown right
// after an alert is set (from the Stop or Bus view's notify flow). Presented
// as a sheet over the originating view. Carries the just-set alert so the
// user can immediately remove it again, and a route into the central
// "Manage alerts" list.

import SwiftUI

struct NotifyConfirmView: View {
    /// The alert that was just set — drives the summary + the removable chip.
    let alert: BusAlert

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    let onClose: () -> Void
    /// Push the central Manage alerts list from the host.
    let onManageAll: () -> Void

    private var t: Theme { m.t }

    /// Whether the alert is still active (the chip's ✕ removes it).
    private var stillActive: Bool {
        m.alert(kind: alert.kind, busNo: alert.busNo, stopCode: alert.stopCode) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — Done closes the confirmation.
            HStack {
                Spacer(minLength: 0)
                Button { fb.tap(); onClose() } label: {
                    Text("Done")
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 20) {
                    checkmark
                    VStack(spacing: 8) {
                        Text("You'll be notified!")
                            .font(t.sans(24, weight: .bold))
                            .foregroundStyle(t.fg)
                        Text(AlertTiming.summary(kind: alert.kind, busNo: alert.busNo,
                                                 stopName: alert.stopName,
                                                 leadMinutes: alert.leadMinutes))
                            .font(t.sans(15))
                            .foregroundStyle(t.dim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)

                    if stillActive { activeChip }
                    manageRow
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var checkmark: some View {
        ZStack {
            Circle().fill(t.soonBg).frame(width: 84, height: 84)
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(t.soon)
        }
        .accessibilityHidden(true)
    }

    /// "Active alert" chip — stop name + a ✕ that removes the alert.
    private var activeChip: some View {
        HStack(spacing: 10) {
            Image(systemName: alert.kind == .arrival ? "bell.fill" : "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.soon)
            Text(alert.stopName)
                .font(t.sans(14, weight: .semibold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
            Button {
                fb.tap()
                m.removeAlert(id: alert.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this alert")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.soonBg, in: Capsule())
        .overlay(Capsule().stroke(t.soon.opacity(0.3), lineWidth: 1))
    }

    /// "Manage all alerts ›" row.
    private var manageRow: some View {
        Button {
            fb.select()
            onManageAll()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("Manage all alerts")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Manage all alerts")
    }
}
