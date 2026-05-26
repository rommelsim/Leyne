// Central app state. Pins are user data (persisted, stop-code keyed);
// all arrivals/stops/routes are live from LTA via DataStore. No mock data.

import SwiftUI
import Combine
import CoreLocation
import UIKit
import ActivityKit
import WidgetKit
import UserNotifications
import os

/// App Group shared between the app and the LyneWidgets extension.
enum AppGroup {
    static let id = "group.com.leyne"        // must match *.entitlements
    static let pinsKey = "leyne.pins.shared"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// Minimal pinned-stop record the Home Screen widget reads (it can't see the
/// app's models). One row = one pinnable stop the user can pick in the widget.
struct SharedPinnedStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String    // nickname or resolved stop name
}

private let laLog = Logger(subsystem: "com.leyne.Leyne", category: "LiveActivity")

enum AppTab: String { case home, nearby, settings, search }

// MARK: - Theme mode override

/// Appearance override. Matches Flutter's three-way ThemeMode enum.
enum LeyneThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    /// ColorScheme for `.preferredColorScheme`, or nil to follow the OS.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - What's New (changelog shown once per app update)

struct WhatsNewItem {
    let icon: String   // SF Symbol name
    let title: String
    let body: String
}

struct WhatsNewEntry {
    let headline: String
    let items: [WhatsNewItem]
}

/// Release notes shown by the What's New screen on update. Mirrors
/// lib/data/changelog.dart — drop old entries freely; only the running
/// version's entry is ever read.
let kChangelog: [String: WhatsNewEntry] = [
    "2.0.0": WhatsNewEntry(
        headline: "A clearer, more honest commute.",
        items: [
            WhatsNewItem(
                icon: "location.slash",
                title: "Know when a time is a guess",
                body: "Arrival times without a live GPS fix are now tagged "
                    + "\"~ scheduled\", so you know which ones to fully trust."
            ),
            WhatsNewItem(
                icon: "clock",
                title: "First & last bus",
                body: "Each service now shows its first and last bus for the "
                    + "day — with a heads-up when the last one has already left."
            ),
            WhatsNewItem(
                icon: "location.circle",
                title: "Search by postal code",
                body: "Enter any 6-digit postal code to map the bus stops near "
                    + "that address. Set the search radius in Settings."
            ),
            WhatsNewItem(
                icon: "bus.fill",
                title: "Arriving buses stand out",
                body: "In Nearby, the number of a bus arriving now lights up green."
            ),
        ]
    ),
]

/// A user-pinned stop. Invariant: a Pin always tracks ≥1 bus — so
/// "pinned" ⟺ "has buses shown". `tracked == nil` means *all* services
/// (default; correct even before arrivals load). A non-nil array is an
/// explicit, non-empty subset. An empty selection is never stored — it
/// means "unpin" (the Pin is removed).
struct Pin: Codable, Equatable {
    var code: String
    var nickname: String
    var tracked: [String]? = nil          // nil = all
    /// Optional user-marked primary bus number. When nil, the home card
    /// auto-picks the soonest tracked service as primary; when set, that
    /// chosen bus stays marked regardless of how its ETA shifts.
    var primary: String? = nil

    init(code: String, nickname: String, tracked: [String]? = nil,
         primary: String? = nil) {
        self.code = code; self.nickname = nickname; self.tracked = tracked
        self.primary = primary
    }

    enum CodingKeys: String, CodingKey { case code, nickname, tracked, primary }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        tracked = try? c.decodeIfPresent([String].self, forKey: .tracked)
        primary = try? c.decodeIfPresent(String.self, forKey: .primary)
    }
}

@MainActor
final class AppModel: ObservableObject {
    // Sound / haptic feedback (v1.0 carry-over).
    @AppStorage("leyne.sound")  var sound = true
    @AppStorage("leyne.haptic") var haptic = true

    // Onboarding completion. Persisted under the Flutter v2.0 key so an
    // upgrade from Flutter → native preserves the user's onboarding flag.
    @AppStorage("leyne.onboardingDone") var onboarded = false

    // 24-hour clock display in the LIVE header. Defaults to true (SG locale).
    @AppStorage("leyne.use24h") var use24h = true

    // Appearance override (Settings ▸ Appearance). Defaults to .system — the
    // theme follows OS Settings ▸ Display & Brightness — but the user can
    // force light or dark from in-app Settings.
    @AppStorage("leyne.themeMode") var themeMode: LeyneThemeMode = .system

    // Language override. Empty string = follow device locale.
    @AppStorage("leyne.locale") var localeCode = ""
    /// Non-empty when the user has picked a language override; nil otherwise.
    var localeIdentifier: String? { localeCode.isEmpty ? nil : localeCode }

    // Arrival-alert notifications. Real device notifications scheduled via
    // UNUserNotificationCenter — fire on the Lock Screen / banner even when
    // the app is backgrounded. Toggle the user-facing intent through
    // `setNotificationsEnabled(_:)` so permission is requested at the right
    // moment; this raw storage flag is the persisted result of that flow.
    @AppStorage("leyne.notifications") var notificationsEnabled = false

    /// Last observed UNAuthorizationStatus, refreshed on launch and whenever
    /// the user toggles the Notifications setting. Drives the warning row
    /// in NotificationsView when the system permission is denied.
    @Published var notificationAuth: UNAuthorizationStatus = .notDetermined

    // ─── Active alight ride (persisted) ───────────────────
    // One ride at a time. Setting this schedules a one-shot local
    // notification at `fireAt`, persisted across app restarts so the
    // user sees "your alight is set" when they reopen DetailView.
    // Cleared when the user untaps the alight stop or the bus passes.
    @AppStorage("lyne.alight.busNo") private var alightBusNoStore = ""
    @AppStorage("lyne.alight.stopCode") private var alightStopCodeStore = ""
    @AppStorage("lyne.alight.stopName") private var alightStopNameStore = ""
    @AppStorage("lyne.alight.fireAt") private var alightFireAtStore: Double = 0

    /// The currently-armed alight alert, or nil. Reads from @AppStorage
    /// so a fresh DetailView open recognizes a previously-set ride.
    var activeAlight: (busNo: String, stopCode: String,
                       stopName: String, fireAt: Date)? {
        guard !alightBusNoStore.isEmpty, !alightStopCodeStore.isEmpty,
              alightFireAtStore > 0 else { return nil }
        return (busNo: alightBusNoStore,
                stopCode: alightStopCodeStore,
                stopName: alightStopNameStore,
                fireAt: Date(timeIntervalSince1970: alightFireAtStore))
    }

    /// True when an active alight ride matches this specific bus/stop
    /// combo — DetailView uses this to highlight the picked stop and
    /// render the "alert is on" state on the on-bus alert card.
    func isActiveAlight(busNo: String, stopCode: String) -> Bool {
        activeAlight?.busNo == busNo
            && activeAlight?.stopCode == stopCode
    }

    // Postal-code search radius in metres. Used by the Search screen when
    // the query is a 6-digit postal code.
    @AppStorage("leyne.searchRadiusM") var searchRadiusM = 500

    // What's New gate — the last version the user acknowledged.
    @AppStorage("leyne.lastSeenVersion") private var lastSeenVersion = ""

    /// Mirrors the iOS color scheme after applying the user's `themeMode`
    /// override. Set from the SwiftUI environment in `RootView`.
    @Published var isDark: Bool = false
    var t: Theme { isDark ? .dark : .light }

    /// The running app's marketing version (set once at boot from
    /// Bundle.main). Drives the What's New gate.
    @Published var currentVersion: String?

    /// Module-level stash so LeyneApp.init can record the version before the
    /// AppModel instance exists (init runs on a non-main thread otherwise).
    nonisolated(unsafe) static var bootVersion: String?

    // Navigation / overlays
    @Published var tab: AppTab = .home
    @Published var launching = true
    @Published var showOnboarding = false
    @Published var showAdd = false
    @Published var searchOpen = false
    @Published var openCard: CardModel? = nil
    @Published var liveActivityOn = false
    /// Identifies the bus+stop the running Live Activity belongs to, so the
    /// button can reflect/toggle its state. nil ⟺ no Live Activity running.
    @Published private(set) var liveActivityKey: String? = nil
    private var liveActivity: Activity<LeyneActivityAttributes>?
    private var liveActivityTask: Task<Void, Never>?
    private var liveActivityEndObserver: Task<Void, Never>?

    static func liveKey(bus: String, stopCode: String) -> String {
        "\(stopCode)|\(bus)"
    }
    /// True when a Live Activity is currently running for *this* bus at *this*
    /// stop — drives the Start/Stop toggle in Detail.
    func isLiveActivityActive(_ s: Service, stopCode: String) -> Bool {
        liveActivityKey == Self.liveKey(bus: s.no, stopCode: stopCode)
    }
    @Published var recentlyAddedId: String? = nil

    // Persisted user pins (start empty — no mock seeds)
    @Published var pins: [Pin] = [] {
        didSet { persistPins() }
    }
    // Persisted recent searches
    @Published var recents: [String] = []

    @Published var tick = 0
    private var timer: AnyCancellable?
    private let ds = DataStore.shared

    init() {
        loadPins()
        loadRecents()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.onTick() }
            }
        showOnboarding = !onboarded
        if let s = UserDefaults.standard.string(forKey: "leyne.startTab"),
           let initial = AppTab(rawValue: s), initial != .search { tab = initial }
        syncFeedback()
        restoreLiveActivity()
        observeActivityRestores()
        mirrorPinsToWidget()
    }

    /// iOS restores existing Live Activities asynchronously after a cold
    /// launch, so the synchronous `Activity.activities` lookup in
    /// `restoreLiveActivity()` can come back empty. `activityUpdates` keeps
    /// emitting activities as they arrive, letting us re-adopt one we lost
    /// track of (e.g. force-quit ⟶ relaunch with the LA still on the lock
    /// screen) and keep the Start/Stop toggle in DetailView accurate.
    private func observeActivityRestores() {
        Task { @MainActor [weak self] in
            for await act in Activity<LeyneActivityAttributes>.activityUpdates {
                guard let self else { return }
                guard self.liveActivity == nil else { continue }
                self.liveActivity = act
                self.liveActivityKey = Self.liveKey(bus: act.attributes.busNo,
                                                   stopCode: act.attributes.stopCode)
                self.liveActivityOn = true
                laLog.notice("LA RESTORED (async) id=\(act.id) bus=\(act.attributes.busNo)")
                self.observeLiveActivityEnd(act)
                self.startLivePolling(busNo: act.attributes.busNo,
                                      stopCode: act.attributes.stopCode)
            }
        }
    }

    // ─── Persistence ──────────────────────────────────────
    private func loadPins() {
        if let d = UserDefaults.standard.data(forKey: "leyne.pins"),
           let p = try? JSONDecoder().decode([Pin].self, from: d) { pins = p }
    }
    private func persistPins() {
        if let d = try? JSONEncoder().encode(pins) {
            UserDefaults.standard.set(d, forKey: "leyne.pins")
        }
        mirrorPinsToWidget()
        // Keep iOS Spotlight in sync — every pin becomes a searchable
        // result discoverable from the system search anywhere.
        Spotlight.updateIndex(pins: pins) { [ds] code in ds.stopName(code) }
    }

    /// Publishes the pinned stops to the App Group and asks WidgetKit to
    /// refresh, so the Home Screen widget always offers the current pins.
    private func mirrorPinsToWidget() {
        let stops = pins.map { p -> SharedPinnedStop in
            let nick = p.nickname.trimmingCharacters(in: .whitespaces)
            let name = !nick.isEmpty ? nick
                : { let n = ds.stopName(p.code); return n.isEmpty ? p.code : n }()
            return SharedPinnedStop(id: p.code, name: name)
        }
        if let d = try? JSONEncoder().encode(stops) {
            AppGroup.defaults?.set(d, forKey: AppGroup.pinsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func loadRecents() {
        recents = UserDefaults.standard.stringArray(forKey: "leyne.recents") ?? []
    }
    func addRecent(_ q: String) {
        let v = q.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        recents.removeAll { $0.caseInsensitiveCompare(v) == .orderedSame }
        recents.insert(v, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: "leyne.recents")
    }

    func finishOnboarding() {
        onboarded = true
        showOnboarding = false
        // Pin the running version so the What's New screen doesn't fire on
        // the user's very next launch for the version they just installed.
        if let v = currentVersion { lastSeenVersion = v }
    }
    func syncFeedback() { Feedback.shared.config(sound: sound, haptic: haptic) }

    // ─── What's New / version tracking ──────────────────────

    /// Set the running app's marketing version. Call once at boot from
    /// `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`.
    func setCurrentVersion(_ v: String) {
        if currentVersion == v { return }
        currentVersion = v
    }

    /// The version whose What's New screen should be shown now, or nil.
    /// Fresh installs (still in onboarding) never see it — they have no
    /// prior version to have "updated" from; `finishOnboarding` pins their
    /// version so it stays that way.
    var whatsNewVersion: String? {
        guard let v = currentVersion, kChangelog[v] != nil else { return nil }
        if lastSeenVersion == v { return nil }
        if !onboarded { return nil }
        return v
    }

    /// Acknowledge the running version's What's New screen. After this the
    /// What's New screen won't show again until the next version with a
    /// changelog entry.
    func markWhatsNewSeen() {
        if let v = currentVersion { lastSeenVersion = v }
    }

    /// Replay onboarding from Settings.
    func resetOnboarding() {
        onboarded = false
        showOnboarding = true
    }

    // ─── Tick: smooth countdown + keep visible stops fresh ─
    private func onTick() {
        tick &+= 1
        var codes = Set(pins.map(\.code))
        if let c = openCard?.stopCode { codes.insert(c) }
        for c in codes { ds.ensureArrivals(stop: c) }

        // Reschedule arrival-alert notifications every ~10 s — LTA's
        // arrivalDate values drift, and a coarse cadence is enough since
        // notification fire times are absolute (set via UNCalendarTrigger).
        if notificationsEnabled, tick % 10 == 0 {
            NotificationsManager.shared.scheduleArrivalAlerts(
                pins: pins, cards: allPinnedCards)
        }
    }

    // ─── Arrival-alert notifications (public surface) ─────

    /// Toggle the user's intent. Turning on requests system authorization;
    /// if denied, the toggle snaps back to off. Turning off clears any
    /// pending scheduled notifications.
    func setNotificationsEnabled(_ on: Bool) async {
        if on {
            let granted = await NotificationsManager.shared.requestAuthorization()
            notificationAuth = await NotificationsManager.shared.currentStatus()
            if granted {
                notificationsEnabled = true
                NotificationsManager.shared.scheduleArrivalAlerts(
                    pins: pins, cards: allPinnedCards)
            } else {
                notificationsEnabled = false
            }
        } else {
            notificationsEnabled = false
            NotificationsManager.shared.clearAll()
        }
    }

    /// Refreshes `notificationAuth` from the system — call on view appear.
    func refreshNotificationAuth() async {
        notificationAuth = await NotificationsManager.shared.currentStatus()
        // If the user revoked permission via system Settings while the
        // app was alive, drop the in-app flag so the toggle reads honest.
        if notificationsEnabled, notificationAuth == .denied {
            notificationsEnabled = false
            NotificationsManager.shared.clearAll()
        }
    }

    /// Arm the alight alert for `busNo` heading to `stopName`/`stopCode`.
    /// `fireAt` is the absolute moment the notification should appear —
    /// DetailView computes it from RouteInfo: 90 s × (stopsToAlight − 2)
    /// from now, so the user gets a heads-up two stops out. Replaces any
    /// previous active alight; one ride at a time.
    func setActiveAlight(busNo: String, stopCode: String,
                         stopName: String, fireAt: Date) {
        NotificationsManager.shared.cancelAlightAlerts()
        alightBusNoStore = busNo
        alightStopCodeStore = stopCode
        alightStopNameStore = stopName
        alightFireAtStore = fireAt.timeIntervalSince1970
        NotificationsManager.shared.scheduleAlightAlert(
            busNo: busNo, alightStopName: stopName, fireAt: fireAt)
        objectWillChange.send()
    }

    /// Disarm the current alight ride and cancel its pending alert.
    func clearActiveAlight() {
        alightBusNoStore = ""
        alightStopCodeStore = ""
        alightStopNameStore = ""
        alightFireAtStore = 0
        NotificationsManager.shared.cancelAlightAlerts()
        objectWillChange.send()
    }

    // ─── Live service composition ─────────────────────────
    func liveServices(code: String, tracked: [String]) -> [Service] {
        let now = Date()
        let all = ds.servicesFor(code)
        let filtered = tracked.isEmpty ? all : all.filter { tracked.contains($0.no) }
        return filtered.map { s -> Service in
            var x = s
            if let a = s.arrivalDate { x.etaSec = max(0, Int(a.timeIntervalSince(now))) }
            if let f = s.followingDate {
                x.followingSec = max(x.etaSec, Int(f.timeIntervalSince(now)))
            }
            return x
        }
        .sorted { $0.etaSec < $1.etaSec }
    }

    private func walkMin(forCode code: String) -> Int {
        guard let loc = LocationManager.shared.location,
              let s = ds.stopByCode[code] else { return 0 }
        let d = haversine(loc.coordinate.latitude, loc.coordinate.longitude,
                          s.Latitude, s.Longitude)
        return max(1, Int((d / 80).rounded()))
    }

    func pin(forCode code: String) -> Pin? { pins.first { $0.code == code } }

    private func card(for pin: Pin) -> CardModel {
        let name = ds.stopName(pin.code)
        return CardModel(
            id: pin.code,
            label: pin.nickname.isEmpty ? name : pin.nickname,
            stopName: name,
            stopCode: pin.code,
            walkMin: walkMin(forCode: pin.code),
            // All services; PinnedCardView filters via the hidden set so it can
            // still show the "Tracking N/M" chip + "+N more" overflow.
            services: liveServices(code: pin.code, tracked: [])
        )
    }

    var allPinnedCards: [CardModel] { pins.map(card(for:)) }

    func openCardLive() -> CardModel? {
        guard let c = openCard else { return nil }
        let p = pin(forCode: c.stopCode)
        var out = c
        out.label = p?.nickname.isEmpty == false ? p!.nickname
            : (ds.stopName(c.stopCode))
        out.stopName = ds.stopName(c.stopCode)
        out.walkMin = walkMin(forCode: c.stopCode)
        out.services = liveServices(code: c.stopCode, tracked: [])  // detail shows all
        return out
    }

    // ─── Pin mutations ────────────────────────────────────
    func isPinned(_ code: String) -> Bool { pins.contains { $0.code == code } }
    func isCardPinned(_ card: CardModel) -> Bool { isPinned(card.stopCode) }

    func togglePin(code: String) {
        if let i = pins.firstIndex(where: { $0.code == code }) {
            Feedback.shared.tap()
            pins.remove(at: i)                              // unpin
        } else {
            Feedback.shared.success()
            pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: nil)) // all
            markNew(code)
        }
    }
    func togglePinForCard(_ card: CardModel) { togglePin(code: card.stopCode) }

    /// Sets (or clears) the user-chosen primary bus for a pinned stop. The
    /// primary is the bus that gets the mint-filled badge + bookmark marker
    /// on Home, regardless of which bus is currently soonest. Pass `nil`
    /// to clear and fall back to the auto soonest-tracked behaviour.
    func setPrimary(code: String, busNo: String?) {
        guard let i = pins.firstIndex(where: { $0.code == code }) else { return }
        if pins[i].primary == busNo { return }
        pins[i].primary = busNo
        Feedback.shared.tap()
    }

    /// Reorder: move the pin with `source` stopCode so that it sits right
    /// before the pin with `target` stopCode. Used by Edit-mode drag-and-
    /// drop on Home. No-op if either code is unknown, if the source is
    /// already the immediate predecessor of the target, or if both codes
    /// are the same (self-drop).
    func movePin(_ source: String, before target: String) {
        guard source != target,
              let from = pins.firstIndex(where: { $0.code == source }),
              let to = pins.firstIndex(where: { $0.code == target })
        else { return }
        if from == to - 1 { return }                       // already there
        let pin = pins.remove(at: from)
        // After removal indices ≥ `from` shift down by one — recompute.
        let insertAt = pins.firstIndex(where: { $0.code == target }) ?? pins.endIndex
        pins.insert(pin, at: insertAt)
        Feedback.shared.tap()
    }

    /// `shown` = the service nos the user checked in the Add sheet.
    func addPin(code: String, tracked shown: [String]) {
        guard !shown.isEmpty else { return }               // never an empty pin
        let all = ds.servicesFor(code).map(\.no)
        let tr: [String]? = (Set(shown) == Set(all)) ? nil : shown
        if let i = pins.firstIndex(where: { $0.code == code }) {
            pins[i].tracked = tr
        } else {
            pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: tr))
        }
        showAdd = false
        tab = .home
        markNew(code)
        Feedback.shared.success()
    }

    private func markNew(_ code: String) {
        recentlyAddedId = code
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.recentlyAddedId == code { self?.recentlyAddedId = nil }
        }
    }

    func rename(code: String, to newName: String) {
        guard let i = pins.firstIndex(where: { $0.code == code }) else { return }
        pins[i].nickname = newName
    }
    func renameCard(_ id: String, _ newLabel: String) { rename(code: id, to: newLabel) }

    /// True if `busNo` is shown on Home. Not pinned → nothing tracked.
    func isTracked(code: String, busNo: String) -> Bool {
        guard let p = pin(forCode: code) else { return false }
        guard let tr = p.tracked else { return true }      // nil = all
        return tr.contains(busNo)
    }

    /// Service numbers hidden from the Home card for this stop.
    func hiddenSet(code: String, allNos: [String] = []) -> Set<String> {
        guard let p = pin(forCode: code) else { return Set(allNos) }
        guard let tr = p.tracked else { return [] }        // all shown
        return Set(allNos).subtracting(tr)
    }

    /// Toggle a service. Checking on an unpinned stop pins it; unchecking
    /// the last tracked bus unpins it (pinned ⟺ ≥1 bus).
    func toggleTracked(code: String, busNo: String, allNos: [String] = []) {
        guard let i = pins.firstIndex(where: { $0.code == code }) else {
            // Not pinned → checking a bus pins the stop tracking just it.
            pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: [busNo]))
            Feedback.shared.success()
            return
        }
        var shown = pins[i].tracked.map(Set.init) ?? Set(allNos)   // nil = all
        if shown.contains(busNo) { shown.remove(busNo) } else { shown.insert(busNo) }
        if shown.isEmpty {
            Feedback.shared.tap()
            pins.remove(at: i)                              // unchecked last → unpin
        } else if shown == Set(allNos) {
            pins[i].tracked = nil                           // back to "all"
        } else {
            pins[i].tracked = Array(shown)
        }
    }

    /// True iff the stop is pinned and tracking every service.
    func allTracked(code: String) -> Bool {
        pin(forCode: code)?.tracked == nil && isPinned(code)
    }

    /// Master control. Track all → pin tracking everything.
    /// Untrack all → unpin (a stop with no buses isn't on Home).
    func setAllTracked(code: String, allNos: [String], tracked on: Bool) {
        if on {
            if let i = pins.firstIndex(where: { $0.code == code }) {
                pins[i].tracked = nil
            } else {
                pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: nil))
                Feedback.shared.success()
            }
        } else if let i = pins.firstIndex(where: { $0.code == code }) {
            Feedback.shared.tap()
            pins.remove(at: i)
        }
    }

    func reorderPins(_ newCodes: [String]) {
        var next: [Pin] = []
        for c in newCodes { if let p = pins.first(where: { $0.code == c }) { next.append(p) } }
        for p in pins where !newCodes.contains(p.code) { next.append(p) }
        pins = next
    }

    // ─── Navigation ───────────────────────────────────────
    func setTab(_ next: AppTab) {
        if next != tab { Feedback.shared.select() }
        tab = next
    }
    func open(stopCode: String, label: String, busNo: String? = nil, feedback: Bool = true) {
        if feedback { Feedback.shared.select() }
        // Resign any active editor (e.g. an in-progress pin rename) so the
        // keyboard doesn't linger over the detail view; this also commits
        // the rename via PinTag's focus-loss handler.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        ds.ensureArrivals(stop: stopCode, force: true)
        openCard = CardModel(id: stopCode, label: label,
                             stopName: ds.stopName(stopCode), stopCode: stopCode,
                             walkMin: 0, services: [], initialSelectedNo: busNo)
    }
    func open(_ card: CardModel, busNo: String? = nil) {
        open(stopCode: card.stopCode, label: card.label, busNo: busNo)
    }
    func openNearby(_ stop: NearbyStop, busNo: String? = nil) {
        open(stopCode: stop.stopCode, label: ds.stopName(stop.stopCode),
             busNo: busNo, feedback: false)
    }
    func openFromSearch(stopCode: String) {
        Feedback.shared.success()
        open(stopCode: stopCode, label: ds.stopName(stopCode), feedback: false)
    }
    func pinNearby(_ code: String) { togglePin(code: code) }

    // ─── Real iOS Live Activity (ActivityKit) ─────────────

    /// Single entry point for the Start/Stop toggle: ends the Live Activity if
    /// it's already running for this bus, otherwise starts it.
    func toggleLiveActivity(_ s: Service, stopName: String, stopCode: String) {
        if isLiveActivityActive(s, stopCode: stopCode) { stopLiveActivity() }
        else { startLiveActivity(s, stopName: stopName, stopCode: stopCode) }
    }

    func startLiveActivity(_ s: Service, stopName: String, stopCode: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Live Activities disabled in Settings — nothing to show.
            laLog.error("LA not enabled (Settings → \(s.no))")
            return
        }
        // Only one Live Activity at a time — replace any other bus's.
        if liveActivity != nil { stopLiveActivity() }
        let attrs = LeyneActivityAttributes(busNo: s.no, dest: s.dest,
                                           stopName: stopName, stopCode: stopCode)
        let state = liveState(etaSec: s.etaSec, stopsAway: -1)
        do {
            let act = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            liveActivity = act
            liveActivityKey = Self.liveKey(bus: s.no, stopCode: stopCode)
            liveActivityOn = true
            laLog.notice("LA STARTED id=\(act.id) bus=\(s.no) → \(s.dest)")
            Feedback.shared.select()
            observeLiveActivityEnd(act)
            startLivePolling(busNo: s.no, stopCode: stopCode)
        } catch {
            liveActivity = nil
            liveActivityKey = nil
            liveActivityOn = false
            laLog.error("LA request failed: \(error.localizedDescription)")
        }
    }

    func stopLiveActivity() {
        liveActivityTask?.cancel()
        liveActivityTask = nil
        liveActivityEndObserver?.cancel()
        liveActivityEndObserver = nil
        let act = liveActivity
        liveActivity = nil
        liveActivityKey = nil
        liveActivityOn = false
        Task { await act?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Re-attach to a Live Activity that survived an app relaunch (the OS keeps
    /// showing it), so the in-app Start/Stop state stays correct.
    func restoreLiveActivity() {
        guard liveActivity == nil else { return }
        guard let act = Activity<LeyneActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) else { return }
        liveActivity = act
        liveActivityKey = Self.liveKey(bus: act.attributes.busNo,
                                       stopCode: act.attributes.stopCode)
        liveActivityOn = true
        laLog.notice("LA RESTORED id=\(act.id) bus=\(act.attributes.busNo)")
        observeLiveActivityEnd(act)
        startLivePolling(busNo: act.attributes.busNo,
                         stopCode: act.attributes.stopCode)
    }

    /// Clears in-app state if the activity ends out-of-band (user dismisses it
    /// from the Lock Screen, OS expiry, etc.).
    private func observeLiveActivityEnd(_ act: Activity<LeyneActivityAttributes>) {
        liveActivityEndObserver?.cancel()
        liveActivityEndObserver = Task { [weak self] in
            for await state in act.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await MainActor.run {
                        guard let self, self.liveActivity?.id == act.id else { return }
                        self.liveActivityTask?.cancel()
                        self.liveActivityTask = nil
                        self.liveActivity = nil
                        self.liveActivityKey = nil
                        self.liveActivityOn = false
                    }
                    return
                }
            }
        }
    }

    private func liveState(etaSec: Int, stopsAway: Int)
        -> LeyneActivityAttributes.ContentState {
        let arrived = etaSec <= 0
        let mins = max(0, Int(ceil(Double(etaSec) / 60)))
        let status: String
        if arrived { status = "Bus is here" }
        else if etaSec <= 30 { status = "Now" }
        else if etaSec <= 90 { status = "Arrives in 1 min" }
        else { status = "Arrives in \(mins) min" }
        return .init(etaMinutes: arrived ? 0 : mins, status: status,
                     stopsAway: stopsAway, arrived: arrived)
    }

    /// Polls real LTA every ~15 s and pushes updates into the Live Activity,
    /// then ends it shortly after the bus arrives.
    private func startLivePolling(busNo: String, stopCode: String) {
        liveActivityTask?.cancel()
        liveActivityTask = Task { [weak self] in
            guard let self else { return }
            var routeYou: Int?
            var routeStops: [RouteStopLive] = []
            if let r = await self.ds.route(service: busNo, stopCode: stopCode) {
                routeYou = r.youIndex; routeStops = r.stops
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                guard let snap = await self.ds.liveServiceSnapshot(
                    serviceNo: busNo, stopCode: stopCode) else { continue }
                var stopsAway = -1
                if let you = routeYou, let c = snap.coord, !routeStops.isEmpty {
                    let bi = routeStops.enumerated().min(by: {
                        haversine($0.element.lat, $0.element.lon, c.latitude, c.longitude)
                            < haversine($1.element.lat, $1.element.lon, c.latitude, c.longitude)
                    })?.offset ?? 0
                    stopsAway = max(0, you - bi)
                }
                let state = self.liveState(etaSec: snap.etaSec, stopsAway: stopsAway)
                await self.liveActivity?.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)))
                if snap.etaSec <= 0 {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    await self.liveActivity?.end(
                        ActivityContent(state: state, staleDate: nil),
                        dismissalPolicy: .default)
                    await MainActor.run {
                        self.liveActivityEndObserver?.cancel()
                        self.liveActivityEndObserver = nil
                        self.liveActivity = nil
                        self.liveActivityKey = nil
                        self.liveActivityOn = false
                    }
                    return
                }
            }
        }
    }
}

// MARK: - NotificationsManager
//
// Schedules one-shot local notifications that fire ~60 s before each
// tracked bus's `arrivalDate`. The system delivers them on the Lock Screen
// / as a banner regardless of whether the app is foreground, backgrounded,
// or fully suspended — that's the contract a local UNTimeIntervalTrigger
// provides. Re-arming happens on the AppModel tick: each call re-computes
// the schedule against the latest live data, replaces requests with the
// same identifier (UN's documented behaviour), and cancels orphans whose
// underlying service is no longer tracked.

private let notifLog = Logger(subsystem: "com.leyne.Leyne", category: "Notifications")

@MainActor
final class NotificationsManager {
    static let shared = NotificationsManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// Fire offset before arrival — matches the design's "1 min" framing.
    private let leadSec: TimeInterval = 60

    /// Notifications with an identifier prefixed this way belong to us; lets
    /// the orphan-sweep ignore unrelated requests that may live in the
    /// system's pending queue.
    private let idPrefix = "arrival."

    private func id(stopCode: String, busNo: String) -> String {
        "\(idPrefix)\(stopCode).\(busNo)"
    }

    func currentStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            center.getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Requests `.alert`, `.sound`, and `.timeSensitive` if available — the
    /// commute use-case is exactly what time-sensitive was meant for.
    func requestAuthorization() async -> Bool {
        var opts: UNAuthorizationOptions = [.alert, .sound, .badge]
        if #available(iOS 15.0, *) { opts.insert(.timeSensitive) }
        do {
            let ok = try await center.requestAuthorization(options: opts)
            notifLog.notice("auth requested: granted=\(ok)")
            return ok
        } catch {
            notifLog.error("auth request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Cancels every pending arrival alert we own.
    func clearAll() {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix(self.idPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // ─── Alight (on-bus) alerts ───────────────────────────
    //
    // A separate category from arrival alerts: arrival alerts fire BEFORE
    // boarding (bus is approaching the user's stop); alight alerts fire
    // DURING the ride (user is on the bus, approaching their drop-off).
    // Single active ride at a time — the bus-stop combo would only matter
    // if we supported overlapping rides, which the UX doesn't.

    private let alightIdPrefix = "alight."

    /// One-shot notification scheduled at an absolute fire time. Replaces
    /// any prior alight alert (only one active ride at a time).
    func scheduleAlightAlert(busNo: String, alightStopName: String, fireAt: Date) {
        cancelAlightAlerts()
        let interval = fireAt.timeIntervalSinceNow
        // Must be at least 1 s in the future — UNTimeIntervalNotificationTrigger
        // rejects zero/negative intervals.
        guard interval > 1 else {
            // Fire immediately as a heads-up (the user picked a stop the
            // bus is already at or past the 2-stop threshold).
            let content = alightContent(busNo: busNo, stopName: alightStopName)
            let req = UNNotificationRequest(
                identifier: "\(alightIdPrefix)\(busNo).\(alightStopName)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            center.add(req) { err in
                if let err {
                    notifLog.error("alight schedule (immediate) failed: \(err.localizedDescription)")
                }
            }
            return
        }
        let content = alightContent(busNo: busNo, stopName: alightStopName)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval, repeats: false)
        let req = UNNotificationRequest(
            identifier: "\(alightIdPrefix)\(busNo).\(alightStopName)",
            content: content, trigger: trigger)
        center.add(req) { err in
            if let err {
                notifLog.error("alight schedule failed: \(err.localizedDescription)")
            }
        }
    }

    private func alightContent(busNo: String, stopName: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Alight at \(stopName)"
        content.body = "Bus \(busNo) is approaching your stop — get ready."
        content.threadIdentifier = "alight"
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    func cancelAlightAlerts() {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter {
                $0.hasPrefix(self.alightIdPrefix)
            }
            if !ids.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    /// Recomputes the desired schedule given the live cards and tracked
    /// services. Idempotent: replaces requests with the same id and cancels
    /// any pending arrival alerts that no longer have a tracked service.
    func scheduleArrivalAlerts(pins: [Pin], cards: [CardModel]) {
        var desired: [(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger)] = []
        let now = Date()

        for card in cards {
            guard let pin = pins.first(where: { $0.code == card.stopCode }) else { continue }
            let tracked: Set<String>? = pin.tracked.map(Set.init)

            for s in card.services {
                // Only tracked services are eligible.
                if let tr = tracked, !tr.contains(s.no) { continue }
                guard let arrives = s.arrivalDate else { continue }

                // Fire 60 s before arrival. If we're already inside the
                // 60 s window or past it, skip — too late to warn ahead.
                let fireAt = arrives.addingTimeInterval(-leadSec)
                let interval = fireAt.timeIntervalSince(now)
                guard interval > 1 else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Bus \(s.no) arriving in 1 min"
                content.body = card.walkMin > 0
                    ? "\(card.label) · \(card.walkMin) min walk"
                    : "\(card.label) · head down to the stop"
                content.threadIdentifier = card.stopCode
                content.sound = .default
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: interval, repeats: false)
                desired.append((id: id(stopCode: card.stopCode, busNo: s.no),
                                content: content, trigger: trigger))
            }
        }

        // Cancel orphans first so the system's pending list stays clean,
        // then (re)add the desired set. UN replaces requests with the same
        // identifier, so add-after-add is safe.
        let desiredIds = Set(desired.map(\.id))
        center.getPendingNotificationRequests { reqs in
            let toCancel = reqs.map(\.identifier).filter {
                $0.hasPrefix(self.idPrefix) && !desiredIds.contains($0)
            }
            if !toCancel.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: toCancel)
            }
            for d in desired {
                let req = UNNotificationRequest(identifier: d.id,
                                                content: d.content,
                                                trigger: d.trigger)
                self.center.add(req) { err in
                    if let err {
                        notifLog.error("add \(d.id) failed: \(err.localizedDescription)")
                    }
                }
            }
        }
    }
}

// Phase helper (used by the status string + tests).
enum LAPhase { case tracking, arriving, close, arrived, completed, dismissing }
func phaseFor(eta: Double, postArrivedMs: Double) -> LAPhase {
    if postArrivedMs > 3500 { return .dismissing }
    if postArrivedMs > 1800 { return .completed }
    if eta <= 0 { return .arrived }
    if eta <= 30 { return .close }
    if eta <= 60 { return .arriving }
    return .tracking
}
