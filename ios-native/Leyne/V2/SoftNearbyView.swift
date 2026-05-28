// SoftNearbyView — Leyne 2.0 Nearby: sort chips + list of nearby stops
// driven by DataStore.nearby and LocationManager.

import SwiftUI

enum SoftNearbySort: Hashable { case distance, arrival, service }

struct SoftNearbyView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore
    @StateObject private var loc = LocationManager.shared

    @State private var sort: SoftNearbySort = .distance
    let onTab: (SoftTab) -> Void
    let onOpenStop: (String) -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Stops within 500m", t: t)
                        Text("Near you")
                            .font(t.sans(30, weight: .semibold))
                            .foregroundStyle(t.fg)
                    }

                    SortChipRow(t: t, selection: $sort, options: [
                        (.distance, "Distance"),
                        (.arrival, "Arrival"),
                        (.service, "Service"),
                    ])

                    if sortedStops.isEmpty {
                        Text(emptyMessage)
                            .font(t.sans(13))
                            .foregroundStyle(t.dim)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sortedStops.prefix(20), id: \.id) { stop in
                                row(stop: stop)
                            }
                        }
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            SoftBottomBar(t: t,
                          selection: Binding(get: { .nearby }, set: { onTab($0) }),
                          onSelect: { _ in fb.select() })
                .padding(.bottom, 12)
        }
        .onAppear {
            loc.startIfAuthorized()
            if let l = loc.location { ds.updateNearby(l) }
            ds.prefetchNearbyArrivals()
        }
        .onChange(of: loc.location) { _, new in
            if let l = new { ds.updateNearby(l); ds.prefetchNearbyArrivals() }
        }
    }

    private var sortedStops: [NearbyStop] {
        switch sort {
        case .distance: return ds.nearby
        case .arrival:
            return ds.nearby.sorted { soonest($0) < soonest($1) }
        case .service:
            return ds.nearby.sorted { ($0.services.count > $1.services.count) }
        }
    }

    private func soonest(_ s: NearbyStop) -> Int {
        let live = ds.servicesFor(s.stopCode)
        return live.map { $0.etaSec }.min() ?? Int.max
    }

    private var emptyMessage: String {
        switch loc.status {
        case .denied, .restricted:
            return "Location is off. Enable in Settings to see nearby stops."
        case .notDetermined:
            return "Allow location access to find stops near you."
        default:
            return "Looking for nearby stops…"
        }
    }

    private func row(stop: NearbyStop) -> some View {
        let live = ds.servicesFor(stop.stopCode).first

        return Button {
            fb.select()
            onOpenStop(stop.stopCode)
        } label: {
            HStack(spacing: 12) {
                WalkTile(t: t, minutes: stop.walkMin)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.stopName)
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("\(fmtDistance(stop.distanceM)) · \(stop.stopCode)")
                            .font(t.mono(11))
                            .foregroundStyle(t.dim)
                        if let s = live {
                            Text("·")
                                .font(t.mono(11)).foregroundStyle(t.faint)
                            Text("\(s.no) \(fmtETA(s.etaSec).big)\(fmtETA(s.etaSec).small)")
                                .font(t.mono(11, weight: .semibold))
                                .foregroundStyle(t.accent)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressScale()
    }
}
