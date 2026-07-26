// WhereSia — root shell.
//
// A 4-tab bar (Home · Saved · Alerts · Me) over per-tab NavigationStacks that
// push the detail screens (Bus stop, MRT station, Service info, Track bus).
// Search presents as a sheet over the Home tab. Wired to the existing live
// data (DataStore / AppModel / LocationManager) — WhereSia is a pure design
// layer.

import SwiftUI

// MARK: - Navigation

// No "Me" tab: it held only a decorative profile and settings iOS already
// owns (notifications permission is requested on first alert; appearance
// follows the system). Owner call, 2026-07-02.
enum WSTab: String, CaseIterable { case home, saved, alerts }

/// Push destinations, shared across every tab's NavigationStack.
enum WSRoute: Hashable {
    case busStop(code: String, service: String?)
    case mrtStation(MrtGeoStation)
    case serviceInfo(no: String, fromStop: String?)
    case map
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
    @State private var showSearch = false

    // Follow the system appearance directly — the in-app Appearance picker
    // left with the Me tab, and m.isDark would pin users to a stale choice.
    @Environment(\.colorScheme) private var colorScheme
    private var ws: WSTheme { .resolve(dark: colorScheme == .dark) }

    var body: some View {
        // THE SYSTEM TAB BAR (owner 2026-07-25, third ask — "use native iOS
        // for the toolbar"). The hand-drawn floating white pill is gone: a
        // real `TabView` gets Liquid Glass on iOS 26, the system's own
        // selection/scroll-edge behaviour, badges, minimise-on-scroll,
        // Dynamic Type and VoiceOver rotor for free.
        //
        // It also FIXES the "can't scroll down to the MRT stations" bug: the
        // custom bar was a `safeAreaInset` applied OUTSIDE each tab's
        // NavigationStack, so the scroll views inside never got the inset and
        // their last rows sat under the floating pill. A TabView insets its
        // content itself.
        TabView(selection: $tab) {
            // `.wsTabEntrance()` per tab: the system swaps tab content with no
            // transition at all, which read as a motionless cut (owner
            // 2026-07-25). Each tab now fades + rises on arrival, in the same
            // drift the rest of the app enters with. Reduce Motion skips it.
            Tab("Nearby", systemImage: "location.fill", value: WSTab.home) {
                stack($homePath) { WSHomeView(onSearch: { showSearch = true }) }
                    .wsTabEntrance()
            }
            Tab("Favourites", systemImage: "star.fill", value: WSTab.saved) {
                stack($savedPath) { WSSavedView() }
                    .wsTabEntrance()
            }
            Tab("Alerts", systemImage: "bell.fill", value: WSTab.alerts) {
                stack($alertsPath) { WSAlertsView() }
                    .wsTabEntrance()
            }
            .badge(m.unseenAlertCount)
        }
        .tint(SoftBlue.blue)
        // The TabView's own container background is the system's (white in
        // light mode) and sits ABOVE RootView's ground, so any frame where a
        // tab isn't painting its own background revealed white. Tint the
        // container itself — belt and braces with WSTabEntrance's ground.
        .background(SoftBlue.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: tab)
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
            // Soft-blue 4b: tinted ground instead of dark glass — matches
            // the search view's white-card content.
            .presentationBackground(SoftBlue.bg)
        }
        // Deep links (notification / widget / Spotlight) surface as m.openCard.
        .onChange(of: m.openCard, initial: true) { _, card in
            guard let card else { return }
            tab = .home
            // Notification / widget taps land on the Stop view with the
            // tapped service pinned as the hero (Track Bus screen retired).
            homePath = [.busStop(code: card.stopCode, service: card.initialSelectedNo)]
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
                // Root tabs now draw a REAL nav bar (large title + system
                // toolbar buttons) instead of a hand-built header row with
                // custom white tiles — owner 2026-07-25. Each root view
                // supplies its own `.navigationTitle` / `.toolbar`.
                // Exit interstitial hook. It used to hang off each screen's
                // custom back button; the Stop view's back button is the
                // SYSTEM one now (owner 2026-07-25), so the trigger moved to
                // the pop itself — a back-out of a dwell screen (stop /
                // station) is the app's natural break. The manager owns every
                // guard (frequency cap, exit count, cross-format gap,
                // deep-link suppression), so firing on every qualifying pop is
                // safe. Map and Service Info stay hook-free: short-dwell,
                // task-critical surfaces.
                .onChange(of: path.wrappedValue) { old, new in
                    guard new.count < old.count, let left = old.last else { return }
                    switch left {
                    case .busStop, .mrtStation:
                        InterstitialAdManager.shared.maybeShowOnExit(model: m)
                    case .serviceInfo, .map:
                        break
                    }
                }
                .navigationDestination(for: WSRoute.self) { route in
                    // Pushed screens supply their own `.wsHeaderBar` toolbar
                    // (real system nav-bar chrome — Liquid Glass on iOS 26,
                    // translucent material below), so unlike the tab roots
                    // above the nav bar stays visible here. NOTE: hiding the
                    // system back button still disables the edge-swipe pop
                    // gesture, so `wsHeaderBar` applies `enableSwipeBack()`.
                    destination(route, path: path)
                }
        }
        .environment(\.wsPush) { route in path.wrappedValue.append(route) }
    }

    @ViewBuilder
    private func destination(_ route: WSRoute, path: Binding<[WSRoute]>) -> some View {
        let back = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        // Detail screens are focused tasks with their own chrome (and their
        // own pinned CTAs / ad banners), so the tab bar goes away on push —
        // the same `hidesBottomBarWhenPushed` behaviour UIKit apps have.
        Group {
            switch route {
            case .busStop(let code, let service):
                WSBusStopView(code: code, initialService: service)
            case .mrtStation(let station):
                WSMrtStationView(station: station, onBack: back)
            case .serviceInfo(let no, let fromStop):
                WSServiceInfoView(serviceNo: no, fromStop: fromStop, onBack: back)
            case .map:
                WSMapView()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

// The hand-drawn `WSTabBar` floating pill was DELETED 2026-07-25 (owner:
// "the toolbar should be iOS native"). Its replacement is the system TabView
// in `WSRoot.body` — don't reintroduce a custom bar here.
