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
    @ObservedObject private var ds = DataStore.shared

    @State private var tab: SoftTab = .home
    // One navigation stack per tab so a drill-down in Home doesn't follow
    // the user over to Nearby or Search. The native TabView preserves each
    // path across tab switches, matching iOS's standard tab behaviour.
    @State private var homeStack: [SoftRoute] = []
    @State private var mrtStack: [SoftMrtRoute] = []
    @State private var favouritesStack: [SoftRoute] = []
    @State private var alertsStack: [SoftRoute] = []
    @State private var searchStack: [SoftRoute] = []
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    /// The native 5-tab bar (Bus · MRT · Saved · Search · Alerts). Each tab owns
    /// its own NavigationStack so child pushes keep the native slide + swipe-back.
    /// Extracted from `body` to keep the view-builder type-check tractable.
    private var tabView: some View {
        TabView(selection: $tab) {
            // 1. Bus — nearby bus stops home screen
            Tab("Bus", systemImage: "bus.fill", value: SoftTab.home) {
                navStack($homeStack) {
                    SoftHomeView(
                        onTab: { tab = $0 },
                        onOpenStop: { homeStack.append(.stop($0)) },
                        onOpenSearch: { tab = .search },
                        // DepartureCard taps push directly to the bus detail.
                        // The stop isn't pushed first — the back chevron on the
                        // bus view returns to Home, which is the right mental model
                        // when launching from the board.
                        onOpenBus: { stopCode, svc in
                            homeStack.append(.bus(stopCode: stopCode, svc: svc))
                        }
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
                        onOpenSearch: { tab = .search },
                        onOpenMrtStation: { station in
                            // Switch to the MRT tab and push the station detail.
                            tab = .mrt
                            mrtStack = [.station(station)]
                        }
                    )
                }
            }
            // 4. Search
            Tab("Search", systemImage: "magnifyingglass", value: SoftTab.search) {
                navStack($searchStack) {
                    SoftSearchView(
                        onClose: { tab = .home },
                        onOpenStop: { searchStack.append(.stop($0)) },
                        onOpenBus: { stopCode, svcNo in
                            searchStack.append(.bus(stopCode: stopCode,
                                                    svc: svcNo,
                                                    fullRoute: true))
                        },
                        onOpenMrtStation: { station in
                            navigateToStation(station)
                        }
                    )
                }
            }
            // 5. Alerts — service status (disruptions / maintenance / advisories)
            //    + personal bus alerts; gear → Settings sheet.
            Tab("Alerts", systemImage: "bell.fill", value: SoftTab.alerts) {
                navStack($alertsStack) {
                    SoftAlertsView()
                }
            }
            .badge(m.unseenAlertCount)
        }
        .tint(t.meBlue)
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            tabView
                // Alerts-tab badge: mark seen when the user is on (or switches
                // to) the Alerts tab, including when fresh disruptions/maintenance
                // land while it's open. Otherwise the badge counts the unseen.
                .onChange(of: tab) { _, newTab in
                    if newTab == .alerts { m.markAllAlertsSeen() }
                }
                .onChange(of: ds.trainAlerts) { _, _ in
                    if tab == .alerts { m.markAllAlertsSeen() }
                }
                .onChange(of: ds.liftMaintenance) { _, _ in
                    if tab == .alerts { m.markAllAlertsSeen() }
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
        .onChange(of: searchStack) { old, new in handleStackPop(old, new) }
        .onChange(of: alertsStack) { old, new in handleStackPop(old, new) }
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
                                      @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .adBannerGutter()
                .softTopEdgeBlur()
                .toolbar(.hidden, for: .navigationBar)
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
                onOpenNews: { path.wrappedValue.append(.news) }
            )
            .adBannerGutter()
            .softTopEdgeBlur()
            .navigationDestination(for: SoftMrtRoute.self) { route in
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
