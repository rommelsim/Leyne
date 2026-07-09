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
    case busStop(code: String)
    case mrtStation(MrtGeoStation)
    case serviceInfo(no: String, fromStop: String?)
    case trackBus(stopCode: String, no: String)
    case map
}

/// Zoom-transition source ID for an MRT station — the "connected" card→screen
/// entry from the animation spec (matched geometry). Shared between the card
/// that registers itself as the source and the pushed destination.
func wsMrtZoomID(_ st: MrtGeoStation) -> String {
    "mrt-" + (st.codes.first ?? st.name)
}

/// Zoom-transition source IDs for the other root-level pushes — the owner
/// liked the MRT card→screen zoom (and its interactive swipe-back) so much it
/// now covers the whole app base (owner call 2026-07-09): bus stops, track
/// bus and the map door all zoom from the card/row that opened them.
func wsStopZoomID(_ code: String) -> String { "stop-" + code }
func wsBusZoomID(stopCode: String, no: String) -> String { "bus-\(stopCode)-\(no)" }
let wsMapZoomID = "map"

/// Environment-injected "push a route onto the current tab's stack".
private struct WSPushKey: EnvironmentKey {
    static let defaultValue: (WSRoute) -> Void = { _ in }
}

/// The root's zoom-transition namespace, handed down so root-level cards can
/// register as `matchedTransitionSource`s (nil in previews / outside WSRoot).
private struct WSZoomNSKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}
extension EnvironmentValues {
    var wsZoomNS: Namespace.ID? {
        get { self[WSZoomNSKey.self] }
        set { self[WSZoomNSKey.self] = newValue }
    }
}

/// Registers the view as the zoom source for `id` when the namespace exists.
struct WSZoomSource: ViewModifier {
    let id: String
    @Environment(\.wsZoomNS) private var ns
    func body(content: Content) -> some View {
        if let ns { content.matchedTransitionSource(id: id, in: ns) }
        else { content }
    }
}
extension View {
    func wsZoomSource(id: String) -> some View { modifier(WSZoomSource(id: id)) }
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
    /// One namespace for the card→screen zoom transitions (anim spec:
    /// matched geometry for the MRT station entry).
    @Namespace private var zoomNS

    // Follow the system appearance directly — the in-app Appearance picker
    // left with the Me tab, and m.isDark would pin users to a stale choice.
    @Environment(\.colorScheme) private var colorScheme
    private var ws: WSTheme { .resolve(dark: colorScheme == .dark) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The navigation path of the currently selected tab.
    private var activePath: [WSRoute] {
        switch tab {
        case .home:   homePath
        case .saved:  savedPath
        case .alerts: alertsPath
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .home:   stack($homePath) { WSHomeView(onSearch: { showSearch = true }) }
            case .saved:  stack($savedPath) { WSSavedView() }
            case .alerts: stack($alertsPath) { WSAlertsView() }
            }
        }
        .background(ws.bg.ignoresSafeArea())
        // Floating glass tab bar as a bottom safe-area inset, not a manual
        // ZStack overlay with a fixed content padding: scroll content can
        // now reach — and show through — the material at the bottom of a
        // list, matching the native iOS 26 floating-bar composition.
        //
        // Root tabs only: pushed destinations don't inherit a custom
        // safe-area inset applied outside their NavigationStack, so the bar
        // floated OVER pushed content (it hid Track Bus's pinned CTA —
        // owner-reported). Hiding it on push is also the better design:
        // detail screens are focused tasks with their own chrome.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack {
                if activePath.isEmpty {
                    // Root tabs are native-ad-only (one NativeAdCard inline in
                    // each tab's list) — no banner in the tab-bar gutter. The
                    // anchored banner lives on the high-dwell detail screens
                    // instead (`wsDetailAdBanner`), where its 30–60 s refresh
                    // actually earns. Owner decision 2026-07-07.
                    WSTabBar(tab: $tab, alertCount: m.unseenAlertCount)
                        // Scrim under the floating bar: scrolled-under content
                        // fades toward the background instead of clashing with
                        // the bar's transparent gutter (owner 2026-07-08 — the
                        // browse card read as "covered", not "scrolled under").
                        // As a `.background` it never affects the inset's
                        // layout; negative top padding bleeds it a few points
                        // above the bar, and it extends into the home bar.
                        .background {
                            LinearGradient(colors: [ws.bg.opacity(0),
                                                    ws.bg.opacity(0.94), ws.bg],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.top, -24)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                        }
                        .transition(reduceMotion ? .opacity :
                            .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: activePath.isEmpty)
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
        // Screenshot/UI-test hook: `-wsRoute stop:83139`, `-wsRoute mrt:CC20`
        // or `-wsRoute bus:83139/174` deep-links straight to a detail screen
        // from the command line (simctl launch … -wsRoute stop:83139). No-op
        // without the argument.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-wsRoute"), args.indices.contains(i + 1)
            else { return }
            let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            switch parts[0] {
            case "stop": homePath = [.busStop(code: parts[1])]
            case "mrt":  if let st = MrtGeo.station(forCode: parts[1]) {
                             homePath = [.mrtStation(st)]
                         }
            case "bus":
                let p = parts[1].split(separator: "/", maxSplits: 1).map(String.init)
                if p.count == 2 {
                    homePath = [.busStop(code: p[0]), .trackBus(stopCode: p[0], no: p[1])]
                }
            default: break
            }
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
                    // above the nav bar stays visible here. NOTE: hiding the
                    // system back button still disables the edge-swipe pop
                    // gesture, so `wsHeaderBar` applies `enableSwipeBack()`.
                    destination(route, path: path)
                }
        }
        .environment(\.wsPush) { route in path.wrappedValue.append(route) }
        .environment(\.wsZoomNS, zoomNS)
    }

    @ViewBuilder
    private func destination(_ route: WSRoute, path: Binding<[WSRoute]>) -> some View {
        let back = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        // Exit interstitial hook — a back-out of a dwell screen (stop / station /
        // track bus) is the app's natural break. The manager owns every guard
        // (frequency cap, exit count, cross-format gap, deep-link suppression),
        // so this is safe to call on every pop. Map and Service Info stay
        // hook-free: short-dwell, task-critical surfaces.
        let backWithAd = { [weak m] in
            back()
            if let m { InterstitialAdManager.shared.maybeShowOnExit(model: m) }
        }
        // Card→screen zoom (anim spec: matched geometry) — only from a
        // root card/row that registered itself as the source (path depth 1);
        // deeper pushes (stop → MRT, track bus → MRT) keep the standard
        // slide so the system never zooms from an off-screen root card.
        // Reduce Motion: plain push (the spec's fade fallback). If no source
        // registered under the ID, the system falls back to the standard
        // push on its own. Owner call 2026-07-09: the zoom (and its
        // interactive swipe-back) covers every root-level push, not just MRT.
        let zooms = path.wrappedValue.count == 1 && !reduceMotion
        switch route {
        case .busStop(let code):
            let v = WSBusStopView(code: code, onBack: backWithAd)
            if zooms { v.navigationTransition(.zoom(sourceID: wsStopZoomID(code), in: zoomNS)) }
            else { v }
        case .mrtStation(let station):
            let v = WSMrtStationView(station: station, onBack: backWithAd)
            if zooms { v.navigationTransition(.zoom(sourceID: wsMrtZoomID(station), in: zoomNS)) }
            else { v }
        case .serviceInfo(let no, let fromStop):
            WSServiceInfoView(serviceNo: no, fromStop: fromStop, onBack: back)
        case .trackBus(let stopCode, let no):
            let v = WSTrackBusView(stopCode: stopCode, serviceNo: no, onBack: backWithAd)
            if zooms {
                v.navigationTransition(.zoom(sourceID: wsBusZoomID(stopCode: stopCode, no: no),
                                             in: zoomNS))
            } else { v }
        case .map:
            let v = WSMapView(onBack: back)
            if zooms { v.navigationTransition(.zoom(sourceID: wsMapZoomID, in: zoomNS)) }
            else { v }
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
