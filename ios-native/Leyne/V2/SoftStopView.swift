// SoftStopView — Leyne 2.0 Stop detail: stop header, hero arrival,
// "Other buses" grouped card with "See all →" link.

import SwiftUI

struct SoftStopView: View {
    let stopCode: String
    /// When true, render the full arrivals list instead of the trimmed
    /// "Other buses" 3-row preview (the "See all" destination).
    var showAll: Bool = false

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void
    let onOpenBus: (String) -> Void
    let onSeeAll: () -> Void

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
            primaryArrivalCard(primary: services[0])
            otherBusesSection(services: Array(services.dropFirst()))
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

    private func primaryArrivalCard(primary: Service) -> some View {
        let eta = fmtETA(primary.etaSec)
        return Button {
            fb.select()
            onOpenBus(primary.no)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ServiceBadge(svc: primary.no, t: t, size: .lg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(primary.dest)")
                            .font(t.mono(10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(t.dim)
                        Text(eta.live ? "Arriving now" : "In \(eta.big) \(eta.small)")
                            .font(t.sans(22, weight: .semibold))
                            .foregroundStyle(t.fg)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
                HStack(spacing: 8) {
                    Circle().fill(primary.load.color(t)).frame(width: 6, height: 6)
                    Text("\(primary.load.label.lowercased())\(followingSuffix(primary))")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                }
            }
            .padding(16)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressScale()
    }

    private func followingSuffix(_ s: Service) -> String {
        let f = fmtETA(s.followingSec)
        return " · Then \(f.big)\(f.small)"
    }

    @ViewBuilder
    private func otherBusesSection(services: [Service]) -> some View {
        let visible = showAll ? services : Array(services.prefix(3))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showAll ? "All arrivals" : "Other buses")
                    .font(t.sans(13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(t.dim)
                Spacer()
                if !showAll && services.count > 3 {
                    Button(action: { fb.select(); onSeeAll() }) {
                        Text("See all \(services.count) →")
                            .font(t.sans(13, weight: .semibold))
                            .foregroundStyle(t.accent)
                    }.buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.no) { idx, bus in
                    otherBusRow(bus: bus, isLast: idx == visible.count - 1)
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func otherBusRow(bus: Service, isLast: Bool) -> some View {
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
                Text(eta.big + eta.small)
                    .font(t.mono(13, weight: .semibold))
                    .foregroundStyle(t.accent)
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
