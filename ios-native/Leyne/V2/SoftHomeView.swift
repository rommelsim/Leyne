// SoftHomeView — Leyne 2.0 Home: greeting + a vertical list of pinned-
// stop cards, each showing the stop name and a compact rundown of its
// live services. Empty state when no pins. Optional MRT alert below.

import SwiftUI

struct SoftHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    /// Line codes the user has tapped to dismiss this session. Cleared
    /// when the app cold-starts so a new disruption surfaces again.
    @State private var dismissedAlerts: Set<String> = []
    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void
    let onOpenSearch: () -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow

                    if m.pins.isEmpty {
                        SoftEmptyState(t: t,
                                       onNearby: { onTab(.nearby) },
                                       onSearch: { onOpenSearch() })
                            .padding(.top, 8)
                    } else {
                        pinsList
                    }

                    mrtAlertCards
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .onAppear { warmArrivals() }
        .onChange(of: m.pins) { _, _ in warmArrivals() }
    }

    private func warmArrivals() {
        for pin in m.pins { ds.ensureArrivals(stop: pin.code) }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: greeting, t: t)
                Text("Your stops")
                    .font(t.sans(30, weight: .semibold))
                    .foregroundStyle(t.fg)
            }
            Spacer()
            Button {
                fb.select()
                onOpenSearch()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .frame(width: 40, height: 40)
                    .background(t.surface, in: Circle())
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var pinsList: some View {
        VStack(spacing: 12) {
            ForEach(m.pins, id: \.code) { pin in
                SoftPinCard(
                    t: t,
                    pin: pin,
                    services: filteredServices(for: pin),
                    walkMinutes: walkMinutes(for: pin.code),
                    onTap: {
                        fb.select()
                        onOpenStop(pin.code)
                    }
                )
            }
        }
    }

    /// Walk-time (in minutes) from the user's last known location to the
    /// stop. Mirrors the heuristic used elsewhere: 80 m/min ≈ 5 km/h.
    /// Returns nil when location isn't available so the chip is hidden.
    private func walkMinutes(for code: String) -> Int? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[code] else { return nil }
        let d = haversine(here.coordinate.latitude,
                          here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        return max(1, Int((d / 80).rounded()))
    }

    @ViewBuilder
    private var mrtAlertCards: some View {
        let visible = ds.trainAlerts.filter { !dismissedAlerts.contains($0.id) }
        if !visible.isEmpty {
            VStack(spacing: 10) {
                ForEach(visible) { alert in
                    mrtAlertCard(alert)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: visible)
        }
    }

    private func mrtAlertCard(_ alert: TrainAlert) -> some View {
        Button {
            fb.select()
            withAnimation(.easeOut(duration: 0.2)) {
                _ = dismissedAlerts.insert(alert.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                MRTLineBar(color: alert.line?.color ?? t.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(t.sans(13, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(alert.detail)
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filteredServices(for pin: Pin) -> [Service] {
        let all = liveServices(for: pin.code)
        if let tracked = pin.tracked, !tracked.isEmpty {
            return all.filter { tracked.contains($0.no) }
        }
        return all
    }

    private func liveServices(for code: String) -> [Service] {
        if case .loaded(let s) = ds.arrivals[code] { return s }
        return []
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }
}

// MARK: - SoftPinCard

/// Pinned-stop card matching the Soft 2.0 prototype: pin-chip + stop-name
/// + walk-time header row, up to 3 service rows sorted by next arrival,
/// right-aligned ETAs ("now" in accent, otherwise mono), an overflow
/// "+N more arrivals →" link, and a quiet state when no live arrivals
/// are available.
struct SoftPinCard: View {
    let t: Theme
    let pin: Pin
    let services: [Service]
    let walkMinutes: Int?
    let onTap: () -> Void

    private static let maxVisible = 3

    private var sorted: [Service] {
        services.sorted { $0.etaSec < $1.etaSec }
    }
    private var visibleServices: [Service] {
        Array(sorted.prefix(Self.maxVisible))
    }
    private var overflowCount: Int {
        max(0, sorted.count - Self.maxVisible)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                if visibleServices.isEmpty {
                    quietRow
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleServices, id: \.no) { s in
                            serviceRow(s)
                        }
                    }
                    if overflowCount > 0 {
                        overflowLink
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if !pinChipLabel.isEmpty {
                Text(pinChipLabel)
                    .font(t.mono(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(t.liveBg, in: Capsule())
            }
            Text(stopDataStoreName)
                .font(t.sans(17, weight: .semibold))
                .foregroundStyle(t.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let w = walkMinutes {
                walkChip(w)
            }
        }
    }

    private func walkChip(_ minutes: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.dim)
            Text("\(minutes) m")
                .font(t.mono(11, weight: .semibold))
                .foregroundStyle(t.dim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.liveBg.opacity(0.5), in: Capsule())
    }

    // MARK: Body

    @ViewBuilder
    private func serviceRow(_ s: Service) -> some View {
        let eta = fmtETA(s.etaSec)
        HStack(spacing: 10) {
            ServiceBadge(svc: s.no, t: t, size: .sm)
            Text("→ \(s.dest)")
                .font(t.sans(13))
                .foregroundStyle(t.dim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if eta.live {
                Text("now")
                    .font(t.sans(13, weight: .semibold))
                    .foregroundStyle(t.accent)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(eta.big)
                        .font(t.mono(13, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text(eta.small)
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                }
            }
        }
    }

    private var overflowLink: some View {
        HStack {
            Text("+\(overflowCount) more arrivals →")
                .font(t.sans(12, weight: .medium))
                .foregroundStyle(t.dim)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var quietRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(t.dim.opacity(0.6))
                .frame(width: 6, height: 6)
            Text("Quiet · no live arrivals")
                .font(t.sans(13))
                .foregroundStyle(t.dim)
            Spacer(minLength: 0)
        }
    }

    // MARK: Naming helpers

    private var pinChipLabel: String {
        let nick = pin.nickname.trimmingCharacters(in: .whitespaces)
        // Avoid printing the stop name twice — if the nickname matches the
        // data-store name the chip would just echo the title.
        if nick.isEmpty { return "PIN" }
        if nick.caseInsensitiveCompare(stopDataStoreName) == .orderedSame { return "PIN" }
        return nick.uppercased()
    }

    private var stopDataStoreName: String {
        let n = DataStore.shared.stopName(pin.code)
        return n.isEmpty ? pin.code : n
    }
}

// MARK: - EmptyState

struct SoftEmptyState: View {
    let t: Theme
    let onNearby: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "pin")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(t.accent)
                .frame(width: 64, height: 64)
                .background(t.liveBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("No stops pinned")
                .font(t.sans(20, weight: .semibold))
                .foregroundStyle(t.fg)
            Text("Pin a bus stop to see live arrivals at a glance.")
                .font(t.sans(13))
                .foregroundStyle(t.dim)

            HStack(spacing: 8) {
                Button(action: onNearby) {
                    Text("Nearby")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(t.accent, in: Capsule())
                }.buttonStyle(.plain)
                Button(action: onSearch) {
                    Text("Search")
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().stroke(t.line, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
