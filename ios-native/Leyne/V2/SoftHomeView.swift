// SoftHomeView — Leyne 2.0 Home: greeting, pinned stops (hero + grid),
// MRT alert card. Empty state when no pins.

import SwiftUI

struct SoftHomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var showMrtAlert = true
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
                        primaryPinCard
                        if m.pins.count > 1 {
                            secondaryPinsGrid
                        }
                    }

                    if showMrtAlert {
                        mrtAlertCard
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            SoftTabBar(t: t,
                       selection: Binding(get: { .home }, set: { onTab($0) }),
                       onSelect: { _ in fb.select() })
                .padding(.bottom, 12)
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

    @ViewBuilder
    private var primaryPinCard: some View {
        if let pin = m.pins.first {
            SoftPrimaryPinCard(
                t: t,
                pin: pin,
                services: liveServices(for: pin.code),
                onTap: { onOpenStop(pin.code) }
            )
        }
    }

    @ViewBuilder
    private var secondaryPinsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Also pinned")
                .font(t.sans(13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(t.dim)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(Array(m.pins.dropFirst()), id: \.code) { pin in
                    SoftSecondaryPinCard(
                        t: t,
                        pin: pin,
                        firstService: liveServices(for: pin.code).first
                    )
                    .onTapGesture { onOpenStop(pin.code) }
                }
            }
        }
    }

    private var mrtAlertCard: some View {
        Button {
            fb.select()
            withAnimation(.easeOut(duration: 0.2)) { showMrtAlert = false }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                MRTLineBar(color: MRTLine.NE.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NE Line · short delays")
                        .font(t.sans(13, weight: .semibold))
                        .foregroundStyle(t.fg)
                    Text("Outram Pk ↔ HarbourFront · tap to dismiss")
                        .font(t.sans(12))
                        .foregroundStyle(t.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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

// MARK: - PrimaryPinCard

struct SoftPrimaryPinCard: View {
    let t: Theme
    let pin: Pin
    let services: [Service]
    let onTap: () -> Void

    var body: some View {
        let primary = trackedFirst()
        let next = services.dropFirst().first
        let thirdEta = services.dropFirst(2).first.map { fmtETA($0.etaSec) }

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    LabelPill(text: pin.nickname.isEmpty ? "Pinned" : pin.nickname,
                              t: t, variant: .solid)
                    Spacer()
                }
                Text(stopName)
                    .font(t.sans(20, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .multilineTextAlignment(.leading)

                // Inset arrival sub-card
                HStack(spacing: 12) {
                    ServiceBadge(svc: primary?.no ?? "—", t: t, size: .md)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryHeadline(primary))
                            .font(t.sans(15, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(primarySubline(primary))
                            .font(t.sans(11))
                            .foregroundStyle(t.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
                .padding(14)
                .background(t.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let n = next {
                    HStack(spacing: 4) {
                        Text("Then ")
                            .font(t.sans(12)).foregroundStyle(t.dim)
                        Text(n.no).font(t.mono(12, weight: .semibold)).foregroundStyle(t.fg)
                        Text(" \(fmtETA(n.etaSec).big)\(fmtETA(n.etaSec).small)")
                            .font(t.mono(12)).foregroundStyle(t.dim)
                        if let third = thirdEta {
                            Text(" · \(third.big)\(third.small)")
                                .font(t.mono(12)).foregroundStyle(t.faint)
                        }
                    }
                }
            }
            .padding(16)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressScale()
    }

    private func trackedFirst() -> Service? {
        if let tracked = pin.tracked, !tracked.isEmpty {
            return services.first { tracked.contains($0.no) }
        }
        return services.first
    }

    private func primaryHeadline(_ s: Service?) -> String {
        guard let s else { return "Loading…" }
        let eta = fmtETA(s.etaSec)
        if eta.live { return "Arriving now" }
        return "In \(eta.big) \(eta.small)"
    }

    private func primarySubline(_ s: Service?) -> String {
        guard let s else { return "Tap to open" }
        return "→ \(s.dest) · \(s.load.label.lowercased())"
    }

    private var stopName: String {
        let nick = pin.nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty { return nick }
        let n = DataStore.shared.stopName(pin.code)
        return n.isEmpty ? pin.code : n
    }
}

// MARK: - SecondaryPinCard

struct SoftSecondaryPinCard: View {
    let t: Theme
    let pin: Pin
    let firstService: Service?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelPill(text: pin.nickname.isEmpty ? "Pin" : pin.nickname, t: t, variant: .tinted)
            Text(stopName)
                .font(t.sans(13, weight: .semibold))
                .foregroundStyle(t.fg)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let s = firstService {
                    Text(s.no).font(t.mono(11, weight: .semibold)).foregroundStyle(t.fg)
                    Text(fmtETA(s.etaSec).big + fmtETA(s.etaSec).small)
                        .font(t.mono(11)).foregroundStyle(t.dim)
                } else {
                    Text("—").font(t.mono(11)).foregroundStyle(t.faint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .pressScale()
    }

    private var stopName: String {
        let nick = pin.nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty { return nick }
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
