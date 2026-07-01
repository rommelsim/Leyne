// Lines (MRT/LRT status), Saved, Settings and the Switch (nearby) screen (iOS).

import SwiftUI

// MARK: shared

private struct RDBackHeader: View {
    let title: String
    var subtitle: String? = nil
    let t: RDTokens
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            RDCircleButton(symbol: "arrow.left", label: "Back", bordered: false, iconSize: 24, t: t, action: onBack)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(rdFont(subtitle == nil ? 24 : 22, .heavy)).foregroundStyle(t.onSurface)
                if let subtitle {
                    Text(subtitle).font(rdFont(12, .medium)).foregroundStyle(t.onVariant)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }
}

private struct RDSectionLabel: View {
    let text: String
    var color: Color? = nil
    let t: RDTokens
    var body: some View {
        Text(text).font(rdFont(11, .bold)).foregroundStyle(color ?? t.onVariant).kerning(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RDToggleSwitch: View {
    let on: Bool
    let t: RDTokens
    var body: some View {
        Capsule().fill(on ? t.primary : t.scHighest)
            .frame(width: 48, height: 28)
            .overlay(
                Circle().fill(on ? t.onPrimary : t.outline).frame(width: 22, height: 22)
                    .padding(.horizontal, 3),
                alignment: on ? .trailing : .leading)
    }
}

// ==================================================================== LINES

struct RDLinesScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore

    var body: some View {
        let alerts = store.trainAlerts
        let disrupted = Set(alerts.compactMap { $0.line })
        let normal = MRTLine.allCases.filter { !disrupted.contains($0) }
        return VStack(spacing: 0) {
            RDBackHeader(title: "MRT & LRT",
                         subtitle: alerts.isEmpty
                            ? "All lines running normally · live from LTA"
                            : "\(disrupted.count) line\(disrupted.count == 1 ? "" : "s") affected · live from LTA",
                         t: t) { m.back() }
            ScrollView {
                VStack(spacing: 11) {
                    ForEach(alerts) { a in majorCard(a) }
                    ForEach(normal, id: \.self) { line in lineRow(line) }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .background(t.surface)
        .onAppear { store.refreshTrainAlertsIfStale() }
    }

    private func badge(code: String, bg: Color, size: CGFloat = 44) -> some View {
        Text(code).font(rdFont(14, .black)).foregroundStyle(rdMrtBadgeFg(code))
            .frame(width: size, height: size)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func majorCard(_ a: TrainAlert) -> some View {
        let color = a.line?.color ?? t.mrt
        let code = a.line?.rawValue ?? String(a.lineCode.prefix(2))
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                badge(code: code, bg: color, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).font(rdFont(16, .heavy)).foregroundStyle(t.onMrtContainer).lineLimit(2)
                    HStack(spacing: 4) {
                        RDSym("exclamationmark.triangle.fill", size: 15, color: t.mrt)
                        Text("DISRUPTION").font(rdFont(11, .heavy)).foregroundStyle(t.mrt).kerning(0.22)
                    }
                }
                Spacer()
            }
            Text(a.detail).font(rdFont(13, .medium)).foregroundStyle(t.onMrtContainer)
            if a.freeBus || a.freeShuttle {
                HStack(spacing: 6) {
                    if a.freeBus { freeChip("Free bus rides") }
                    if a.freeShuttle { freeChip("Free shuttle") }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.mrtContainer)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(t.mrt, lineWidth: 2))
    }

    private func freeChip(_ s: String) -> some View {
        Text(s).font(rdFont(10.5, .bold)).foregroundStyle(t.onMrtContainer)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(t.surface.opacity(0.55)).clipShape(Capsule())
    }

    private func lineRow(_ line: MRTLine) -> some View {
        RDCard(t: t) {
            HStack(spacing: 13) {
                badge(code: line.rawValue, bg: line.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(line.displayName) Line").font(rdFont(15, .bold)).foregroundStyle(t.onSurface)
                    Text("Running normally").font(rdFont(12, .medium)).foregroundStyle(t.onVariant)
                }
                Spacer()
                HStack(spacing: 5) {
                    RDDot(color: t.bus, size: 6)
                    Text("Normal").font(rdFont(11.5, .bold)).foregroundStyle(t.onBusContainer)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(t.busContainer).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(.horizontal, 15).padding(.vertical, 14)
        }
    }
}

// ==================================================================== SAVED

struct RDSavedScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore

    var body: some View {
        let stops = m.savedStopCodes.sorted()
        let buses = m.savedRoutes.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        return VStack(spacing: 0) {
            RDBackHeader(title: "Saved", t: t) { m.back() }
            ScrollView {
                if stops.isEmpty && buses.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 22) {
                        if !buses.isEmpty {
                            section("BUSES") {
                                rows(buses) { busRow($0) }
                            }
                        }
                        if !stops.isEmpty {
                            section("STOPS") {
                                rows(stops) { code in
                                    Button(action: { m.openStop(code: code) }) { stopRow(code) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .background(t.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            RDSym("bookmark", size: 34, color: t.outline)
            Text("Nothing saved yet").font(rdFont(16, .heavy)).foregroundStyle(t.onSurface)
            Text("Tap the bookmark on a stop or bus to save it here.")
                .font(rdFont(13, .medium)).foregroundStyle(t.onVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 90).padding(.horizontal, 44)
    }

    private func section<C: View>(_ label: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            RDSectionLabel(text: label, t: t)
            RDCard(t: t, radius: 20) { content() }
        }
    }

    @ViewBuilder
    private func rows<Item: Hashable, C: View>(_ items: [Item], @ViewBuilder _ row: @escaping (Item) -> C) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { i, item in
                if i > 0 { Rectangle().fill(t.outlineVariant).frame(height: 1) }
                row(item)
            }
        }
    }

    private func busRow(_ svc: String) -> some View {
        HStack(spacing: 13) {
            Text(svc).font(rdFont(15, .heavy)).foregroundStyle(t.onSurface)
                .padding(.horizontal, 12).frame(height: 42)
                .background(t.scHighest)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Saved bus").font(rdFont(14, .bold)).foregroundStyle(t.onSurface)
            Spacer()
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
    }

    private func stopRow(_ code: String) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(store.stopName(code)).font(rdFont(15, .bold)).foregroundStyle(t.onSurface).lineLimit(1)
                    RDMrtBadgeRow(stopName: store.stopName(code), size: 8)
                }
                Text("Stop \(code)").font(rdFont(12, .medium)).foregroundStyle(t.onVariant)
            }
            Spacer()
            RDSym("chevron.right", size: 20, color: t.outline)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// ================================================================= SETTINGS

struct RDSettingsScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens

    var body: some View {
        VStack(spacing: 0) {
            RDBackHeader(title: "Settings", t: t) { m.back() }
            ScrollView {
                VStack(spacing: 18) {
                    appearance
                    permissions
                    about
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 24)
            }
        }
        .background(t.surface)
    }

    private func sectionLabel(_ s: String) -> some View {
        RDSectionLabel(text: s, color: t.primary, t: t).padding(.horizontal, 6).padding(.bottom, 9)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("APPEARANCE")
            RDCard(t: t) {
                Button(action: { m.toggleTheme() }) {
                    settingRow(m.dark ? "moon.fill" : "sun.max.fill", "Dark theme",
                               "Switch between light and dark", iconColor: t.primary) {
                        AnyView(RDToggleSwitch(on: m.dark, t: t))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 15)
                }.buttonStyle(.plain)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ONBOARDING & PERMISSIONS")
            RDCard(t: t) {
                VStack(spacing: 0) {
                    Button(action: { m.replayOnboarding() }) {
                        settingRow("arrow.clockwise", "Replay onboarding",
                                   "See the welcome & permission flow again", iconColor: t.onVariant,
                                   pad: true) { AnyView(RDSym("chevron.right", size: 20, color: t.outline)) }
                    }.buttonStyle(.plain)
                    Divider().background(t.outlineVariant)
                    settingRow("exclamationmark.triangle.fill", "MRT disruption alerts", nil,
                               iconColor: t.mrt, pad: true) { AnyView(RDToggleSwitch(on: true, t: t)) }
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ABOUT")
            RDCard(t: t) {
                VStack(spacing: 0) {
                    settingRow("externaldrive.fill", "Data source", nil, iconColor: t.onVariant, pad: true) {
                        AnyView(Text("LTA · 15s").font(rdFont(12, .medium)).foregroundStyle(t.onVariant))
                    }
                    Divider().background(t.outlineVariant)
                    settingRow("hand.tap.fill", "Remove ads", nil, iconColor: t.onVariant, pad: true) {
                        AnyView(Text("$2.98").font(rdFont(12, .semibold)).foregroundStyle(t.onVariant))
                    }
                }
            }
        }
    }

    private func settingRow(_ symbol: String, _ title: String, _ subtitle: String?,
                            iconColor: Color, pad: Bool = false,
                            @ViewBuilder trailing: () -> AnyView) -> some View {
        HStack(spacing: 13) {
            RDSym(symbol, size: 22, color: iconColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(rdFont(14.5, .semibold)).foregroundStyle(t.onSurface)
                if let subtitle {
                    Text(subtitle).font(rdFont(12, .medium)).foregroundStyle(t.onVariant)
                }
            }
            Spacer()
            trailing()
        }
        .padding(pad ? 16 : 0)
        .contentShape(Rectangle())
    }
}

// =================================================================== SWITCH

struct RDSwitchScreen: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var loc: LocationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                RDCircleButton(symbol: "arrow.left", label: "Back", bordered: false, iconSize: 24, t: t) { m.back() }
                Text("Stops nearby").font(rdFont(21, .heavy)).foregroundStyle(t.onSurface)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)

            Button(action: { m.openSearch() }) {
                HStack(spacing: 11) {
                    RDSym("magnifyingglass", size: 22, color: t.onVariant)
                    Text("Search stops, buses, MRT").font(rdFont(15, .medium)).foregroundStyle(t.onVariant)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(t.scHigh).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    nearbyLabel("bus.fill", "BUS STOPS NEARBY")
                    ForEach(Array(m.otherStops.enumerated()), id: \.element.index) { idx, o in
                        if idx > 0 { rowDivider }
                        let next = o.stop.arrivals.first
                        row(iconBg: t.primaryContainer, iconColor: t.onPrimaryContainer, symbol: "bus.fill",
                            title: o.stop.name, code: nil, codeColor: nil,
                            subtitle: next != nil ? "\(o.stop.distShort) · next \(next!.route)" : o.stop.distShort,
                            value: next?.min ?? "—", unit: "min") { m.selectStop(o.index) }
                    }
                    if let here = loc.location {
                        let stations = MrtGeo.nearestStations(to: here.coordinate, limit: 4)
                        if !stations.isEmpty {
                            nearbyLabel("tram.fill", "MRT STATIONS NEARBY")
                            ForEach(Array(stations.enumerated()), id: \.element.station.id) { idx, item in
                                if idx > 0 { rowDivider }
                                let s = item.station
                                let code = s.codes.first ?? ""
                                row(iconBg: mrtLineColorFor(code), iconColor: rdMrtBadgeFg(code), symbol: "tram.fill",
                                    title: s.name, code: code, codeColor: mrtLineColorFor(code),
                                    subtitle: s.codes.joined(separator: " · "),
                                    value: "\(item.walkMin)", unit: "min walk") { m.openStation(named: s.name) }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(t.surface)
    }

    private func nearbyLabel(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            RDSym(symbol, size: 16, color: t.onVariant)
            Text(text).font(rdFont(11, .heavy)).foregroundStyle(t.onVariant).kerning(0.66)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
    }

    private var rowDivider: some View {
        Rectangle().fill(t.outlineVariant).frame(height: 1).padding(.leading, 72)
    }

    /// Flat grouped-list row (matches Home/Stop) — no filled card; the value on
    /// the right is neutral (blue is reserved for interactive controls).
    private func row(iconBg: Color, iconColor: Color, symbol: String, title: String,
                     code: String?, codeColor: Color?, subtitle: String,
                     value: String, unit: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                RDSym(symbol, size: 18, color: iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconBg).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(rdFont(15.5, .semibold)).foregroundStyle(t.onSurface).lineLimit(1)
                        if let code, let codeColor {
                            Text(code).font(rdFont(9, .heavy)).foregroundStyle(rdMrtBadgeFg(code))
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(codeColor).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    Text(subtitle).font(rdFont(12, .medium)).foregroundStyle(t.onVariant).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(rdFont(18, .heavy)).foregroundStyle(t.onSurface)
                    Text(unit).font(rdFont(10, .medium)).foregroundStyle(t.onVariant)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
