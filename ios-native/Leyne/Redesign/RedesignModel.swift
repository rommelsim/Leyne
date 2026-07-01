// Controller for the SG Transit redesign (iOS) — a faithful port of the
// prototype's state machine to an ObservableObject. Holds the phase/screen
// state, navigation stack, theming choices, and the small set of interactions
// the design wires up (sort, expand, save, live-tracking, toast).

import SwiftUI
import Combine

enum RDPhase { case launch, onboarding, app }
enum RDPlatform { case android, apple }

/// Direction of the last screen transition, so push/pop animate consistently
/// (forward slides in from the trailing edge, back slides back out the same way).
enum RDNavDir { case forward, back }

@MainActor
final class RedesignModel: ObservableObject {
    // theming
    @Published var dark = false
    @Published var seed = "blue"
    @Published var premium = false

    // flow
    @Published var phase: RDPhase = .launch
    @Published var platform: RDPlatform = .apple
    @Published var obStep = 0

    // navigation
    @Published var screen = "map"
    @Published var stack: [String] = []
    @Published var navDir: RDNavDir = .forward

    // live data
    let store = DataStore.shared

    // home / detail — active selection points into the live data
    @Published var stopIdx = 0
    @Published var activeStopCode: String? = nil
    @Published var activeService: String? = nil
    @Published var activeRouteStop: String? = nil
    @Published var activeStationName: String? = nil
    @Published var sortBy = "eta"
    @Published var arrivalsExpanded = false
    @Published var savedStopCodes: Set<String> = []
    @Published var station: RDStation? = nil

    // route
    @Published var routeExpanded = false
    @Published var routeDownExpanded = false
    @Published var savedRoutes: Set<String> = []

    // overlays
    @Published var searchOpen = false
    @Published var tracking = false
    @Published var luVisible = false
    @Published var toast: String? = nil

    static let collapsedCount = 5

    private var toastTask: Task<Void, Never>?

    init() {
        // Dev-only deep entry for screenshots (only triggers when these env vars
        // are explicitly set, e.g. via `SIMCTL_CHILD_RD_*`; no-op in production).
        let env = ProcessInfo.processInfo.environment
        if let p = env["RD_PHASE"], p == "app" {
            phase = .app
            if let sc = env["RD_SCREEN"] {
                screen = sc
                if sc != "map" { stack = ["map"] }
                if sc == "station" {
                    station = kRDStations["holland"]
                    activeStationName = env["RD_STATION"] ?? "Farrer Road"
                }
                if sc == "route" {
                    activeService = env["RD_SVC"] ?? "48"
                    activeRouteStop = env["RD_STOP"] ?? "11111"
                }
                if sc == "stop" { activeStopCode = env["RD_STOP"] ?? "11111" }
            }
            if env["RD_DARK"] == "1" { dark = true }
            if let sd = env["RD_SEED"] { seed = sd }
            if env["RD_PREMIUM"] == "1" { premium = true }
            if env["RD_LU"] == "1" { luVisible = true; tracking = true }
            return
        }
        // Launch splash auto-advances after 2s. Returning users (who already
        // finished onboarding) skip straight to the app and resume location;
        // first-run users get the permission-priming onboarding.
        let onboarded = UserDefaults.standard.bool(forKey: "leyne.onboardingDone")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if self.phase == .launch {
                if onboarded {
                    self.phase = .app
                    LocationManager.shared.startIfAuthorized()
                } else {
                    self.phase = .onboarding
                }
            }
        }
    }

    // MARK: derived (live data)

    /// The nearby stop the user is currently looking at — the explicitly
    /// selected one, or the closest stop when nothing is selected.
    var currentNearby: NearbyStop? {
        if let code = activeStopCode {
            return store.nearby.first { $0.stopCode == code } ?? store.nearby.first
        }
        return store.nearby.first
    }

    var currentStop: RDStop {
        guard let n = currentNearby else {
            return RDStop(name: "Finding nearby stops…", code: "",
                          dist: "Waiting for your location", distShort: "",
                          badge: "", arrivals: [])
        }
        return rdStop(n)
    }

    /// The stop the Stop screen shows — `activeStopCode` resolved from the FULL
    /// stop dataset (it may be far from the user, e.g. tapped on a bus route),
    /// not just the nearby list. Falls back to the nearest stop.
    var activeStop: RDStop {
        guard let code = activeStopCode else { return currentStop }
        if let n = store.nearby.first(where: { $0.stopCode == code }) { return rdStop(n) }
        let here = LocationManager.shared.location
        let s = store.stopByCode[code]
        let dist: Int = (here != nil && s != nil)
            ? Int(haversine(here!.coordinate.latitude, here!.coordinate.longitude,
                            s!.Latitude, s!.Longitude).rounded())
            : 0
        let n = NearbyStop(id: code, stopName: store.stopName(code), stopCode: code,
                           distanceM: dist, walkMin: dist > 0 ? max(1, dist / 80) : 0,
                           services: store.servicesFor(code))
        return rdStop(n)
    }

    /// The code the Stop screen is showing (explicit tap, else nearest).
    var activeStopResolvedCode: String? { activeStopCode ?? store.nearby.first?.stopCode }

    var stopSaved: Bool {
        guard let code = currentNearby?.stopCode else { return false }
        return savedStopCodes.contains(code)
    }

    var sortedArrivals: [RDArrival] {
        currentStop.arrivals.sorted { a, b in
            if sortBy == "number" {
                return (Int(a.route) ?? Int.max) < (Int(b.route) ?? Int.max)
            }
            return (Int(a.min) ?? Int.max) < (Int(b.min) ?? Int.max)
        }
    }

    var visibleArrivals: [RDArrival] {
        arrivalsExpanded ? sortedArrivals : Array(sortedArrivals.prefix(Self.collapsedCount))
    }

    var canExpandArrivals: Bool { sortedArrivals.count > Self.collapsedCount }

    /// Nearest MRT/LRT station to the user — drives the Home transfer card.
    var nearestMrt: (station: MrtGeoStation, distanceM: Int, walkMin: Int)? {
        guard let loc = LocationManager.shared.location else { return nil }
        return MrtGeo.nearestStation(to: loc.coordinate)
    }

    /// Other nearby stops (not the current one), paired with their index in
    /// `store.nearby` for selection.
    var otherStops: [(stop: RDStop, index: Int)] {
        let cur = currentNearby?.stopCode
        return store.nearby.enumerated().compactMap { i, n in
            n.stopCode == cur ? nil : (rdStop(n), i)
        }
    }

    var activeStation: RDStation { station ?? kRDStations["holland"]! }

    var routeSaved: Bool {
        guard let svc = activeService else { return false }
        return savedRoutes.contains(svc)
    }

    var obSteps: [String] {
        platform == .apple ? ["welcome", "notif", "location", "att", "done"]
                           : ["welcome", "notif", "location", "done"]
    }
    var obCurrent: String { obSteps[min(max(obStep, 0), obSteps.count - 1)] }

    var showNav: Bool {
        (screen == "map" || screen == "lines" || screen == "saved") && !searchOpen
    }

    var canHandleBack: Bool { searchOpen || !stack.isEmpty || screen != "map" }

    // MARK: actions

    func go(_ s: String) {
        navDir = .forward
        stack.append(screen)
        screen = s
        searchOpen = false
    }

    func back() {
        navDir = .back
        screen = stack.popLast() ?? "map"
    }

    func toMap() {
        navDir = .back
        screen = "map"; stack.removeAll(); searchOpen = false
    }

    func toLines() {
        navDir = .forward
        screen = "lines"; stack = ["map"]; searchOpen = false
    }

    func openStop() { go("stop") }
    func openRoute() { go("route") }

    /// Open a specific stop's detail (from search / nearby / saved).
    func openStop(code: String) {
        activeStopCode = code
        go("stop")
    }

    /// Open a bus route, anchored to the stop the user is watching it from.
    func openBus(service: String, stopCode: String?) {
        activeService = service
        activeRouteStop = stopCode
        go("route")
    }

    func selectStop(_ i: Int) {
        navDir = .back
        if i >= 0, i < store.nearby.count { activeStopCode = store.nearby[i].stopCode }
        screen = "map"; stack.removeAll()
    }

    func openStation(_ key: String) {
        navDir = .forward
        stack.append(screen)
        station = kRDStations[key]
        screen = "station"
        searchOpen = false
    }

    /// Open a real MRT/LRT station by display name (from the live transfer card
    /// or search). The station screen resolves identity + crowd from this.
    func openStation(named name: String) {
        navDir = .forward
        stack.append(screen)
        activeStationName = name
        station = nil
        screen = "station"
        searchOpen = false
    }

    func toggleSaveStop() {
        guard let n = currentNearby else { return }
        let on = !savedStopCodes.contains(n.stopCode)
        if on { savedStopCodes.insert(n.stopCode) } else { savedStopCodes.remove(n.stopCode) }
        notify(on ? "Saved \(n.stopName)" : "Removed \(n.stopName) from saved")
    }

    func notify(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(3600))
            guard let self, !Task.isCancelled else { return }
            self.toast = nil
        }
    }

    func dismissToast() { toastTask?.cancel(); toast = nil }

    func setSort(_ s: String) { sortBy = s }
    func toggleArrivals() { arrivalsExpanded.toggle() }
    func toggleRoute() { routeExpanded.toggle() }
    func toggleRouteDown() { routeDownExpanded.toggle() }

    func saveRoute() {
        guard let svc = activeService else { return }
        let on = !savedRoutes.contains(svc)
        if on { savedRoutes.insert(svc) } else { savedRoutes.remove(svc) }
        notify(on ? "Bus \(svc) saved" : "Removed Bus \(svc) from saved")
    }

    // theming
    func toggleTheme() { dark.toggle() }
    func togglePremium() { premium.toggle() }
    func setSeed(_ k: String) { seed = k }

    // onboarding
    func setPlatform(_ p: RDPlatform) { platform = p; obStep = 0 }

    func obNext() {
        if obStep >= obSteps.count - 1 {
            phase = .app; screen = "map"; stack.removeAll()
        } else {
            obStep += 1
        }
    }

    func replayOnboarding() {
        phase = .onboarding; obStep = 0; stack.removeAll(); screen = "map"
    }

    // live tracking
    private var trackMsg: String {
        let svc = activeService ?? "your bus"
        return "Live Update on · we’ll alert you when \(svc) is 1 stop away"
    }

    func startTrack() {
        notify(trackMsg)
        tracking = true; luVisible = true
        navDir = .forward
        stack.append(screen); screen = "route"
    }

    func trackFromRoute() {
        notify(trackMsg)
        tracking = true; luVisible = true
    }

    func stopTrack() { tracking = false; luVisible = false }
    func dismissLU() { luVisible = false }

    func luView() {
        luVisible = false
        if screen != "route" { navDir = .forward; stack.append(screen); screen = "route" }
    }

    // search
    func openSearch() { searchOpen = true }
    func closeSearch() { searchOpen = false }

    /// Returns true if an in-app back action was performed.
    @discardableResult
    func handleBack() -> Bool {
        if searchOpen { searchOpen = false; return true }
        if !stack.isEmpty { back(); return true }
        if screen != "map" { toMap(); return true }
        return false
    }
}
