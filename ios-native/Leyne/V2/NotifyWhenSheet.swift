// NotifyWhenSheet — the "Notify me when" sheet shared by both alert kinds.
//
//   • arrival     — set from the Stop view: pick how early before the bus
//                   reaches YOUR stop. Header shows the service badge.
//   • destination — set from the Bus view: how early before the bus reaches
//                   your chosen DESTINATION stop. Header shows a flag chip.
//
// Richer picker UI: it owns the chosen lead + the delivery prefs (push is
// implicit/always-on; Live Activity is an opt-in toggle), returning them via
// `onDone`. All timing/copy comes from `AlertTiming` so the sheet stays a thin
// shell over the shared rules.

import SwiftUI

struct NotifyWhenSheet: View {
    let kind: AlertKind
    let busNo: String
    /// The stop the alert is about — boarding stop (arrival) or destination
    /// stop (destination). Drives the header subtitle + the live summary.
    let stopName: String

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    let onCancel: () -> Void
    /// Fires on Done with the chosen lead (minutes) + the Live Activity
    /// (lock-screen) preference. Push delivery is implicit — the alert itself
    /// is the push — so only the Live Activity opt-in needs to round-trip.
    let onDone: (Int, Bool) -> Void

    @State private var lead: Int
    @State private var push: Bool = true
    @State private var liveActivity: Bool = true

    private var t: Theme { m.t }

    /// Live Activity only makes sense for an arrival alert (you follow the bus
    /// to YOUR stop). For a destination alert we hide the lock-screen row.
    private var showsLiveActivity: Bool { kind == .arrival }

    init(kind: AlertKind, busNo: String, stopName: String,
         initialLead: Int? = nil,
         onCancel: @escaping () -> Void, onDone: @escaping (Int, Bool) -> Void) {
        self.kind = kind
        self.busNo = busNo
        self.stopName = stopName
        self.onCancel = onCancel
        self.onDone = onDone
        _lead = State(initialValue: initialLead ?? AlertTiming.defaultLead(kind))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerChip
                    leadSection
                    summaryCard
                    deliverySection
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
            Button { fb.tap(); onCancel() } label: {
                Text("Cancel")
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text("Notify me when")
                .font(t.sans(16, weight: .semibold))
                .foregroundStyle(t.fg)

            Spacer(minLength: 8)

            Button {
                fb.success()
                onDone(lead, showsLiveActivity && liveActivity)
            } label: {
                Text("Done")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Header chip — who/what the alert is for

    private var headerChip: some View {
        HStack(spacing: 12) {
            if kind == .arrival {
                ServiceBadge(svc: busNo, t: t, size: .md)
            } else {
                Image(systemName: "flag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(t.contrastFg)
                    .frame(width: 48, height: 48)
                    .background(t.accent,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .arrival ? "Bus \(busNo)" : "Destination stop")
                    .font(t.sans(16, weight: .bold))
                    .foregroundStyle(t.fg)
                Text(stopName)
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if kind == .arrival {
                livePill
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(t.line, lineWidth: 1))
    }

    /// Confident "LIVE" badge — the sheet is only ever opened for a bus with
    /// live arrivals, so we present it without hedging (per the app's
    /// timely-updates design language). Replaces the old trailing chevron.
    private var livePill: some View {
        HStack(spacing: 5) {
            Image(systemName: "bus.fill")
                .font(.system(size: 12, weight: .bold))
            Text("LIVE")
                .font(t.sans(12, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(t.soon)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(t.soonBg, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live tracking")
    }

    // MARK: Lead-time radio list

    private var leadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                icon: "clock",
                title: "How early do you want to be notified?",
                subtitle: "You'll get a notification before the bus arrives.")

            VStack(spacing: 0) {
                let options = AlertTiming.leadOptions(kind)
                ForEach(Array(options.enumerated()), id: \.element) { i, opt in
                    if i > 0 {
                        Rectangle().fill(t.line).frame(height: 1)
                            .padding(.horizontal, 6)
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
        let recommended = opt <= 1   // "When bus is arriving"
        return Button {
            fb.select()
            lead = opt
        } label: {
            HStack(spacing: 12) {
                Image(systemName: recommended ? "bus.fill" : "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? t.soon : t.dim)
                    .frame(width: 34, height: 34)
                    .background(selected ? t.soonBg : t.surfaceHi,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(AlertTiming.leadLabel(opt))
                            .font(t.sans(15, weight: .medium))
                            .foregroundStyle(t.fg)
                        if recommended {
                            Text("Recommended")
                                .font(t.sans(10, weight: .semibold))
                                .foregroundStyle(t.soon)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(t.soonBg,
                                            in: Capsule())
                        }
                    }
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
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? t.soonBg.opacity(0.5) : Color.clear)
                    .padding(4))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? t.soon : Color.clear, lineWidth: 1.5)
                    .padding(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(AlertTiming.leadLabel(opt))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Live summary footer + notification preview

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.soon)
                .frame(width: 36, height: 36)
                .background(t.soonBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(lead <= 1
                     ? "You'll be notified when it arrives"
                     : "You'll be notified \(lead) min before")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text(AlertTiming.summary(kind: kind, busNo: busNo,
                                         stopName: stopName, leadMinutes: lead))
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            notificationPreview
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.soonBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// A miniature lock-screen banner showing exactly what will be delivered,
    /// built from the same `AlertTiming` copy so it tracks the chosen lead.
    private var notificationPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(t.accent)
                    .frame(width: 14, height: 14)
                Text("Leyne")
                    .font(t.sans(10, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 4)
                Text("now")
                    .font(t.sans(9))
                    .foregroundStyle(t.faint)
            }
            Text(AlertTiming.arrivalTitle(busNo))
                .font(t.sans(11, weight: .bold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
            Text(AlertTiming.arrivalBody(stopName: stopName, leadMinutes: lead))
                .font(t.sans(10))
                .foregroundStyle(t.dim)
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: 132)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(t.line, lineWidth: 1))
    }

    // MARK: Delivery prefs — where to notify

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                icon: "iphone",
                title: "Where should we notify you?",
                subtitle: "Choose where you want to receive alerts.")

            VStack(spacing: 0) {
                deliveryRow(
                    on: $push,
                    title: "Push notification",
                    subtitle: "Sent to this device")
                if showsLiveActivity {
                    Rectangle().fill(t.line).frame(height: 1)
                        .padding(.horizontal, 6)
                    deliveryRow(
                        on: $liveActivity,
                        title: "Lock screen (Live Activity)",
                        subtitle: "Follow your bus in real time")
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
    }

    private func deliveryRow(on: Binding<Bool>, title: String, subtitle: String) -> some View {
        Button {
            fb.select()
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(t.sans(15, weight: .medium))
                        .foregroundStyle(t.fg)
                    Text(subtitle)
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: on.wrappedValue
                      ? "checkmark.square.fill" : "square")
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

    // MARK: Shared section header (icon + title + subtitle)

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(t.soon)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text(subtitle)
                    .font(t.sans(12))
                    .foregroundStyle(t.dim)
            }
        }
        .padding(.leading, 2)
    }
}
