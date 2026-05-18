// Quick Search — Conservative (A) + Ambitious (B). Live LTA Buses + Stops.

import SwiftUI

// ═══ Variant A — Conservative ═══════════════════════════════
struct SearchSheetA: View {
    let t: Theme
    let dark: Bool
    let onClose: () -> Void
    let onPick: (String) -> Void          // stop code

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var q = ""
    @FocusState private var focused: Bool

    private var buses: [LTABusServiceDTO] { store.searchServices(q) }
    private var stops: [LTABusStop] { store.searchStops(q) }
    private var total: Int { buses.count + stops.count }

    private func pickStop(_ code: String) {
        m.addRecent(q.isEmpty ? store.stopName(code) : q)
        onPick(code); onClose()
    }
    private func pickBus(_ no: String) {
        Task {
            if let s = await store.originStop(ofService: no) {
                m.addRecent(no); onPick(s.BusStopCode); onClose()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(t.dim)
                        .padding(.leading, 10)
                    TextField("Bus or stop (name / code)", text: $q)
                        .focused($focused).font(t.sans(15)).foregroundStyle(t.fg)
                        .autocorrectionDisabled().padding(.horizontal, 8)
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(t.dim)
                        }.padding(.trailing, 10)
                    }
                }
                .frame(height: 40)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))
                Button("Cancel", action: onClose).font(t.sans(14, weight: .medium)).foregroundStyle(t.accent)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            .overlay(alignment: .bottom) { Divider().overlay(t.line) }

            if !q.isEmpty {
                HStack {
                    (Text("DETECTED · ")
                     + Text(detectQueryKind(q).label.isEmpty ? "ANY" : detectQueryKind(q).label.uppercased()).foregroundColor(t.fg)
                     + Text(total > 0 ? " · \(total) match\(total == 1 ? "" : "es")" : ""))
                        .font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
            }

            ScrollView { if q.isEmpty { emptyState } else { results } }

            HStack {
                Text("AT A STOP?").font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "qrcode").font(.system(size: 13))
                    Text("Scan poster QR")
                }
                .font(t.sans(12, weight: .medium)).foregroundStyle(t.fg)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().stroke(t.line, lineWidth: 1))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .top) { Divider().overlay(t.line) }
        }
        .background(t.bg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onClose(); m.setTab(.nearby) } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9).fill(t.accent.opacity(0.09))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "location.fill").foregroundStyle(t.accent))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Stops near me").font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                        Text("Live, sorted by walking distance").font(t.sans(11)).foregroundStyle(t.dim)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(t.dim)
                }
                .padding(14)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.bottom, 18)

            if !m.recents.isEmpty {
                Text("RECENT").font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim).padding(.bottom, 10)
                FlowChips(items: m.recents, t: t) { q = $0 }
            } else {
                Text("Search a bus number or a stop name / 5-digit code.")
                    .font(t.sans(12)).foregroundStyle(t.dim).padding(.top, 8)
            }
        }
        .padding(16)
    }

    @ViewBuilder private var results: some View {
        VStack(spacing: 0) {
            if total == 0 {
                VStack(spacing: 6) {
                    Text("Nothing matches “\(q)”").font(t.sans(13))
                    Text("Try a bus number or a stop name / 5-digit code.").font(t.sans(11))
                }.foregroundStyle(t.dim).padding(40)
            }
            if !buses.isEmpty {
                srGroup("BUSES", buses.count) {
                    ForEach(buses.prefix(20), id: \.ServiceNo) { b in
                        SRRow(t: t, leading: .bus(b.ServiceNo),
                              title: b.LoopDesc?.isEmpty == false ? "Loop · \(b.LoopDesc!)" : "Service \(b.ServiceNo)",
                              sub: (b.Operator ?? "") + (b.Category.map { " · \($0.capitalized)" } ?? "")) {
                            pickBus(b.ServiceNo)
                        }
                    }
                }
            }
            if !stops.isEmpty {
                srGroup("STOPS", stops.count) {
                    ForEach(stops.prefix(30), id: \.BusStopCode) { s in
                        SRRow(t: t, leading: .icon("smallcircle.filled.circle", t.accent),
                              title: s.Description, sub: "STOP \(s.BusStopCode) · \(s.RoadName)") {
                            pickStop(s.BusStopCode)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4).padding(.bottom, 24)
    }

    private func srGroup<C: View>(_ label: String, _ count: Int, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack { Text(label); Spacer(); Text("\(count)") }
                .font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
            c()
        }
    }
}

// ═══ Variant B — Ambitious ══════════════════════════════════
struct SearchSheetB: View {
    let t: Theme
    let dark: Bool
    let onClose: () -> Void
    let onPick: (String) -> Void

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var store: DataStore
    @State private var q = ""
    @FocusState private var focused: Bool

    private var buses: [LTABusServiceDTO] { store.searchServices(q) }
    private var stops: [LTABusStop] { store.searchStops(q) }
    private var total: Int { buses.count + stops.count }
    private var detected: DetectedKind { detectQueryKind(q) }

    private var kindColor: Color {
        switch detected.kind {
        case "bus": return t.live
        case "stopcode": return t.accent
        case "postal", "block": return t.warn
        case "text": return t.fg
        default: return t.dim
        }
    }

    private func pickStop(_ code: String) {
        m.addRecent(q.isEmpty ? store.stopName(code) : q); onPick(code); onClose()
    }
    private func pickBus(_ no: String) {
        Task { if let s = await store.originStop(ofService: no) {
            m.addRecent(no); onPick(s.BusStopCode); onClose() } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SEARCH").font(t.mono(11)).tracking(1.4).foregroundStyle(t.dim)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(t.fg)
                        .frame(width: 32, height: 32)
                        .background(t.surface, in: Circle())
                        .overlay(Circle().stroke(t.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

            HStack {
                TextField("What are you looking for?", text: $q)
                    .focused($focused)
                    .font(t.sans(36, weight: .medium)).foregroundStyle(t.fg)
                    .autocorrectionDisabled()
                if !q.isEmpty {
                    Button { q = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 18)).foregroundStyle(t.dim)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(q.isEmpty ? t.dim : kindColor).frame(width: 5, height: 5)
                    Text(q.isEmpty ? "WAITING" : (detected.label.isEmpty ? "ANYTHING" : detected.label.uppercased()))
                }
                .font(t.mono(11)).tracking(0.8)
                .foregroundStyle(q.isEmpty ? t.dim : kindColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background((q.isEmpty ? t.dim : kindColor).opacity(q.isEmpty ? 0.06 : 0.13), in: Capsule())
                .overlay(Capsule().stroke(q.isEmpty ? t.line : kindColor.opacity(0.33), lineWidth: 1))
                if !q.isEmpty && total > 0 {
                    Text("\(total) MATCH\(total == 1 ? "" : "ES")").font(t.mono(11)).foregroundStyle(t.dim)
                }
                Spacer()
                Image(systemName: "qrcode").font(.system(size: 16)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)

            ScrollView { if q.isEmpty { emptyStateB } else { resultsB } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((dark ? Color(hex: "0a0907") : Color(hex: "FBF8F0")).ignoresSafeArea())
        .onAppear { focused = true }
    }

    @ViewBuilder private var emptyStateB: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onClose(); m.setTab(.nearby) } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 11).fill(t.bg.opacity(0.13))
                        .frame(width: 42, height: 42)
                        .overlay(Image(systemName: "location.fill").foregroundStyle(t.bg))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HERE").font(t.mono(11)).tracking(0.8).opacity(0.6)
                        Text("Stops within walking distance").font(t.sans(15, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 16))
                }
                .foregroundStyle(t.bg).padding(16)
                .background(t.fg, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).padding(.bottom, 16)

            if !m.recents.isEmpty {
                Text("RECENT").font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim).padding(.bottom, 4)
                ForEach(m.recents, id: \.self) { r in
                    Button { q = r } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(t.dim)
                            Text(r).font(t.sans(14)).foregroundStyle(t.fg)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Divider().overlay(t.line) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 32)
    }

    @ViewBuilder private var resultsB: some View {
        VStack(alignment: .leading, spacing: 0) {
            if total == 0 {
                VStack(spacing: 4) {
                    Text("Nothing matches that.").font(t.sans(14)).foregroundStyle(t.fg)
                    Text("I look up bus services and bus stops.").font(t.sans(12)).foregroundStyle(t.dim)
                }.frame(maxWidth: .infinity).padding(48)
            }
            if !buses.isEmpty {
                srGroupB("Buses", t.live) {
                    ForEach(buses.prefix(20), id: \.ServiceNo) { b in
                        richRow(lead: .bus(b.ServiceNo),
                                title: b.LoopDesc?.isEmpty == false ? "Loop · \(b.LoopDesc!)" : "Service \(b.ServiceNo)",
                                sub: (b.Operator ?? "")) { pickBus(b.ServiceNo) }
                    }
                }
            }
            if !stops.isEmpty {
                srGroupB("Stops", t.accent) {
                    ForEach(stops.prefix(30), id: \.BusStopCode) { s in
                        richRow(lead: .icon("smallcircle.filled.circle", t.accent),
                                title: s.Description, sub: "STOP \(s.BusStopCode) · \(s.RoadName)") {
                            pickStop(s.BusStopCode)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func srGroupB<C: View>(_ label: String, _ accent: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(label.uppercased()).font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim)
                Rectangle().fill(t.line).frame(height: 1)
            }
            .padding(.horizontal, 18).padding(.bottom, 8)
            VStack(spacing: 6) { c() }.padding(.horizontal, 12)
        }
        .padding(.top, 18)
    }

    private enum Lead { case bus(String), icon(String, Color) }
    private func richRow(lead: Lead, title: String, sub: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                switch lead {
                case .bus(let no):
                    Text(no).font(t.mono(15, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 56, minHeight: 38)
                        .background(t.live, in: RoundedRectangle(cornerRadius: 8))
                case .icon(let name, let c):
                    RoundedRectangle(cornerRadius: 11).fill(c.opacity(0.13))
                        .frame(width: 42, height: 42)
                        .overlay(Image(systemName: name).font(.system(size: 17)).foregroundStyle(c))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg).lineLimit(1)
                    Text(sub).font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ─── Shared compact row (variant A) ───────────────────────
struct SRRow: View {
    let t: Theme
    enum Lead { case bus(String), icon(String, Color) }
    let leading: Lead
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                switch leading {
                case .bus(let no):
                    Text(no).font(t.mono(13, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 48, minHeight: 32)
                        .background(t.live, in: RoundedRectangle(cornerRadius: 7))
                case .icon(let name, let c):
                    RoundedRectangle(cornerRadius: 9).fill(c.opacity(0.09))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: name).font(.system(size: 15)).foregroundStyle(c))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg).lineLimit(1)
                    Text(sub).font(t.mono(11)).foregroundStyle(t.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct FlowChips: View {
    let items: [String]
    let t: Theme
    let onTap: (String) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item).font(t.sans(12)).foregroundStyle(t.fg)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t.surface, in: Capsule())
                        .overlay(Capsule().stroke(t.line, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
}
