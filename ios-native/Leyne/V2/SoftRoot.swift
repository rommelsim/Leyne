// SoftRoot — Leyne 2.0 root composition (Phase 5 IA).
//
// Phase 5 IA: 2-tab bar (Now · Rail) + sheet-based Search, Saved, Alerts,
// Settings — matching the prototype's navbar model (TABS = [{now},{rail}]).
//
// What's where:
//   Now tab     — SoftHomeView (departures board, pinned stops, DepartureCards)
//                 Header: search bar → SoftSearchView sheet
//                         bell button → alerts sheet (personal + service status)
//                         gear button → SoftSettingsView sheet
//   Rail tab    — SoftMrtView (line overview + saved MRT stations)
//                 Header: gear button → SoftSettingsView sheet
//   Search      — SoftSearchView presented as .fullScreenCover from Now/Rail
//                 header search bar, NOT a tab. Rewired from "switch to Search
//                 tab" to "present sheet".
//   Saved       — SoftFavouritesView presented as .sheet from a "Saved" button
//                 in the Now header (or accessible from Rail header).
//                 Favourite services + saved MRT stations are all reachable here.
//   Alerts      — SoftAlertsView presented as .sheet from the bell in Now/Rail
//                 header (maintains service status + personal bus alerts + badge).
//   Settings    — SoftSettingsView presented as .sheet from the gear in Now/Rail
//                 header (already worked this way from Alerts tab; now primary
//                 entry point).
//
// Deep links + Live Activity: unchanged. m.openCard routes to Now tab's stack
// (homeStack / mrtStack) exactly as before. Tab switching is still possible via
// the SoftTab enum for the two remaining tabs; removed tabs' cases remain in the
// enum (SoftTabBar.swift) to avoid breaking any lingering references.
//
// SwipeBackEnabler: preserved on every pushed destination.

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

// MARK: - Route enums (unchanged from Phase 1–4)

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

// MARK: - SoftRoot

struct SoftRoot: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @ObservedObject private var ds = DataStore.shared

    // The two remaining persistent tabs.
    @State private var tab: SoftTab = .home

    // Per-tab navigation stacks.
    @State private var homeStack: [SoftRoute] = []
    @State private var mrtStack: [SoftMrtRoute] = []

    // Sheet presentation state — replaces the removed tabs.
    @State private var showSearch = false
    @State private var showSaved = false
    @State private var showAlerts = false
    @State private var showSettings = false

    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            tabView
                .onChange(of: ds.trainAlerts) { _, _ in
                    // Alerts are contextual — no tab badge needed after Phase 5.
                    // Mark seen when the alerts sheet is open (handled in sheet onChange).
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
        // Interstitial ad: fires on any back-pop from Stop or Bus detail.
        .onChange(of: homeStack) { old, new in handleStackPop(old, new) }
        // Notification / Spotlight / Live Activity deep links arrive via
        // AppModel.openCard. Route them into the Home tab's stack.
        // `initial: true` catches COLD launches (tapping a Live Activity from a
        // suspended/killed app) where openCard is set before this observer attaches.
        .onChange(of: m.openCard, initial: true) { _, card in
            guard let c = card else { return }
            // Tell the interstitial manager so the resulting shrink isn't read
            // as a user back-exit (they tapped a notification, not "back").
            InterstitialAdManager.shared.suppressNextExit()
            tab = .home
            if let svc = c.initialSelectedNo, !svc.isEmpty {
                homeStack = [.stop(c.stopCode), .bus(stopCode: c.stopCode, svc: svc)]
            } else {
                homeStack = [.stop(c.stopCode)]
            }
            m.openCard = nil
        }
        // ── Sheet: Search ─────────────────────────────────────────────────
        .fullScreenCover(isPresented: $showSearch) {
            searchSheet
        }
        // ── Sheet: Saved (Favourites) ─────────────────────────────────────
        // Presented as a large detent sheet — swipe-down to dismiss.
        // SoftFavouritesView needs nav callbacks:
        //   • onOpenStop   → dismiss sheet + push Stop onto homeStack
        //   • onOpenBus    → dismiss sheet + push Bus onto homeStack
        //   • onOpenSearch → dismiss Saved sheet + show Search sheet
        //   • onOpenMrtStation → dismiss Saved + switch to MRT tab + push station
        .sheet(isPresented: $showSaved) {
            savedSheet
        }
        // ── Sheet: Alerts ─────────────────────────────────────────────────
        .sheet(isPresented: $showAlerts) {
            alertsSheet
                .onAppear { m.markAllAlertsSeen() }
                .onChange(of: ds.trainAlerts) { _, _ in m.markAllAlertsSeen() }
                .onChange(of: ds.liftMaintenance) { _, _ in m.markAllAlertsSeen() }
        }
        // ── Sheet: Settings ───────────────────────────────────────────────
        .sheet(isPresented: $showSettings) {
            SoftSettingsView(onTab: { _ in })
                .environmentObject(m)
                .environmentObject(fb)
        }
    }

    // MARK: - Tab view (2 tabs)

    /// The native 2-tab bar (Now · Rail). Each tab owns its own NavigationStack.
    private var tabView: some View {
        TabView(selection: $tab) {
            // 1. Buses — bus departures board (+ pushed bus/stop detail).
            // Labelled "Buses" (not "Now") so the tab's purpose reads clearly
            // against the "Rail" tab, and a pushed bus detail no longer sits
            // under a vague "Now" label.
            Tab("Buses", systemImage: "bus.fill", value: SoftTab.home) {
                navStack($homeStack) {
                    SoftHomeView(
                        onTab: { tab = $0 },
                        onOpenStop: { homeStack.append(.stop($0)) },
                        onOpenSearch: { showSearch = true },
                        onOpenBus: { stopCode, svc in
                            homeStack.append(.bus(stopCode: stopCode, svc: svc))
                        },
                        // Phase 5: wire the search-bar trailing controls to sheets.
                        onOpenSaved: { showSaved = true },
                        onOpenAlerts: { showAlerts = true },
                        onOpenSettings: { showSettings = true }
                    )
                }
            }

            // 2. Rail — MRT overview + saved stations
            Tab("Rail", systemImage: "tram.fill", value: SoftTab.mrt) {
                mrtNavStack($mrtStack)
            }
        }
        .tint(t.brand)
        // Unseen-alert badge on the bell in the header, not a tab badge —
        // the tab itself carries no badge in the 2-tab model.
    }

    // MARK: - navStack helper

    /// Wraps a tab's root in a NavigationStack with shared route destinations.
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

    // MARK: - Route destinations

    @ViewBuilder
    private func routeDestination(_ route: SoftRoute,
                                  path: Binding<[SoftRoute]>) -> some View {
        let content = routeView(route, path: path)
            .softTopEdgeBlur()
            .toolbar(.hidden, for: .navigationBar)
            .enableSwipeBack()
        switch route {
        case .stop:
            // Stop view carries its own inline MREC ad — don't double-stack the banner.
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
            // Legacy route kept so stale paths still resolve.
            SoftSearchView(
                onClose: pop,
                onOpenStop: { code in path.wrappedValue.append(.stop(code)) },
                onOpenBus: { stopCode, svcNo in
                    path.wrappedValue.append(.bus(stopCode: stopCode, svc: svcNo, fullRoute: true))
                },
                onOpenMrtStation: { station in navigateToStation(station) }
            )
        }
    }

    // MARK: - MRT navigation stack

    @ViewBuilder
    private func mrtNavStack(_ path: Binding<[SoftMrtRoute]>) -> some View {
        let pop = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        NavigationStack(path: path) {
            SoftMrtView(
                onOpenLine: { line in path.wrappedValue.append(.line(line)) },
                onOpenNews: { path.wrappedValue.append(.news) },
                onOpenAlerts: { showAlerts = true },
                onOpenSettings: { showSettings = true }
            )
            .adBannerGutter()
            .softTopEdgeBlur()
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Sheet views

    /// Search sheet — fullScreenCover so the keyboard + results fill the screen
    /// exactly like a tab would. Dismisses itself via `onClose`.
    private var searchSheet: some View {
        NavigationStack {
            SoftSearchView(
                onClose: { showSearch = false },
                onOpenStop: { code in
                    showSearch = false
                    homeStack.append(.stop(code))
                    tab = .home
                },
                onOpenBus: { stopCode, svcNo in
                    showSearch = false
                    homeStack.append(.bus(stopCode: stopCode, svc: svcNo, fullRoute: true))
                    tab = .home
                },
                onOpenMrtStation: { station in
                    showSearch = false
                    navigateToStation(station)
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .environmentObject(m)
        .environmentObject(fb)
        .environmentObject(ds)
    }

    /// Saved sheet — SoftFavouritesView at large detent.
    /// Navigation callbacks dismiss the sheet then continue into the stack.
    /// The navigation bar is kept visible only for the Done button; the large
    /// "Saved" title inside SoftFavouritesView's own List header is the visual
    /// title (the nav bar title is hidden via .inline + empty string so they
    /// don't double up).
    private var savedSheet: some View {
        NavigationStack {
            SoftFavouritesView(
                onOpenStop: { code in
                    showSaved = false
                    homeStack.append(.stop(code))
                    tab = .home
                },
                onOpenBus: { code, svc in
                    showSaved = false
                    homeStack.append(.bus(stopCode: code, svc: svc))
                    tab = .home
                },
                onOpenSearch: {
                    showSaved = false
                    showSearch = true
                },
                onOpenMrtStation: { station in
                    showSaved = false
                    navigateToStation(station)
                }
            )
            // Keep navigation bar visible for the Done button; suppress the
            // automatic title so the view's own "Saved" large heading shows instead.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSaved = false }
                        .font(m.t.sans(15, weight: .semibold))
                        .foregroundStyle(t.brand)
                }
            }
        }
        .environmentObject(m)
        .environmentObject(fb)
        .environmentObject(ds)
    }

    /// Alerts sheet — SoftAlertsView at large detent.
    /// Settings is still accessible via the gear inside SoftAlertsView's own header.
    /// ManageAlertsView is navigated to via the NavigationLink inside SoftAlertsView.
    private var alertsSheet: some View {
        NavigationStack {
            SoftAlertsView()
                // Suppress the automatic nav bar title — SoftAlertsView has its
                // own large "Alerts" heading inside the scroll content.
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showAlerts = false }
                            .font(m.t.sans(15, weight: .semibold))
                            .foregroundStyle(t.brand)
                    }
                }
        }
        .environmentObject(m)
        .environmentObject(fb)
    }

    // MARK: - Interstitial ad

    private func handleStackPop(_ old: [SoftRoute], _ new: [SoftRoute]) {
        guard new.count < old.count, let removed = old.last else { return }
        switch removed {
        case .stop, .bus:
            InterstitialAdManager.shared.maybeShowOnExit(model: m)
        case .search:
            break
        }
    }

    // MARK: - MRT station navigation

    /// Navigates to an MRT station detail: switches to Rail tab and pushes the
    /// station onto the MRT stack. Used by Search, Saved, and the legacy
    /// SoftRoute.search case in routeView.
    func navigateToStation(_ station: MrtGeoStation,
                           distanceM: Int? = nil,
                           walkMin: Int? = nil) {
        tab = .mrt
        mrtStack = [.station(station, distanceM: distanceM, walkMin: walkMin)]
    }
}
