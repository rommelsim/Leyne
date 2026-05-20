// Nearby tab — live nearest stops (device GPS + LTA BusStops), expandable.

import SwiftUI
import CoreLocation

struct NearbyView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var loc: LocationManager
    @State private var openId: String?
    @State private var collapsed = false
    @State private var sortMode = "distance"
    // Frozen row order. Recomputed only on sort change / nearby change /
    // arrivals load — NOT every 1 s tick — so the list never reshuffles
    // under the user's finger (which dropped taps on the row buttons).
    @State private var orderedStops: [NearbyStop] = []

    private var t: Theme { m.t }

    private func computeOrder() -> [NearbyStop] {
        let list = store.nearby
        switch sortMode {
        case "arrival":
            var key: [String: Int] = [:]
            for s in list {
                key[s.stopCode] = m.liveServices(code: s.stopCode, tracked: [])
                    .map(\.etaSec).min() ?? 999_999
            }
            return list.sorted { (key[$0.stopCode] ?? 0) < (key[$1.stopCode] ?? 0) }
        case "service":
            var key: [String: Int] = [:]
            for s in list {
                key[s.stopCode] = store.servicesFor(s.stopCode)
                    .map { Int($0.no.filter(\.isNumber)) ?? 9999 }.min() ?? 9999
            }
            return list.sorted { (key[$0.stopCode] ?? 0) < (key[$1.stopCode] ?? 0) }
        default:
            return list.sorted { $0.distanceM < $1.distanceM }
        }
    }
    private func refreshOrder() { orderedStops = computeOrder() }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    LargeTitleHeader(t: t, title: "Nearby", subtitle: nil,
                                     locationSubtitle: true,
                                     onRefresh: nil, refreshing: false,
                                     collapsed: $collapsed)
                    content
                }
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "scroll")

            StickyCompactBar(t: t, title: "Nearby",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        Circle().fill(t.live).frame(width: 6, height: 6)
                        Text("LIVE").font(t.mono(10)).foregroundStyle(t.dim)
                    }),
                visible: collapsed)
        }
        .background(t.bg.ignoresSafeArea())
        .onAppear { loc.start(); store.prefetchNearbyArrivals(); refreshOrder() }
        .onChange(of: store.nearby) { _, _ in
            store.prefetchNearbyArrivals(); refreshOrder()
        }
        .onChange(of: sortMode) { _, _ in refreshOrder() }
        .onChange(of: store.arrivals) { _, _ in refreshOrder() }
    }

    @ViewBuilder private var content: some View {
        if !loc.authorized {
            permissionPrompt
        } else if case .error(let msg) = store.referenceState {
            messageCard(icon: "wifi.exclamationmark", title: "Couldn’t load stops",
                        body: msg, action: ("Retry", { Task { await store.bootstrap() } }))
        } else if store.nearby.isEmpty {
            VStack(spacing: 10) {
                ProgressView().tint(t.dim)
                Text("Finding stops near you…").font(t.sans(13)).foregroundStyle(t.dim)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        } else {
            sortRow
            VStack(spacing: 10) {
                ForEach(orderedStops) { stop in
                    NearbyStopRow(
                        stop: stop, t: t,
                        open: openId == stop.id,
                        isPinned: m.isPinned(stop.stopCode),
                        state: store.arrivals[stop.stopCode] ?? .loading,
                        onToggle: {
                            // Plain state set — instant, never blocked. The
                            // geometry change animates via .animation(value:)
                            // below, decoupled from data publishes.
                            let willOpen = openId != stop.id
                            openId = willOpen ? stop.id : nil
                            if willOpen { store.ensureArrivals(stop: stop.stopCode) }
                        },
                        onPin: { m.togglePin(code: stop.stopCode) },
                        onOpen: { busNo in m.openNearby(stop, busNo: busNo) }
                    )
                }
            }
            .animation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.30), value: openId)
            .animation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.45), value: orderedStops.map(\.stopCode))
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
    }

    private var sortRow: some View {
        HStack(spacing: 8) {
            Text("SORT").font(t.mono(10)).tracking(1).foregroundStyle(t.dim).padding(.trailing, 4)
            ForEach([("distance", "Distance"), ("arrival", "Arrival"), ("service", "Service")], id: \.0) { id, label in
                let active = sortMode == id
                Button { withAnimation(.easeInOut(duration: 0.45)) { sortMode = id } } label: {
                    Text(label)
                        .font(t.sans(11, weight: .medium))
                        .foregroundStyle(active ? t.bg : t.dim)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(active ? t.fg : .clear, in: Capsule())
                        .overlay(Capsule().stroke(active ? t.fg : t.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.circle")
                .font(.system(size: 34, weight: .light)).foregroundStyle(t.accent)
            Text("See stops near you")
                .font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg)
            Text("Leyne uses your location only to find bus stops within walking distance. It stays on your device.")
                .font(t.sans(12)).foregroundStyle(t.dim).multilineTextAlignment(.center)
            Button { loc.requestPermission() } label: {
                Text(loc.status == .denied ? "Open Settings" : "Enable location")
                    .font(t.sans(14, weight: .semibold)).foregroundStyle(t.bg)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            if loc.status == .denied {
                Text("Location is off. Enable it in Settings ▸ Leyne ▸ Location.")
                    .font(t.sans(11)).foregroundStyle(t.dim).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 28)
        .onChange(of: loc.status) { _, s in
            if s == .denied,
               let url = URL(string: UIApplication.openSettingsURLString) {
                // surface Settings deep-link on the next tap via the button label
                _ = url
            }
        }
    }

    private func messageCard(icon: String, title: String, body: String,
                             action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(t.crit)
            Text(title).font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
            Text(body).font(t.sans(11)).foregroundStyle(t.dim).multilineTextAlignment(.center)
            if let (label, run) = action {
                Button(action: run) {
                    Text(label).font(t.sans(13, weight: .medium)).foregroundStyle(t.bg)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(t.accent, in: Capsule())
                }.buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}

struct NearbyStopRow: View {
    let stop: NearbyStop
    let t: Theme
    let open: Bool
    let isPinned: Bool
    let state: ArrivalState
    let onToggle: () -> Void
    let onPin: () -> Void
    let onOpen: (String?) -> Void

    @EnvironmentObject var m: AppModel

    var body: some View {
        // Compute once per render — not 6–8× via computed properties.
        let services = m.liveServices(code: stop.stopCode, tracked: [])
        let anyArriving = services.contains { $0.etaSec <= 60 }
        return VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(spacing: 3) {
                        Text(fmtDistance(stop.distanceM))
                            .font(t.mono(14, weight: .bold)).foregroundStyle(t.fg)
                        Text("\(stop.walkMin) MIN")
                            .font(t.mono(9)).tracking(0.5).foregroundStyle(t.dim)
                    }
                    .frame(width: 44)

                    Rectangle().fill(t.line).frame(width: 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.stopName)
                            .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("STOP \(stop.stopCode)").font(t.mono(10)).foregroundStyle(t.dim)
                            if !services.isEmpty {
                                Text("·").font(t.mono(10)).foregroundStyle(t.dim.opacity(0.6))
                                Text("\(services.count) services").font(t.mono(10)).foregroundStyle(t.dim)
                            }
                            if anyArriving {
                                Text("ARRIVING")
                                    .font(t.mono(9, weight: .bold)).tracking(0.5)
                                    .foregroundStyle(t.live)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(t.liveBg, in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(t.dim)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 0) {
                    Divider().overlay(t.line)
                    expandedBody(services)
                    Divider().overlay(t.line)
                    HStack(spacing: 8) {
                        Button(action: onPin) {
                            HStack(spacing: 6) {
                                Image(systemName: isPinned ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(isPinned ? "Pinned to Home" : "Pin to Home")
                            }
                            .font(t.sans(12, weight: .medium))
                            .foregroundStyle(isPinned ? .white : t.fg)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(isPinned ? t.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isPinned ? t.accent : t.line, lineWidth: 1))
                            .contentShape(Rectangle())   // whole pill tappable
                        }
                        .buttonStyle(.plain)
                        Button { onOpen(nil) } label: {
                            HStack(spacing: 6) {
                                Text("Open")
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                            }
                            .font(t.sans(12, weight: .medium)).foregroundStyle(t.fg)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.line, lineWidth: 1))
                            .contentShape(Rectangle())   // whole pill tappable
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(anyArriving ? t.live : t.line, lineWidth: 1))
        .shadow(color: anyArriving ? t.live.opacity(0.1) : .clear, radius: 6, y: 4)
    }

    @ViewBuilder private func expandedBody(_ services: [Service]) -> some View {
        if !services.isEmpty {
            ForEach(Array(services.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider().overlay(t.line) }
                ServiceRow(s: s, t: t) { onOpen($0) }
            }
        } else {
            switch state {
            case .loading:
                HStack { ProgressView().tint(t.dim); Text("Loading arrivals…").font(t.sans(12)).foregroundStyle(t.dim) }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            case .empty:
                Text("No buses running here right now")
                    .font(t.sans(12)).foregroundStyle(t.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            case .error(let msg):
                Text(msg).font(t.sans(11)).foregroundStyle(t.crit)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            case .loaded:
                Text("No buses running here right now")
                    .font(t.sans(12)).foregroundStyle(t.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        }
    }
}
