// WhereSia — root shell.
//
// A 4-tab bar (Home · Saved · Alerts · Me) over per-tab NavigationStacks that
// push the detail screens (Bus stop, MRT station, Service info, Track bus).
// Search presents as a sheet over the Home tab. Wired to the existing live
// data (DataStore / AppModel / LocationManager) — WhereSia is a pure design
// layer.

import SwiftUI

// MARK: - Navigation

enum WSTab: String, CaseIterable { case home, saved, alerts, me }

/// Push destinations, shared across every tab's NavigationStack.
enum WSRoute: Hashable {
    case busStop(code: String)
    case mrtStation(MrtGeoStation)
    case serviceInfo(no: String, fromStop: String?)
    case trackBus(stopCode: String, no: String)
}

/// Environment-injected "push a route onto the current tab's stack".
private struct WSPushKey: EnvironmentKey {
    static let defaultValue: (WSRoute) -> Void = { _ in }
}
extension EnvironmentValues {
    var wsPush: (WSRoute) -> Void {
        get { self[WSPushKey.self] }
        set { self[WSPushKey.self] = newValue }
    }
}

// MARK: - Root

struct WSRoot: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @EnvironmentObject private var location: LocationManager

    @State private var tab: WSTab = .home
    @State private var homePath: [WSRoute] = []
    @State private var savedPath: [WSRoute] = []
    @State private var alertsPath: [WSRoute] = []
    @State private var mePath: [WSRoute] = []
    @State private var showSearch = false

    private var ws: WSTheme { .resolve(dark: m.isDark) }

    var body: some View {
        Group {
            switch tab {
            case .home:   stack($homePath) { WSHomeView(onSearch: { showSearch = true }) }
            case .saved:  stack($savedPath) { WSSavedView() }
            case .alerts: stack($alertsPath) { WSAlertsView() }
            case .me:     stack($mePath) { WSMeView() }
            }
        }
        .background(ws.bg.ignoresSafeArea())
        // Floating glass tab bar as a bottom safe-area inset, not a manual
        // ZStack overlay with a fixed content padding: scroll content can
        // now reach — and show through — the material at the bottom of a
        // list, matching the native iOS 26 floating-bar composition.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WSTabBar(tab: $tab, alertCount: m.unseenAlertCount)
        }
        .environment(\.ws, ws)
        .sheet(isPresented: $showSearch) {
            WSSearchView(onSelect: { route in
                showSearch = false
                tab = .home
                homePath.append(route)
            }, onClose: { showSearch = false })
            .environment(\.ws, ws)
            .environment(m)
            .environment(store)
            .environmentObject(location)
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
        // Deep links (notification / widget / Spotlight) surface as m.openCard.
        .onChange(of: m.openCard, initial: true) { _, card in
            guard let card else { return }
            tab = .home
            var routes: [WSRoute] = [.busStop(code: card.stopCode)]
            if let no = card.initialSelectedNo {
                routes.append(.trackBus(stopCode: card.stopCode, no: no))
            }
            homePath = routes
            m.openCard = nil
        }
        .onChange(of: tab) { _, new in
            if new == .alerts { m.markAllAlertsSeen() }
        }
    }

    /// Wraps a tab root in a NavigationStack bound to that tab's path, with the
    /// shared destination table and a `wsPush` closure that appends to it.
    @ViewBuilder
    private func stack<Root: View>(_ path: Binding<[WSRoute]>,
                                   @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: WSRoute.self) { route in
                    // Pushed screens supply their own `.wsHeaderBar` toolbar
                    // (real system nav-bar chrome — Liquid Glass on iOS 26,
                    // translucent material below), so unlike the tab roots
                    // above the nav bar stays visible here. That also
                    // restores the interactive edge-swipe-back gesture for
                    // free: hiding the back *button* doesn't kill it, only
                    // hiding the whole nav bar (the old approach) did — this
                    // replaces the `enableSwipeBack()` workaround entirely.
                    destination(route, path: path)
                }
        }
        .environment(\.wsPush) { route in path.wrappedValue.append(route) }
    }

    @ViewBuilder
    private func destination(_ route: WSRoute, path: Binding<[WSRoute]>) -> some View {
        let back = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        switch route {
        case .busStop(let code):
            WSBusStopView(code: code, onBack: back)
        case .mrtStation(let station):
            WSMrtStationView(station: station, onBack: back)
        case .serviceInfo(let no, let fromStop):
            WSServiceInfoView(serviceNo: no, fromStop: fromStop, onBack: back)
        case .trackBus(let stopCode, let no):
            WSTrackBusView(stopCode: stopCode, serviceNo: no, onBack: back)
        }
    }
}

// MARK: - Tab bar (floating Liquid Glass)

struct WSTabBar: View {
    @Binding var tab: WSTab
    var alertCount: Int
    @Environment(\.ws) private var ws

    var body: some View {
        HStack(spacing: 2) {
            item(.home, "Home", .home)
            item(.saved, "Saved", .saved)
            item(.alerts, "Alerts", .alerts, badge: alertCount)
            item(.me, "Me", .me)
        }
        .padding(.horizontal, 8)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .wsGlassChrome(cornerRadius: 26, tint: ws.tabbar)
        .shadow(color: .black.opacity(ws.isDark ? 0.35 : 0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        // One selection tick per tab change, regardless of which item fired it.
        .sensoryFeedback(.selection, trigger: tab)
    }

    @ViewBuilder
    private func item(_ t: WSTab, _ label: String, _ glyph: WSGlyph, badge: Int = 0) -> some View {
        let on = tab == t
        Button {
            tab = t
        } label: {
            VStack(spacing: 5) {
                WSIcon(glyph: glyph, size: 22, weight: on ? .regular : .light,
                       color: on ? ws.text : ws.dim)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Circle().fill(ws.text).frame(width: 7, height: 7).offset(x: 5, y: -2)
                        }
                    }
                Text(label)
                    .font(ws.sans(10, weight: .bold))
                    .foregroundStyle(on ? ws.text : ws.dim)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)   // ≥44pt tap target even though the glyph+label are smaller
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
