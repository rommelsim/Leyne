// Nearby — live nearest stops sorted by distance / arrival / service number.
// Ported from Flutter v2.0 lib/screens/nearby_screen.dart.
//
// Rows are flat (no inline expand): tap a row to drill into Detail. ARRIVING
// pill sits next to the stop name when any service is ≤60s out. Service
// numbers show inline as tiny mono chips so you can see which buses stop here
// at a glance. Map FAB bottom-right is a placeholder for the upcoming map.

import SwiftUI
import CoreLocation
import UIKit

private enum NearbySort { case distance, arrival, service }

struct NearbyView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var loc: LocationManager

    @State private var sort: NearbySort = .distance
    @State private var collapsed = false
    @State private var orderedStops: [NearbyStop] = []
    @State private var arrivalLoader: Timer? = nil
    @State private var arrivalRequested = Set<String>()

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .topLeading) {
            t.bg.ignoresSafeArea()
            content
        }
        .onAppear {
            loc.startIfAuthorized()
            store.ensureRoutes()
            store.prefetchNearbyArrivals()
            refreshOrder()
            startArrivalPump()
        }
        .onDisappear { stopArrivalPump() }
        .onChange(of: store.nearby) { _, _ in refreshOrder() }
        .onChange(of: sort) { _, _ in refreshOrder() }
        .onChange(of: store.arrivals) { _, _ in refreshOrder() }
    }

    @ViewBuilder private var content: some View {
        if !loc.authorized {
            VStack(spacing: 0) {
                header
                permissionPrompt
                Spacer()
            }
        } else if case .error(let msg) = store.referenceState {
            VStack(spacing: 0) {
                header
                errorCard(msg)
                Spacer()
            }
        } else if orderedStops.isEmpty {
            VStack(spacing: 0) {
                header
                Spacer().frame(height: 100)
                VStack(spacing: 12) {
                    ProgressView().tint(t.dim)
                    Text("Finding stops near you…")
                        .font(t.sans(13)).foregroundStyle(t.dim)
                }.frame(maxWidth: .infinity)
                Spacer()
            }
        } else {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header.background(GeometryReader { geo in
                            Color.clear.preference(key: TitleOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).minY)
                        })
                        sortRow
                        rowList
                    }
                    .padding(.bottom, 96)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(TitleOffsetKey.self) { y in
                    let c = y < -12
                    if c != collapsed { collapsed = c }
                }
                StickyCompactBar(t: t, title: "Nearby",
                    trailing: AnyView(radiusChip),
                    visible: collapsed)
            }
        }
    }

    // MARK: header + sort row

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Nearby")
                .font(t.sans(28, weight: .semibold))
                .foregroundStyle(t.fg)
            Spacer()
            radiusChip
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    private var radiusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope").font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.dim)
            Text("\(m.searchRadiusM)M")
                .font(t.mono(11, weight: .semibold)).tracking(1)
                .foregroundStyle(t.dim)
        }
    }

    private var sortRow: some View {
        HStack(spacing: 8) {
            Text("SORT").font(t.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.dim).padding(.trailing, 4)
            sortChip(.distance, "Distance")
            sortChip(.arrival, "Arrival")
            sortChip(.service, "Service")
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
    }

    private func sortChip(_ s: NearbySort, _ label: String) -> some View {
        let active = sort == s
        return Button {
            Feedback.shared.select()
            withAnimation(.easeInOut(duration: 0.3)) { sort = s }
        } label: {
            Text(label)
                .font(t.sans(13, weight: .medium))
                .foregroundStyle(active ? t.bg : t.dim)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(active ? t.fg : .clear, in: Capsule())
                .overlay(Capsule().stroke(active ? t.fg : t.line, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: rows

    private var rowList: some View {
        VStack(spacing: 6) {
            ForEach(orderedStops) { stop in
                NearbyRowFlat(stop: stop, t: t, m: m, store: store)
                    .onTapGesture { m.openNearby(stop) }
            }
        }
        .padding(.horizontal, 14).padding(.top, 4)
    }

    // MARK: states

    private var permissionPrompt: some View {
        let blocked = loc.deniedForever
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(t.surface)
                    .frame(width: 56, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.line, lineWidth: 1))
                Image(systemName: "location")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(t.accent)
            }
            Text("See stops near you")
                .font(t.sans(17, weight: .semibold)).foregroundStyle(t.fg)
            Text("Leyne uses your location only to find bus stops within walking distance. It stays on your device.")
                .font(t.sans(13)).foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
            Button {
                if blocked { loc.openAppSettings() } else { loc.requestAndStart() }
            } label: {
                Text(blocked ? "Open Settings" : "Enable location")
                    .font(t.sans(14, weight: .semibold)).foregroundStyle(t.contrastFg)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(t.accent, in: Capsule())
            }.buttonStyle(.plain)
            if blocked {
                Text("Location is off. Enable it in system settings.")
                    .font(t.sans(11)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50).padding(.horizontal, 32)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(t.crit.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(t.crit)
            }
            VStack(spacing: 4) {
                Text("Can't reach LTA right now")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text(msg)
                    .font(t.sans(12)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Button { Task { await store.bootstrap() } } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.contrastFg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(t.accent, in: Capsule())
            }
            .buttonStyle(PressableRowStyle(scale: 0.96))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50).padding(.horizontal, 32)
    }

    // MARK: ordering + arrival pump

    private func refreshOrder() {
        let list = store.nearby
        switch sort {
        case .distance:
            orderedStops = list.sorted { $0.distanceM < $1.distanceM }
        case .arrival:
            var key: [String: Int] = [:]
            for s in list {
                key[s.stopCode] = m.liveServices(code: s.stopCode, tracked: [])
                    .map(\.etaSec).min() ?? Int.max
            }
            orderedStops = list.sorted { (key[$0.stopCode] ?? 0) < (key[$1.stopCode] ?? 0) }
        case .service:
            var key: [String: Int] = [:]
            for s in list {
                let nos = store.servicesAtStop(s.stopCode)
                key[s.stopCode] = nos.compactMap {
                    Int($0.filter(\.isNumber))
                }.min() ?? Int.max
            }
            orderedStops = list.sorted { (key[$0.stopCode] ?? 0) < (key[$1.stopCode] ?? 0) }
        }
    }

    /// Fire up to 3 not-yet-requested nearby stops every 700ms so the whole
    /// nearby list has live arrivals (needed for the Arrival sort and the
    /// ARRIVING pill on each row).
    private func startArrivalPump() {
        arrivalLoader?.invalidate()
        arrivalLoader = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            Task { @MainActor in pumpArrivalLoad() }
        }
        pumpArrivalLoad()
    }

    private func stopArrivalPump() {
        arrivalLoader?.invalidate()
        arrivalLoader = nil
    }

    @MainActor
    private func pumpArrivalLoad() {
        var fired = 0
        for s in store.nearby {
            if fired >= 3 { break }
            if arrivalRequested.insert(s.stopCode).inserted {
                store.ensureArrivals(stop: s.stopCode, silent: true)
                fired += 1
            }
        }
    }
}

// MARK: - NearbyRowFlat

private struct NearbyRowFlat: View {
    let stop: NearbyStop
    let t: Theme
    let m: AppModel
    let store: DataStore

    var body: some View {
        let services = m.liveServices(code: stop.stopCode, tracked: [])
        let anyArriving = services.contains { $0.etaSec <= 60 }
        let arrivingNos = Set(services.filter { $0.etaSec <= 60 }.map(\.no))
        let svcNos = store.servicesAtStop(stop.stopCode)

        HStack(alignment: .center, spacing: 12) {
            // Distance + walk
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(stop.distanceM)")
                        .font(t.mono(17, weight: .semibold)).foregroundStyle(t.fg)
                    Text("m").font(t.mono(10)).foregroundStyle(t.dim)
                }
                Text("\(stop.walkMin) MIN")
                    .font(t.mono(9)).tracking(0.5).foregroundStyle(t.faint)
            }
            .frame(width: 52, alignment: .trailing)

            Rectangle().fill(t.line).frame(width: 1, height: 36)

            // Stop info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stop.stopName)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(1)
                    if anyArriving {
                        Text("ARRIVING")
                            .font(t.mono(9, weight: .bold)).tracking(0.6)
                            .foregroundStyle(t.live)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(t.liveBg, in: Capsule())
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text(stop.stopCode).font(t.mono(10)).foregroundStyle(t.faint)
                    serviceChipsRow(svcNos: svcNos, arrivingNos: arrivingNos)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        // Arriving stops keep their faint accent tint (it's a status colour,
        // not chrome). Otherwise lift the row onto glass so Nearby reads
        // the same as Home's pinned-card stack.
        .background(
            Group {
                if anyArriving { t.accent.opacity(0.05) } else { t.glassSurface() }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(anyArriving ? t.accent.opacity(0.35) : t.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func serviceChipsRow(svcNos: [String], arrivingNos: Set<String>) -> some View {
        let shown = Array(svcNos.prefix(6))
        let overflow = svcNos.count - shown.count
        return HStack(spacing: 4) {
            ForEach(shown, id: \.self) { no in
                serviceChip(no, arriving: arrivingNos.contains(no))
            }
            if overflow > 0 {
                Text("+\(overflow)").font(t.mono(10)).foregroundStyle(t.faint)
            }
            Spacer(minLength: 0)
        }
    }

    private func serviceChip(_ no: String, arriving: Bool) -> some View {
        Text(no)
            .font(t.mono(10, weight: .semibold))
            .foregroundStyle(arriving ? t.contrastFg : t.fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(arriving ? t.accent : t.lineHi)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
