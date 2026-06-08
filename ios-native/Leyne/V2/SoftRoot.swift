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

struct SoftRoot: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @State private var tab: SoftTab = .home
    // One navigation stack per tab so a drill-down in Home doesn't follow
    // the user over to Nearby or Search. The native TabView preserves each
    // path across tab switches, matching iOS's standard tab behaviour.
    @State private var homeStack: [SoftRoute] = []
    @State private var favouritesStack: [SoftRoute] = []
    @State private var settingsStack: [SoftRoute] = []
    @State private var searchStack: [SoftRoute] = []
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            // Native TabView with four inline labelled tabs — Home ·
            // Favourites · Settings · Search — matching the 2.4.0 mockup's
            // standard bottom bar. Search is a normal tab (not the detached
            // `.search` role circle) so it reads as the fourth labelled item.
            // Each tab owns a NavigationStack so child pushes (Stop / Bus)
            // keep the native slide + edge-swipe-back. Selection tint is the
            // location blue used across the redesign.
            TabView(selection: $tab) {
                Tab("Nearby", systemImage: "location.fill", value: SoftTab.home) {
                    navStack($homeStack) {
                        SoftHomeView(
                            onTab: { tab = $0 },
                            onOpenStop: { homeStack.append(.stop($0)) },
                            onOpenSearch: { tab = .search }
                        )
                    }
                }
                Tab("Saved", systemImage: "star.fill", value: SoftTab.favourites) {
                    navStack($favouritesStack) {
                        SoftFavouritesView(
                            onOpenStop: { favouritesStack.append(.stop($0)) },
                            onOpenBus: { code, svc in
                                favouritesStack.append(.bus(stopCode: code, svc: svc))
                            },
                            onOpenSearch: { tab = .search }
                        )
                    }
                }
                Tab("Search", systemImage: "magnifyingglass", value: SoftTab.search) {
                    navStack($searchStack) {
                        SoftSearchView(
                            onClose: { tab = .home },
                            onOpenStop: { searchStack.append(.stop($0)) },
                            onOpenBus: { stopCode, svcNo in
                                searchStack.append(.bus(stopCode: stopCode,
                                                        svc: svcNo,
                                                        fullRoute: true))
                            }
                        )
                    }
                }
                Tab("Settings", systemImage: "gearshape.fill", value: SoftTab.settings) {
                    navStack($settingsStack) {
                        SoftSettingsView(onTab: { tab = $0 })
                    }
                }
            }
            .tint(t.meBlue)

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
        .onChange(of: settingsStack) { old, new in handleStackPop(old, new) }
        // Notification / Spotlight deep links arrive via AppModel.openCard.
        // Route them into the Home tab's stack, then clear so the same
        // trigger fires the next tap.
        .onChange(of: m.openCard) { _, card in
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
                }
            )
        }
    }
}
