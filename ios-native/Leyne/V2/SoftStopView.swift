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
        }
        .onAppear { ds.ensureArrivals(stop: stopCode) }
    }

    private var topActionRow: some View {
        HStack {
            GlassPillButton(t: t, icon: "chevron.left", label: "Back",
                            action: { fb.select(); onBack() })
            Spacer()
            GlassPillButton(t: t,
                            icon: isPinned ? "pin.fill" : "pin",
                            label: isPinned ? "Pinned" : "Pin",
                            filled: isPinned,
                            action: { fb.select(); togglePin() })
        }
    }

    private var stopHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "STOP \(stopCode)", t: t)
            Text(ds.stopName(stopCode))
                .font(t.sans(28, weight: .semibold))
                .foregroundStyle(t.fg)
            HStack(spacing: 8) {
                Image(systemName: "figure.walk").font(.system(size: 12))
                Text(ds.roadName(stopCode).isEmpty
                     ? "Live arrivals · LTA"
                     : ds.roadName(stopCode))
                    .font(t.mono(11))
            }
            .foregroundStyle(t.dim)
        }
    }

    @ViewBuilder
    private var arrivalContent: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
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
            .padding(12)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                t.line.frame(height: 0.5).padding(.leading, 56)
            }
        }
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

    private func togglePin() {
        if isPinned {
            m.pins.removeAll { $0.code == stopCode }
        } else {
            m.pins.append(Pin(code: stopCode, nickname: ""))
        }
    }
}
