// SoftStopView — Leyne 2.0 Stop detail: stop header + a single sortable
// list of every bus serving this stop (no hero card).

import SwiftUI

/// How the stop's arrivals are ordered.
enum StopSort: Hashable {
    case arrival   // soonest first
    case service   // by bus number (natural numeric order)
}

struct SoftStopView: View {
    let stopCode: String

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void
    let onOpenBus: (String) -> Void

    @State private var sort: StopSort = .arrival

    private var t: Theme { m.t }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    /// Every service no. serving this stop, from whatever arrivals we have
    /// loaded (falls back to the static route catalogue so the count is
    /// stable before live data lands). Used as `allNos` for the model's
    /// tracking math so "track all" ⟺ `tracked == nil`.
    private var allServiceNos: [String] {
        if case .some(.loaded(let svcs)) = ds.arrivals[stopCode], !svcs.isEmpty {
            return svcs.map(\.no)
        }
        return ds.servicesFor(stopCode).map(\.no)
    }

    /// Label for the master pill. "Track" was ambiguous (track on a map?);
    /// this stop's pill arms *arrival alerts*, so the copy says so. Shows the
    /// count when some-but-not-all buses are armed, "All alerts" when every
    /// service is, and "Alert all" as the call-to-action when nothing's armed.
    private var trackAllLabel: String {
        guard isPinned else { return "Alert all" }
        let total = allServiceNos.count
        if total > 0, trackedCount >= total { return "All alerts" }
        return "\(trackedCount) alert\(trackedCount == 1 ? "" : "s")"
    }

    /// Count of services the user is currently tracking (alerted on) here.
    private var trackedCount: Int {
        guard isPinned else { return 0 }
        let hidden = m.hiddenSet(code: stopCode, allNos: allServiceNos)
        return max(allServiceNos.count - hidden.count, 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topActionRow
                    stopHeader
                    arrivalContent
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .refreshable { await ds.refreshArrivals(stop: stopCode) }
        }
        .onAppear { ds.ensureArrivals(stop: stopCode) }
        .task { await m.refreshNotificationAuth() }
    }

    private var topActionRow: some View {
        HStack {
            GlassPillButton(t: t, icon: "chevron.left", label: "Back",
                            action: { fb.select(); onBack() })
            Spacer()
            // Master control. Pinned → shows tracked count + clears all on tap
            // (unpins). Not pinned → "Track all" pins every service so the
            // user gets alerts for the whole stop in one tap. Per-bus refining
            // happens with the bell on each row below.
            GlassPillButton(t: t,
                            icon: isPinned ? "bell.fill" : "bell",
                            label: trackAllLabel,
                            filled: isPinned,
                            action: { fb.select(); toggleTrackAll() })
            .accessibilityLabel(isPinned
                ? "Alerting for \(trackedCount) buses at this stop. Tap to turn all alerts off."
                : "Alert me for every bus at this stop")
        }
    }

    private var stopHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "STOP \(stopCode)", t: t)
            Text(ds.stopName(stopCode))
                .font(t.sans(28, weight: .semibold))
                .foregroundStyle(t.fg)
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                Text(ds.roadName(stopCode).isEmpty
                     ? "Live arrivals · LTA"
                     : ds.roadName(stopCode))
                    .font(t.mono(11))
            }
            .foregroundStyle(t.dim)
        }
    }

    /// True when this stop is pinned/armed AND system notifications are off.
    /// Mirrors the Android condition: pinned (tracked ≥1 bus) && notif disabled.
    private var shouldShowNotifBanner: Bool {
        isPinned && m.notificationAuth == .denied
    }

    /// Warn banner shown above the bus list when the stop is pinned but
    /// notifications are denied at the system level. Mirrors Android's warn
    /// banner (soft_stop_screen.dart:80-82).
    private var notifOffBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.warn)
            Text("Notifications are off — arrival alerts won't fire.")
                .font(t.mono(11))
                .foregroundStyle(t.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Enable")
                    .font(t.sans(12, weight: .semibold))
                    .foregroundStyle(t.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.warn, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(t.warnBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(t.warn.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var arrivalContent: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
            if shouldShowNotifBanner { notifOffBanner }
            trackHint
            sortControl
            busList(sortedServices(services))
        case .some(.empty):
            emptyArrivals(message: "No buses in operation right now.")
        case .some(.error(let e)):
            emptyArrivals(message: e)
        default:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private var sortControl: some View {
        SortChipRow(t: t, selection: $sort, options: [
            (.arrival, "Soonest"),
            (.service, "Bus no."),
        ])
    }

    private func sortedServices(_ s: [Service]) -> [Service] {
        switch sort {
        case .arrival:
            return s.sorted { $0.etaSec < $1.etaSec }
        case .service:
            // Natural numeric order so 67 < 75 < 170 < 871, and lettered
            // variants (12e) sort beside their base. localizedStandardCompare
            // gives this for free without parsing the number out.
            return s.sorted {
                $0.no.localizedStandardCompare($1.no) == .orderedAscending
            }
        }
    }

    private func busList(_ services: [Service]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(services.enumerated()), id: \.element.no) { idx, bus in
                busRow(bus: bus, isLast: idx == services.count - 1)
            }
        }
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Clip so per-row tracked tints / accent rules respect the card's
        // rounded corners on the first and last rows.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Live (GPS-monitored) vs scheduled (estimate-only) tag, mirroring the
    /// LTA `Monitored` flag. Live reads in the accent; scheduled stays dim.
    @ViewBuilder
    private func liveSchedTag(_ monitored: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: monitored ? "dot.radiowaves.up.forward" : "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(monitored ? "live" : "sched")
                .font(t.mono(10, weight: .medium))
        }
        .foregroundStyle(monitored ? t.accent : t.dim)
    }

    private func busRow(bus: Service, isLast: Bool) -> some View {
        let tracked = m.isTracked(code: stopCode, busNo: bus.no)
        return HStack(spacing: 4) {
            // Per-service alert toggle. Tapping pins the stop (model side)
            // and tracks just this bus, arming the ~1-min-before arrival
            // alert. Separate 44pt hit target so it never competes with the
            // row's tap-to-open-bus action.
            Button {
                fb.tap()
                m.toggleTracked(code: stopCode, busNo: bus.no, allNos: allServiceNos)
            } label: {
                Image(systemName: tracked ? "bell.fill" : "bell")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tracked ? t.accent : t.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tracked
                ? "Alerting for bus \(bus.no). Tap to stop."
                : "Alert me about bus \(bus.no)")

            Button {
                fb.select()
                onOpenBus(bus.no)
            } label: {
                HStack(spacing: 12) {
                    ServiceBadge(svc: bus.no, t: t, size: .sm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bus.dest)
                            .font(t.sans(14, weight: .medium))
                            .foregroundStyle(t.fg)
                        HStack(spacing: 6) {
                            Circle().fill(bus.load.color(t)).frame(width: 5, height: 5)
                            Text(bus.load.label.lowercased())
                                .font(t.mono(10))
                                .foregroundStyle(t.dim)
                        }
                    }
                    Spacer()
                    let eta = fmtETA(bus.etaSec)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(eta.big) \(eta.small)")
                            .font(t.mono(13, weight: .semibold))
                            .foregroundStyle(t.accent)
                        liveSchedTag(bus.monitored)
                    }
                }
                .padding(.vertical, 12)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        // Tracked rows get a faint accent wash + left rule so state reads
        // without relying on the bell colour alone (accessibility: don't
        // signal with colour only).
        .background(tracked ? t.liveBg : .clear)
        .overlay(alignment: .leading) {
            if tracked {
                t.accent.frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                t.line.frame(height: 0.5).padding(.leading, 56)
            }
        }
    }

    private var trackHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.accent)
            Text("Tap the bell on a bus to be alerted ~1 min before it arrives.")
                .font(t.mono(11))
                .foregroundStyle(t.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyArrivals(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "tram.fill")
                .font(.system(size: 22))
                .foregroundStyle(t.dim)
            Text(message)
                .font(t.sans(14))
                .foregroundStyle(t.fg)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Master toggle behind the top pill. Pinned (tracking ≥1) → clear all,
    /// which unpins the stop (pinned ⟺ ≥1 tracked bus). Not pinned → track
    /// every service. Routes through the model so the invariant + alert
    /// scheduling stay consistent with per-row toggles.
    private func toggleTrackAll() {
        m.setAllTracked(code: stopCode, allNos: allServiceNos, tracked: !isPinned)
    }
}
