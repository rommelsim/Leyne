// SoftRoot — Leyne 2.0 root composition. Wraps Home / Nearby / Settings
// in a NavigationStack so child views (Stop / Bus / Search) push with
// UIKit's native slide-from-trailing animation + edge-swipe back
// gesture. AppModel.openCard observation drives notification /
// Spotlight deep-link pushes onto the stack.

import SwiftUI
import UIKit

/// SwiftUI's NavigationStack drops the interactive pop gesture when the
/// nav bar is hidden via `.toolbar(.hidden, …)`. Setting the gesture
/// recogniser's delegate to `nil` reinstates it. Apply once at the root
/// of each pushed destination.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController,
                                context: Context) {
        DispatchQueue.main.async {
            guard let nav = uiViewController.navigationController else { return }
            nav.interactivePopGestureRecognizer?.delegate = nil
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

private struct EnableSwipeBack: ViewModifier {
    func body(content: Content) -> some View {
        content.background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}

extension View {
    /// Re-enables the edge-swipe-from-left back gesture for SwiftUI
    /// NavigationStack views that hide their toolbar.
    func enableSwipeBack() -> some View { modifier(EnableSwipeBack()) }
}

/// Toolbar chrome for a tab's root: either hidden (custom in-content header) or
/// left visible so the root can host a native `.searchable` bar (which must live
/// in a navigation bar). When visible, the screen sets its own navigation title.
private struct RootBarChrome: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if hidden {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

enum SoftRoute: Hashable {
    case stop(String)
    /// `fullRoute` is true when opened from a bus search (no anchor stop
    /// context), so the route timeline shows the whole route from origin.
    case bus(stopCode: String, svc: String, fullRoute: Bool = false)
    case search
}

/// Navigation destinations within the MRT tab's NavigationStack.
enum SoftMrtRoute: Hashable {
    /// Push the station detail for a tapped nearby/search station.
    /// `distanceM` and `walkMin` are optional (nil when navigating from Search).
    case station(MrtGeoStation, distanceM: Int? = nil, walkMin: Int? = nil)
    /// Push the per-line crowd + status detail view.
    case line(MRTLine)
    /// Push the News & advisories view.
    case news
}

struct SoftRoot: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @State private var tab: SoftTab = .home
    // One navigation stack per tab so a drill-down in Home doesn't follow
    // the user over to MRT or Saved. The native TabView preserves each
    // path across tab switches, matching iOS's standard tab behaviour.
    // Search is no longer a tab — the Home/Saved search bar raises it as a
    // card (the `showSearch` sheet). Alerts is no longer a tab either — it's
    // presented as a sheet from the Home bell.
    @State private var homeStack: [SoftRoute] = []
    @State private var mrtStack: [SoftMrtRoute] = []
    @State private var favouritesStack: [SoftRoute] = []
    @State private var showAlerts = false
    @State private var showSearch = false
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    /// The native 3-tab bar (Bus · MRT · Saved) — only true places/modes. Search
    /// is a field at the top of Home that raises a search card; Alerts is a bell
    /// on Home that raises a sheet. Each tab owns its own NavigationStack so
    /// child pushes keep the native slide + swipe-back.
    private var tabView: some View {
        TabView(selection: $tab) {
            // 1. Bus — nearby bus stops home screen + native search bar + bell
            Tab("Bus", systemImage: "bus.fill", value: SoftTab.home) {
                // Home hosts the native `.searchable` bar, which lives in the
                // navigation bar — so unlike the other tabs it must NOT hide it.
                navStack($homeStack, hidesNavBar: false) {
                    SoftHomeView(
                        onTab: { tab = $0 },
                        onOpenStop: { homeStack.append(.stop($0)) },
                        onOpenBus: { code, svc in
                            homeStack.append(.bus(stopCode: code, svc: svc,
                                                  fullRoute: true))
                        },
                        onOpenMrtStation: { station in navigateToStation(station) },
                        onOpenAlerts: { showAlerts = true }
                    )
                }
            }
            // 2. MRT — station map + live crowd / service alerts
            Tab("MRT", systemImage: "tram.fill", value: SoftTab.mrt) {
                mrtNavStack($mrtStack)
            }
            // 3. Saved — pinned stops and favourite services
            Tab("Saved", systemImage: "star.fill", value: SoftTab.favourites) {
                navStack($favouritesStack) {
                    SoftFavouritesView(
                        onOpenStop: { favouritesStack.append(.stop($0)) },
                        onOpenBus: { code, svc in
                            favouritesStack.append(.bus(stopCode: code, svc: svc))
                        },
                        onOpenSearch: { showSearch = true },
                        onOpenMrtStation: { station in
                            // Switch to the MRT tab and push the station detail.
                            tab = .mrt
                            mrtStack = [.station(station)]
                        }
                    )
                }
            }
        }
        .tint(t.meBlue)
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            tabView
                // Alerts is now a sheet raised from the Home bell. Opening it
                // clears the unseen badge (the red dot on the bell).
                .sheet(isPresented: $showAlerts) {
                    NavigationStack {
                        SoftAlertsView()
                    }
                    // Opens as a half card; drag up for the rest.
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(m)
                    .environmentObject(fb)
                }
                .onChange(of: showAlerts) { _, open in
                    if open { m.markAllAlertsSeen() }
                }
                // Search raised as a card from the Home/Saved search bar. The
                // bar is just the launcher, so only one search field is ever
                // visible. Result taps dismiss the card and route into the Bus
                // tab (or MRT for a station).
                .sheet(isPresented: $showSearch) {
                    SoftSearchView(
                        compact: true,
                        onClose: { showSearch = false },
                        onOpenStop: { code in
                            tab = .home
                            homeStack.append(.stop(code))
                            showSearch = false
                        },
                        onOpenBus: { stopCode, svcNo in
                            tab = .home
                            homeStack.append(.bus(stopCode: stopCode,
                                                  svc: svcNo, fullRoute: true))
                            showSearch = false
                        },
                        onOpenMrtStation: { station in
                            showSearch = false
                            navigateToStation(station)
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(m)
                    .environmentObject(fb)
                    .environmentObject(DataStore.shared)
                }

            // Map handoff toast overlays the whole stack.
            VStack {
                MapHandoffToast(t: t, kind: $mapHandoff)
                    .padding(.top, 8)
                Spacer()
            }
            .zIndex(100)
            .allowsHitTesting(mapHandoff != .none)
        }
        // Interstitial ad: each tab owns its own NavigationStack, so a Stop/Bus
        // exit shows up as that tab's path shrinking. Observing the paths
        // (rather than each onBack button) means the back button, the system
        // back, AND the edge-swipe-back gesture all trigger the attempt — they
        // all pop the bound path. The manager's guards decide whether one shows.
        .onChange(of: homeStack) { old, new in handleStackPop(old, new) }
        .onChange(of: favouritesStack) { old, new in handleStackPop(old, new) }
        // Notification / Spotlight / Live Activity deep links arrive via
        // AppModel.openCard. Route them into the Home tab's stack, then clear so
        // the same trigger fires the next tap. `initial: true` is essential for
        // COLD launches (tapping a Live Activity from a suspended/killed app):
        // onOpenURL sets openCard before this observer attaches, so without the
        // initial pass the deep link is silently dropped and nothing navigates.
        .onChange(of: m.openCard, initial: true) { _, card in
            guard let c = card else { return }
            // This replaces the Home stack programmatically — tell the
            // interstitial manager so the resulting shrink isn't read as a
            // user back-exit (they tapped a notification, not "back").
            InterstitialAdManager.shared.suppressNextExit()
            tab = .home
            if let svc = c.initialSelectedNo, !svc.isEmpty {
                homeStack = [.stop(c.stopCode), .bus(stopCode: c.stopCode, svc: svc)]
            } else {
                homeStack = [.stop(c.stopCode)]
            }
            m.openCard = nil
        }
    }

    /// Fires an interstitial attempt when a tab's nav path shrinks and the
    /// removed top was a Stop or Bus detail — i.e. the user backed out of a
    /// detail view. Growing paths (drill-in, deep-link) and tab switches are
    /// ignored. The manager's own guards (caps, gates, deep-link suppression)
    /// decide whether an ad actually shows.
    private func handleStackPop(_ old: [SoftRoute], _ new: [SoftRoute]) {
        guard new.count < old.count, let removed = old.last else { return }
        switch removed {
        case .stop, .bus:
            InterstitialAdManager.shared.maybeShowOnExit(model: m)
        case .search:
            break
        }
    }

    /// Wraps a tab's root in a NavigationStack bound to that tab's path,
    /// registering the shared route destinations. The ad-banner gutter is
    /// applied to the root *and* every pushed detail view, so the banner
    /// stays visible on Stop / Bus pages too. Each mount point owns its own
    /// banner host (see `BannerAdView`); the host's `window != nil` gate
    /// means only the on-screen view ever requests an ad, so the extra
    /// gutters stay AdMob-policy-clean.
    @ViewBuilder
    private func navStack<Root: View>(_ path: Binding<[SoftRoute]>,
                                      hidesNavBar: Bool = true,
                                      @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .adBannerGutter()
                .softTopEdgeBlur()
                // Most roots hide the nav bar (custom in-content headers). Home
                // keeps it so it can host the native `.searchable` field; an
                // empty inline title keeps that bar a thin strip above the bar.
                .modifier(RootBarChrome(hidden: hidesNavBar))
                .navigationDestination(for: SoftRoute.self) { route in
                    routeDestination(route, path: path)
                }
        }
    }

    /// A pushed destination with the standard chrome. The bottom ad-banner
    /// gutter is applied to every destination EXCEPT `.stop`, which carries its
    /// own inline 300×250 MREC instead — mounting both would double up ads on
    /// one screen.
    @ViewBuilder
    private func routeDestination(_ route: SoftRoute,
                                  path: Binding<[SoftRoute]>) -> some View {
        let content = routeView(route, path: path)
            .softTopEdgeBlur()
            .toolbar(.hidden, for: .navigationBar)
            // Each detail draws its own back chevron. Now that the Home root
            // shows a nav bar (to host the search field), SwiftUI would also
            // inject a system back button on push — hide it so there's only one.
            .navigationBarBackButtonHidden(true)
            // Tab bar stays visible on pushed Stop / Bus detail pages so the
            // user can switch tabs without backing out.
            .enableSwipeBack()
        switch route {
        case .stop:
            content
        default:
            content.adBannerGutter()
        }
    }

    @ViewBuilder
    private func routeView(_ route: SoftRoute,
                           path: Binding<[SoftRoute]>) -> some View {
        let pop = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        switch route {
        case .stop(let code):
            SoftStopView(stopCode: code,
                         onBack: pop,
                         onOpenBus: { svc in path.wrappedValue.append(.bus(stopCode: code, svc: svc)) })
        case .bus(let code, let svc, let fullRoute):
            SoftBusView(stopCode: code, svc: svc, fullRoute: fullRoute, onBack: pop)
        case .search:
            // Legacy route — Search is now a first-class tab. Kept so any
            // stale path still resolves; route taps into the same stack.
            SoftSearchView(
                onClose: pop,
                // Append on top of search (don't pop it first) so Back returns
                // to the results, then Back again leaves search — matching the
                // first-class search tab's behavior.
                onOpenStop: { code in
                    path.wrappedValue.append(.stop(code))
                },
                onOpenBus: { stopCode, svcNo in
                    path.wrappedValue.append(.bus(stopCode: stopCode,
                                                   svc: svcNo,
                                                   fullRoute: true))
                },
                onOpenMrtStation: { station in
                    navigateToStation(station)
                }
            )
        }
    }

    // MARK: - MRT navigation stack

    /// Dedicated NavigationStack for the MRT tab. Pushes SoftMrtStationView for
    /// station taps originating from the nearest list or from Search. The station
    /// view needs its own `onBack` closure because the toolbar is hidden and the
    /// system back button isn't visible — the SwipeBackEnabler reinstates the
    /// edge-swipe gesture, but an in-view back button is also provided.
    @ViewBuilder
    private func mrtNavStack(_ path: Binding<[SoftMrtRoute]>) -> some View {
        let pop = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        NavigationStack(path: path) {
            SoftMrtView(
                onOpenLine: { line in path.wrappedValue.append(.line(line)) },
                onOpenNews: { path.wrappedValue.append(.news) },
                // Stop / bus results from MRT's search bar route to the Bus tab.
                onOpenStop: { code in
                    tab = .home
                    homeStack.append(.stop(code))
                },
                onOpenBus: { code, svc in
                    tab = .home
                    homeStack.append(.bus(stopCode: code, svc: svc, fullRoute: true))
                }
            )
            .adBannerGutter()
            .softTopEdgeBlur()
            // MRT's nav bar stays visible (not hidden) so it can host the native
            // `.searchable` field; SoftMrtView sets its own "MRT" title.
            .navigationDestination(for: SoftMrtRoute.self) { route in
                Group {
                    switch route {
                    case .station(let station, let distM, let walkM):
                        SoftMrtStationView(
                            station: station,
                            distanceM: distM,
                            walkMin: walkM,
                            onBack: pop
                        )
                        .adBannerGutter()
                        .softTopEdgeBlur()
                    case .line(let line):
                        SoftMrtLineView(line: line, onBack: pop)
                            .adBannerGutter()
                            .softTopEdgeBlur()
                    case .news:
                        SoftMrtNewsView(onBack: pop)
                            .adBannerGutter()
                            .softTopEdgeBlur()
                    }
                }
                // Each detail draws its own back button; the MRT root now shows
                // a nav bar (for search), so suppress the injected system one.
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden(true)
                .enableSwipeBack()
            }
        }
    }

    /// Navigates the Search tab's stack to an MRT station detail. The search
    /// tab reuses the standard `SoftRoute` stack, so we push `.mrtStation`
    /// using the shared `mrtStack` from the MRT tab — then switch to MRT.
    /// This is the cleanest approach without adding mrtStation to SoftRoute
    /// (which would require handling it in all other navStacks' routeView).
    func navigateToStation(_ station: MrtGeoStation, distanceM: Int? = nil, walkMin: Int? = nil) {
        tab = .mrt
        mrtStack = [.station(station, distanceM: distanceM, walkMin: walkMin)]
    }
}
