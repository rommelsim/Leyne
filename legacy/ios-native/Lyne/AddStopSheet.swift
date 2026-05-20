// Add-a-stop sheet — two-step: pick a stop (live search) → pick which buses.

import SwiftUI

struct AddStopSheet: View {
    let t: Theme
    let onClose: () -> Void
    let onAdd: (String, [String]) -> Void     // (stopCode, trackedServiceNos)

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var q = ""
    @State private var selectedCode: String?
    @State private var tracked: Set<String> = []

    private var buses: [LTABusServiceDTO] { store.searchServices(q) }
    private var stops: [LTABusStop] { store.searchStops(q) }
    private var selectedServices: [Service] {
        guard let c = selectedCode else { return [] }
        return m.liveServices(code: c, tracked: [])
    }

    private func pick(_ code: String) {
        selectedCode = code
        store.ensureArrivals(stop: code, force: true)
        tracked = Set(m.liveServices(code: code, tracked: []).map(\.no))
    }
    private func confirm() {
        guard let c = selectedCode else { return }
        onAdd(c, Array(tracked))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if m.showAdd {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)
                VStack(spacing: 0) {
                    Capsule().fill(t.line).frame(width: 36, height: 5)
                        .padding(.top, 8).padding(.bottom, 14)
                    header
                    if selectedCode == nil { step1 } else { step2 }
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
                .background(t.bg)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .transition(.move(edge: .bottom))
            }
        }
        // Dim fades, card springs up from the bottom (and back down on close).
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: m.showAdd)
        // The view now persists, so start each open fresh (matches the old
        // recreate-on-present behaviour).
        .onChange(of: m.showAdd) { _, open in
            if open { q = ""; selectedCode = nil; tracked = [] }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                if selectedCode != nil {
                    Button { selectedCode = nil } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(t.accent)
                    }
                }
                Text(selectedCode != nil ? "Pick buses to track" : "Add a bus stop")
                    .font(t.sans(20, weight: .semibold)).foregroundStyle(t.fg).lineLimit(1)
            }
            Spacer()
            Button("Cancel", action: onClose).font(t.sans(15)).foregroundStyle(t.accent)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    // ─── Step 1: pick stop ────────────────────────────────
    private var step1: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(t.dim)
                    TextField("Bus or stop (name / code)", text: $q)
                        .font(t.sans(14)).foregroundStyle(t.fg).autocorrectionDisabled()
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(t.dim)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))

                if !q.isEmpty {
                    HStack {
                        (Text("DETECTED · ")
                         + Text(detectQueryKind(q).label.isEmpty ? "ANYTHING" : detectQueryKind(q).label.uppercased())
                            .foregroundColor(t.fg))
                            .font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                        Spacer()
                    }.padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    if q.isEmpty {
                        nearbyList
                    } else if buses.isEmpty && stops.isEmpty {
                        VStack(spacing: 4) {
                            Text("Nothing matches “\(q)”").font(t.sans(13))
                            Text("Try a bus number or a stop name / 5-digit code.").font(t.sans(11))
                        }.foregroundStyle(t.dim).padding(32)
                    } else {
                        resultsList
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder private var nearbyList: some View {
        Text("NEARBY").font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.horizontal, 4)
        if store.nearby.isEmpty {
            Text("Enable location in Nearby to see stops around you, or search above.")
                .font(t.sans(12)).foregroundStyle(t.dim).padding(.horizontal, 4).padding(.bottom, 8)
        }
        ForEach(Array(store.nearby.enumerated()), id: \.element.id) { i, stop in
            if i > 0 { Divider().overlay(t.line) }
            Button { pick(stop.stopCode) } label: { stopRow(name: stop.stopName,
                code: stop.stopCode, trailing: fmtDistance(stop.distanceM)) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var resultsList: some View {
        if !buses.isEmpty {
            groupHeader("BUSES", buses.count)
            ForEach(Array(buses.prefix(8).enumerated()), id: \.element.ServiceNo) { i, b in
                if i > 0 { Divider().overlay(t.line) }
                Button { Task {
                    if let s = await store.originStop(ofService: b.ServiceNo) { pick(s.BusStopCode) }
                } } label: {
                    HStack(spacing: 12) {
                        Text(b.ServiceNo).font(t.mono(13, weight: .bold)).foregroundStyle(.white)
                            .frame(minWidth: 44, minHeight: 30)
                            .background(t.live, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Service \(b.ServiceNo)").font(t.sans(13, weight: .medium)).foregroundStyle(t.fg)
                            Text((b.Operator ?? "") + " · opens its first stop")
                                .font(t.mono(10)).foregroundStyle(t.dim).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(t.dim)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                }.buttonStyle(.plain)
            }
        }
        if !stops.isEmpty {
            groupHeader("STOPS", stops.count)
            ForEach(Array(stops.prefix(30).enumerated()), id: \.element.BusStopCode) { i, s in
                if i > 0 { Divider().overlay(t.line) }
                Button { pick(s.BusStopCode) } label: {
                    stopRow(name: s.Description, code: s.BusStopCode, trailing: s.RoadName)
                }.buttonStyle(.plain)
            }
        }
    }

    private func groupHeader(_ label: String, _ count: Int) -> some View {
        HStack { Text(label); Spacer(); Text("\(count)") }
            .font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim)
            .padding(.top, 14).padding(.bottom, 6).padding(.horizontal, 4)
    }

    private func stopRow(name: String, code: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg).lineLimit(1)
                Text("STOP \(code) · \(trailing)").font(t.mono(10)).foregroundStyle(t.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(t.dim)
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
    }

    // ─── Step 2: pick buses ───────────────────────────────
    @ViewBuilder private var step2: some View {
        if let code = selectedCode {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.stopName(code)).font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg)
                Text("STOP \(code) · \(store.roadName(code))")
                    .font(t.mono(11)).foregroundStyle(t.dim)
                Text("Pick which buses appear on Home. You can change this anytime.")
                    .font(t.sans(12)).foregroundStyle(t.dim).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    if selectedServices.isEmpty {
                        HStack { ProgressView().tint(t.dim)
                            Text("Loading buses…").font(t.sans(12)).foregroundStyle(t.dim) }
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        Button {
                            tracked = tracked.count == selectedServices.count
                                ? [] : Set(selectedServices.map(\.no))
                        } label: {
                            HStack {
                                Text("All buses").font(t.sans(12)).foregroundStyle(t.fg)
                                Spacer()
                                Text(tracked.count == selectedServices.count ? "On" : "Off")
                                    .font(t.mono(11)).foregroundStyle(t.dim)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(t.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain).padding(.bottom, 12)

                        VStack(spacing: 0) {
                            ForEach(Array(selectedServices.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { Divider().overlay(t.line) }
                                Button {
                                    if tracked.contains(s.no) { tracked.remove(s.no) }
                                    else { tracked.insert(s.no) }
                                } label: {
                                    HStack(spacing: 12) {
                                        let on = tracked.contains(s.no)
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(on ? t.accent : .clear)
                                                .frame(width: 22, height: 22)
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? t.accent : t.line, lineWidth: 1.5))
                                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) }
                                        }
                                        Text(s.no).font(t.mono(17, weight: .bold)).foregroundStyle(t.fg)
                                            .frame(minWidth: 44, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("→ \(s.dest)").font(t.sans(13)).foregroundStyle(t.fg).lineLimit(1)
                                            Text("\(s.load.label) · \(s.deck.word)\(s.wab ? " · ♿" : "")")
                                                .font(t.mono(10)).foregroundStyle(t.dim)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(t.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))

                        Text(tracked.isEmpty
                             ? "Pick at least one bus to continue."
                             : "\(tracked.count) of \(selectedServices.count) buses will appear on Home.")
                            .font(t.mono(11)).foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 14).padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
            }

            Button(action: confirm) {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill").font(.system(size: 13))
                    Text("Pin to Home")
                }
                .font(t.sans(15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(tracked.isEmpty ? t.line : t.accent, in: RoundedRectangle(cornerRadius: 14))
                .opacity(tracked.isEmpty ? 0.6 : 1)
            }
            .buttonStyle(.plain).disabled(tracked.isEmpty)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 28)
        }
    }
}
