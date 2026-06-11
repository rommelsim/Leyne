// ArrivalAlertToast — the actionable top-of-screen toast used after a
// one-tap arrival alert toggle. Shows a brief message with an optional
// "Undo" button that reverses the toggle.
//
// Design: matches SoftBusView's confirmation toast (glass pill, top-of-screen,
// slide-in / slide-out, auto-dismiss after 3 s). The Undo button is accented
// so it reads as a distinct action tap target — not just decorative chrome.
//
// Usage:
//   1. Call `AppModel.toggleArrivalAlert(...)` — get back an
//      `ArrivalAlertToggleResult`.
//   2. Set `toastValue` on `ArrivalAlertToast.State` from that result.
//   3. Attach `.overlay(alignment: .top) { ArrivalAlertToast(state: $state, t: t) }`
//      to the host view.

import SwiftUI

/// Drives the toast. `nil` = hidden. Wrap in `@State` on the host view.
struct ArrivalAlertToastState: Equatable {
    let icon: String
    let message: String
    /// When non-nil an "Undo" button is shown; tapping it calls this closure
    /// and dismisses the toast.
    let undoAlert: BusAlert?
}

/// The toast pill itself. Place it with `.overlay(alignment: .top)` so it
/// floats above the content without shifting the layout.
struct ArrivalAlertToast: View {
    let t: Theme
    @Binding var state: ArrivalAlertToastState?
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    var body: some View {
        if let s = state {
            HStack(spacing: 9) {
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.soon)
                Text(s.message)
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.fg)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if s.undoAlert != nil {
                    Spacer(minLength: 8)
                    Button {
                        fb.select()
                        performUndo(s)
                    } label: {
                        Text("Undo")
                            .font(t.sans(13, weight: .semibold))
                            .foregroundStyle(t.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(t.surface.opacity(0.96))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(t.isDark ? 0.34 : 0.10),
                    radius: 16, x: 0, y: 5)
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: s) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { state = nil }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Undo

    /// Reverses the toggle: if the toast carries an armed alert, remove it;
    /// if it carries a removed alert, re-add it.
    private func performUndo(_ s: ArrivalAlertToastState) {
        guard let a = s.undoAlert else { return }
        if m.alert(kind: a.kind, busNo: a.busNo, stopCode: a.stopCode) != nil {
            // Alert is currently on — the original action was "arm", so undo = remove.
            m.removeAlert(id: a.id)
        } else {
            // Alert is currently off — the original action was "remove", so undo = re-add.
            m.upsertAlert(a)
        }
        withAnimation(.easeInOut(duration: 0.25)) { state = nil }
    }
}

// MARK: - View helper

extension View {
    /// Convenience: apply the arrival-alert toast overlay to any view.
    /// `topPadding` lets callers that already have a navigation bar offset
    /// the pill below the bar.
    func arrivalAlertToastOverlay(
        state: Binding<ArrivalAlertToastState?>,
        t: Theme
    ) -> some View {
        self.overlay(alignment: .top) {
            ArrivalAlertToast(t: t, state: state)
        }
    }
}

// MARK: - AppModel convenience

extension AppModel {
    /// Calls `toggleArrivalAlert` and returns a pre-built toast state
    /// ready to assign to `@State var toastState: ArrivalAlertToastState?`.
    @MainActor
    func toggleArrivalAlertWithToast(
        busNo: String,
        stopCode: String,
        stopName: String,
        dest: String
    ) -> ArrivalAlertToastState {
        let result = toggleArrivalAlert(
            busNo: busNo, stopCode: stopCode,
            stopName: stopName, dest: dest)
        switch result {
        case .armed(let a):
            return ArrivalAlertToastState(
                icon: "eye.fill",
                message: "We'll alert you 3 & 1 min before Bus \(busNo)",
                undoAlert: a)
        case .removed(let a):
            return ArrivalAlertToastState(
                icon: "eye.slash.fill",
                message: "Alert off for Bus \(busNo)",
                undoAlert: a)
        }
    }
}
