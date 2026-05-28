// SoftHomeView — Leyne 2.0 Home: greeting + a vertical list of pinned-
// stop cards, each showing the stop name and a compact rundown of its
// live services. Empty state when no pins. Optional MRT alert below.

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
                        pinsList
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

    private var pinsList: some View {
        VStack(spacing: 12) {
            ForEach(m.pins, id: \.code) { pin in
                SoftPinCard(
                    t: t,
                    pin: pin,
                    services: filteredServices(for: pin),
                    onTap: {
                        fb.select()
                        onOpenStop(pin.code)
                    }
                )
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

/// Unified pinned-stop card. Replaces the earlier hero+grid split — every
/// pin gets the same full-width card so multiple services at the same stop
/// stack cleanly underneath the stop name. Whole surface is tappable.
struct SoftPinCard: View {
    let t: Theme
    let pin: Pin
    let services: [Service]
    let onTap: () -> Void

    private var visibleServices: [Service] {
        Array(services.prefix(4))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                Divider().background(t.line)
                if visibleServices.isEmpty {
                    Text(services.isEmpty ? "No live arrivals" : "—")
                        .font(t.sans(13))
                        .foregroundStyle(t.faint)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleServices, id: \.no) { s in
                            serviceRow(s)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressScale()
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if showEyebrow {
                    Text(pin.nickname.uppercased())
                        .font(t.mono(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(t.dim)
                }
                Text(stopName)
                    .font(t.sans(18, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.dim)
        }
    }

    @ViewBuilder
    private func serviceRow(_ s: Service) -> some View {
        let eta = fmtETA(s.etaSec)
        HStack(spacing: 12) {
            ServiceBadge(svc: s.no, t: t, size: .sm)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if eta.live {
                        Text("Arriving now")
                            .font(t.sans(14, weight: .semibold))
                            .foregroundStyle(t.accent)
                    } else {
                        Text(eta.big)
                            .font(t.mono(14, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(eta.small)
                            .font(t.mono(12))
                            .foregroundStyle(t.dim)
                    }
                }
                Text("→ \(s.dest)")
                    .font(t.sans(11))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var stopDataStoreName: String {
        let n = DataStore.shared.stopName(pin.code)
        return n.isEmpty ? pin.code : n
    }

    private var stopName: String {
        // Show the actual stop name as the primary title. If a nickname
        // was supplied it surfaces as the eyebrow above.
        return stopDataStoreName
    }

    private var showEyebrow: Bool {
        let nick = pin.nickname.trimmingCharacters(in: .whitespaces)
        return !nick.isEmpty && nick.caseInsensitiveCompare(stopDataStoreName) != .orderedSame
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
