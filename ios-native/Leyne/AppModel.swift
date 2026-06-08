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
    static let nearbyKey = "leyne.nearby.shared"
    static let favsKey = "leyne.favs.shared"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// Minimal pinned-stop record the Home Screen widget reads (it can't see the
/// app's models). One row = one pinnable stop the user can pick in the widget.
struct SharedPinnedStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String    // nickname or resolved stop name
}

/// Last-known nearby stop the Nearby widget reads. The widget refetches live
/// arrivals itself; this carries only what it can't compute without the stop
/// database (name + walking distance). Mirrors WNearbyStop in the extension.
struct SharedNearbyStop: Codable, Identifiable, Hashable {
    let id: String      // bus stop code
    let name: String
    let walkMin: Int
}

/// A favourited service, pre-resolved to a concrete stop + the route's
/// destination so the extension (which has no route/stop DB) can render the
/// Favourite Service widget. Mirrors WFavService in the extension.
struct SharedFavService: Codable, Identifiable, Hashable {
    let no: String
    let stopCode: String
    let stopName: String
    let dest: String
    var id: String { "\(no)#\(stopCode)" }
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
    "2.5.0": WhatsNewEntry(
        headline: "Your bus, all on one screen.",
        items: [
            WhatsNewItem(
                icon: "bus.fill",
                title: "Everything at a glance",
                body: "The bus screen now shows the arrival time, stops away, "
                    + "crowd, deck, the route and a live map together — no "
                    + "scrolling to find what you need."
            ),
            WhatsNewItem(
                icon: "hand.tap.fill",
                title: "Peek a nearby stop",
                body: "Touch and hold a stop in Nearby to preview its live "
                    + "arrivals without opening it."
            ),
            WhatsNewItem(
                icon: "list.number",
                title: "Tidier lists, and fixes",
                body: "Stops now list buses by number, your saved stops stay in "
                    + "Nearby, and the route and map open as clean cards. Plus "
                    + "polish and fixes."
            ),
        ]
    ),
    "2.4.2": WhatsNewEntry(
        headline: "Alerts that fit your trip.",
        items: [
            WhatsNewItem(
                icon: "bell.fill",
                title: "Tell me before it arrives",
                body: "Get a heads-up before your bus reaches your stop — or "
                    + "before it reaches your destination — with the lead time "
                    + "you choose. Find and manage every alert in one place."
            ),
            WhatsNewItem(
                icon: "location.fill",
                title: "Tracking that lines up",
                body: "The bus on the map now matches the stops-away and "
                    + "distance you read, and route progress follows the line "
                    + "all the way to its destination."
            ),
            WhatsNewItem(
                icon: "checkmark.seal",
                title: "Quicker saving and refresh",
                body: "Tap the pin to save a stop or the bus to save a bus, "
                    + "pull down to refresh while tracking a bus, plus polish "
                    + "and fixes."
            ),
        ]
    ),
    "2.4.1": WhatsNewEntry(
        headline: "Clearer arrivals.",
        items: [
            WhatsNewItem(
                icon: "star.fill",
                title: "Your buses, first",
                body: "The Home card now shows the top three buses at each stop "
                    + "— your favourites first, then whatever's arriving soonest."
            ),
            WhatsNewItem(
                icon: "bus.fill",
                title: "A simpler bus view",
                body: "Tracking a bus leads with how far away it is and when it'll "
                    + "arrive; the live map is one tap away when you want it."
            ),
            WhatsNewItem(
                icon: "checkmark.seal",
                title: "Polish and fixes",
                body: "Minor stability and reliability fixes to keep "
                    + "everything quick and dependable."
            ),
        ]
    ),
    "2.4.0": WhatsNewEntry(
        headline: "A brighter, clearer Leyne.",
        items: [
            WhatsNewItem(
                icon: "paintpalette",
                title: "Arrivals you can read at a glance",
                body: "A fresh, colourful look — green means a bus is close, "
                    + "amber means a little wait — so you can see what's coming "
                    + "without reading a single number."
            ),
            WhatsNewItem(
                icon: "person.2.fill",
                title: "See how full the bus is",
                body: "Every arrival now shows whether there are seats, standing "
                    + "room, or it's filling up — so you can decide whether to "
                    + "wait for the next one."
            ),
            WhatsNewItem(
                icon: "star.fill",
                title: "Your favourite stops, one tap away",
                body: "Pinned stops now live in their own Favourites tab, so the "
                    + "places you ride from most are always right there."
            ),
        ]
    ),
    "2.3.3": WhatsNewEntry(
        headline: "Smoother and steadier.",
        items: [
            WhatsNewItem(
                icon: "arrow.clockwise",
                title: "Arrivals that keep themselves fresh",
                body: "Behind-the-scenes work so times and the bottom strip "
                    + "refresh reliably and recover on their own — fewer stale "
                    + "moments, less waiting around."
            ),
            WhatsNewItem(
                icon: "checkmark.seal",
                title: "Polish and fixes",
                body: "Small stability and reliability fixes across the app to "
                    + "keep everything quick and dependable."
            ),
        ]
    ),
    "2.3.2": WhatsNewEntry(
        headline: "Routes both ways, cleaner nights.",
        items: [
            WhatsNewItem(
                icon: "arrow.left.arrow.right",
                title: "See both directions of a route",
                body: "Open any bus and switch between its two directions — "
                    + "there and back — to follow the whole line either way."
            ),
            WhatsNewItem(
                icon: "magnifyingglass",
                title: "Search a bus, see its route",
                body: "Searching a bus number now opens that service's full "
                    + "route, not just a stop — so you can scan every stop it "
                    + "serves."
            ),
            WhatsNewItem(
                icon: "circle.lefthalf.filled",
                title: "A cleaner dark mode",
                body: "Dark mode is now a crisp black-and-white — simpler and "
                    + "easier on the eyes at night."
            ),
        ]
    ),
    "2.3.1": WhatsNewEntry(
        headline: "A fresh new look.",
        items: [
            WhatsNewItem(
                icon: "sparkles",
                title: "A cleaner, calmer design",
                body: "Leyne's been redrawn around a soft, focused look that "
                    + "puts your next arrival front and centre — less clutter, "
                    + "easier to read at a glance on the move."
            ),
            WhatsNewItem(
                icon: "dot.radiowaves.up.forward",
                title: "See which times are live at a glance",
                body: "Live arrivals read crisp and bold, with a quiet "
                    + "freshness dot and a LIVE / ESTIMATED / SCHEDULED tag, so "
                    + "you instantly know how much to trust each time."
            ),
            WhatsNewItem(
                icon: "map.fill",
                title: "An immersive bus view",
                body: "Tap any bus for a full-screen map with a draggable "
                    + "sheet — peek for your ETA and how busy it is, or pull up "
                    + "for alerts and the full route timeline."
            ),
        ]
    ),
    "2.3.0": WhatsNewEntry(
        headline: "Smarter alerts, quicker taps.",
        items: [
            WhatsNewItem(
                icon: "bell.badge",
                title: "Get a heads-up before your stop",
                body: "Pick your drop-off in a bus's route view and Leyne "
                    + "buzzes you about two stops early — so you can look up "
                    + "from your phone and still get off in time."
            ),
            WhatsNewItem(
                icon: "bus.fill",
                title: "Tap a live bus to jump right in",
                body: "Tapping a bus on the Lock Screen, in the Dynamic "
                    + "Island, or on your Home Screen widget now opens that "
                    + "exact bus instead of just the app."
            ),
            WhatsNewItem(
                icon: "mappin.and.ellipse",
                title: "Find stops by postal code",
                body: "Type any 6-digit postal code in Search to list the bus "
                    + "stops nearest that address, within your Settings radius."
            ),
        ]
    ),
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

/// A favourited bus *service* (distinct from a pinned stop). `stop == nil`
/// means "anywhere" — the next arrival on the service's route near you;
/// `stop` set means that bus at that specific stop (with arrival alerts).
/// Drives the Favourites "services" section + the Stops/Services/Bus+Stop
/// filters. Persisted alongside pins.
struct FavService: Codable, Equatable, Identifiable {
    var no: String
    var stop: String?   // nil = anywhere
    var id: String { stop.map { "\(no)#\($0)" } ?? "\(no)#*" }
    var isAnywhere: Bool { stop == nil }
}

@MainActor
final class AppModel: ObservableObject {
    // Haptic feedback (v1.0 carry-over).
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
    //
    // Defaults to `true` so onboarding's notification step + the boot-time
    // fallback can fire the system permission prompt without the user
    // having to discover Settings → Notifications first. Existing
    // installs that already toggled this off (the value is persisted)
    // keep their explicit choice.
    @AppStorage("leyne.notifications") var notificationsEnabled = true

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
    // Persisted favourite services (a bus anywhere, or a bus at a stop).
    @Published var favServices: [FavService] = [] {
        didSet { persistFavServices() }
    }
    // Persisted recent searches
    @Published var recents: [String] = []

    // Persisted stop codes the user has hidden from the Nearby list (via the
    // long-press "Hide From Nearby" action). Filtered out in SoftHomeView and
    // restored from Settings → Hidden stops.
    @Published var hiddenNearby: Set<String> = [] {
        didSet { persistHiddenNearby() }
    }

    // ─── Notification alerts (the redesign's single source of truth) ───
    // Both alert kinds — "notify me when my bus reaches MY STOP" (arrival)
    // and "…MY DESTINATION" (destination) — live here, persisted as JSON.
    // The old `Pin.tracked`-driven arrival path and `activeAlight` destination
    // path are migrated into this list on first load. Alerts are managed via
    // `upsertAlert`/`removeAlert` and are independent of pin/`tracked` card
    // visibility.
    @Published var alerts: [BusAlert] = []

    @Published var tick = 0
    private var timer: AnyCancellable?
    private let ds = DataStore.shared

    init() {
        loadPins()
        loadFavServices()
        loadRecents()
        loadAlerts()
        loadHiddenNearby()
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
    private func loadFavServices() {
        if let d = UserDefaults.standard.data(forKey: "leyne.favServices"),
           let f = try? JSONDecoder().decode([FavService].self, from: d) { favServices = f }
    }
    private func persistFavServices() {
        if let d = try? JSONEncoder().encode(favServices) {
            UserDefaults.standard.set(d, forKey: "leyne.favServices")
        }
        mirrorFavServicesToWidget()
    }
    private func loadHiddenNearby() {
        if let d = UserDefaults.standard.data(forKey: "leyne.hiddenNearby"),
           let h = try? JSONDecoder().decode(Set<String>.self, from: d) {
            hiddenNearby = h
        }
    }
    private func persistHiddenNearby() {
        if let d = try? JSONEncoder().encode(hiddenNearby) {
            UserDefaults.standard.set(d, forKey: "leyne.hiddenNearby")
        }
    }

    /// Hide a stop from the Nearby list ("Hide From Nearby" long-press action).
    func hideFromNearby(code: String) { hiddenNearby.insert(code) }
    /// Restore a previously hidden stop (Settings → Hidden stops).
    func unhideNearby(code: String) { hiddenNearby.remove(code) }

    /// Re-publish the favourite-service snapshot. Called after reference data
    /// finishes loading, when stop names + destinations finally resolve.
    func republishFavServicesToWidget() { mirrorFavServicesToWidget() }

    /// Publishes favourite *services* to the App Group so the Favourite
    /// Service widget can offer them. Only favs anchored to a concrete stop
    /// are widget-eligible — an "anywhere" fav has no stop the extension can
    /// fetch without location, so it stays in-app only. Destination is
    /// resolved here from live route data (the extension can't resolve a
    /// DestinationCode → name).
    private func mirrorFavServicesToWidget() {
        let shared: [SharedFavService] = favServices.compactMap { fav in
            guard let stop = fav.stop else { return nil }       // skip "anywhere"
            let name = { let n = ds.stopName(stop); return n.isEmpty ? stop : n }()
            let dest = ds.servicesFor(stop).first { $0.no == fav.no }?.dest ?? ""
            return SharedFavService(no: fav.no, stopCode: stop, stopName: name, dest: dest)
        }
        if let d = try? JSONEncoder().encode(shared) {
            AppGroup.defaults?.set(d, forKey: AppGroup.favsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // ─── Favourite-service helpers ─────────────────────────
    /// Is this exact (bus, stop?) saved? `stop == nil` checks the anywhere one.
    func isFavService(no: String, stop: String?) -> Bool {
        favServices.contains { $0.no == no && $0.stop == stop }
    }
    /// Toggle a favourite service on/off.
    func toggleFavService(no: String, stop: String?) {
        if let i = favServices.firstIndex(where: { $0.no == no && $0.stop == stop }) {
            favServices.remove(at: i)
        } else {
            favServices.append(FavService(no: no, stop: stop))
        }
    }
    func removeFavService(_ fav: FavService) {
        favServices.removeAll { $0.id == fav.id }
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
    func removeRecent(_ q: String) {
        recents.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        UserDefaults.standard.set(recents, forKey: "leyne.recents")
    }
    func clearRecents() {
        recents = []
        UserDefaults.standard.set(recents, forKey: "leyne.recents")
    }

    // ─── Notification alerts: persistence + migration ─────
    private static let alertsKey = "leyne.alerts"

    /// Loads persisted alerts. On the very first run after this feature
    /// ships (`leyne.alerts` absent) it migrates the pre-existing alert
    /// data — each `Pin.tracked` service becomes an arrival alert, and the
    /// active alight ride becomes a destination alert — so users keep their
    /// arrangements without re-setting them. Best-effort: anything that
    /// can't be resolved is simply skipped.
    private func loadAlerts() {
        if let d = UserDefaults.standard.data(forKey: Self.alertsKey),
           let a = try? JSONDecoder().decode([BusAlert].self, from: d) {
            alerts = a
            return
        }
        migrateLegacyAlerts()
    }

    private func persistAlerts() {
        if let d = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(d, forKey: Self.alertsKey)
        }
    }

    /// One-time migration from the legacy tracked-service + alight model.
    private func migrateLegacyAlerts() {
        var migrated: [BusAlert] = []
        // Tracked services → arrival alerts (lead 1, the old behaviour).
        for pin in pins {
            let name = ds.stopName(pin.code)
            let nos: [String] = pin.tracked
                ?? ds.servicesFor(pin.code).map(\.no)        // nil = all
            for no in nos {
                let dest = ds.servicesFor(pin.code).first { $0.no == no }?.dest ?? ""
                migrated.append(BusAlert(
                    kind: .arrival, busNo: no, stopCode: pin.code,
                    stopName: name.isEmpty ? pin.code : name, dest: dest,
                    boardStopCode: pin.code, leadMinutes: 1))
            }
        }
        // Active alight ride → destination alert (lead 1).
        if let al = activeAlight {
            migrated.append(BusAlert(
                kind: .destination, busNo: al.busNo, stopCode: al.stopCode,
                stopName: al.stopName, dest: "",
                boardStopCode: al.stopCode, leadMinutes: 1))
        }
        alerts = migrated
        persistAlerts()
    }

    // ─── Notification alerts: CRUD ────────────────────────

    /// The alert matching this (kind, bus, stop), or nil.
    func alert(kind: AlertKind, busNo: String, stopCode: String) -> BusAlert? {
        alerts.first { $0.kind == kind && $0.busNo == busNo && $0.stopCode == stopCode }
    }

    /// Adds the alert, or replaces an existing one with the same id. Persists
    /// and re-arms notifications. For destination alerts, pass a `fireAt` so
    /// the one-shot can be scheduled at the absolute computed moment (the
    /// caller — SoftBusView — has the boarding ETA to compute it).
    func upsertAlert(_ alert: BusAlert, fireAt: Date? = nil) {
        if let i = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[i] = alert
        } else {
            alerts.append(alert)
        }
        persistAlerts()
        if alert.kind == .destination, let fireAt {
            NotificationsManager.shared.scheduleDestinationAlert(alert, fireAt: fireAt)
        }
        rearmAlertNotifications()
    }

    /// Removes the alert with this id (and cancels its pending notification).
    func removeAlert(id: String) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        let removed = alerts.remove(at: i)
        persistAlerts()
        NotificationsManager.shared.cancelAlert(removed)
        rearmAlertNotifications()
        // Arrival alerts are paired with a lock-screen Live Activity — SoftBusView's
        // combined affordance starts both together and cancels both together. Any
        // OTHER removal path (Manage alerts swipe/Edit) must end the companion too,
        // or the Live Activity is left running on the lock screen with no in-app way
        // to stop it. Match the running activity by its bus+stop key.
        if removed.kind == .arrival,
           liveActivityKey == Self.liveKey(bus: removed.busNo, stopCode: removed.stopCode) {
            stopLiveActivity()
        }
    }

    /// Removes the alert matching (kind, bus, stop), if any.
    func removeAlerts(kind: AlertKind, busNo: String, stopCode: String) {
        if let a = alert(kind: kind, busNo: busNo, stopCode: stopCode) {
            removeAlert(id: a.id)
        }
    }

    /// Re-computes the arrival schedule from the live data, leaving
    /// destination one-shots (already scheduled at their absolute fire time)
    /// untouched. Called after any alert mutation and on the 10 s tick.
    private func rearmAlertNotifications() {
        guard notificationsEnabled else { return }
        NotificationsManager.shared.scheduleArrivalAlerts(
            alerts: alerts, cards: alertSchedulingCards)
    }

    /// Live cards covering every stop an arrival alert references, so the
    /// scheduler can read each bus's `arrivalDate`. Pinned stops are already
    /// kept fresh by the tick; alert stops that aren't pinned still resolve
    /// from whatever arrivals the DataStore holds.
    private var alertSchedulingCards: [CardModel] {
        let codes = Set(alerts.filter { $0.kind == .arrival }.map(\.stopCode))
        return codes.map { code in
            CardModel(id: code, label: ds.stopName(code), stopName: ds.stopName(code),
                      stopCode: code, walkMin: 0,
                      services: liveServices(code: code, tracked: []))
        }
    }

    func finishOnboarding() {
        onboarded = true
        showOnboarding = false
        // Pin the running version so the What's New screen doesn't fire on
        // the user's very next launch for the version they just installed.
        if let v = currentVersion { lastSeenVersion = v }
    }
    func syncFeedback() { Feedback.shared.config(haptic: haptic) }

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

    /// Arrival-alert ids we've seen with the bus still inbound. Gate for
    /// [clearFulfilledArrivalAlerts] so a freshly-set alert on a bus that's
    /// momentarily at the stop isn't cleared the instant it's created.
    private var arrivalsSeenInbound: Set<String> = []

    /// Removes arrival alerts whose tracked bus has reached the stop. The
    /// bus's locally-computed `etaSec` holds at 0 from arrival until the next
    /// feed refresh, so the per-second tick reliably catches the window. Only
    /// alerts previously seen inbound are cleared (so setting an alert never
    /// removes it on the same tick). `removeAlert` also ends the paired Live
    /// Activity, keeping both surfaces in sync.
    private func clearFulfilledArrivalAlerts() {
        var fulfilled: [String] = []
        for a in alerts where a.kind == .arrival {
            guard let svc = liveServices(code: a.stopCode, tracked: [a.busNo]).first
            else { continue }   // bus not in the feed this tick — wait for it
            if svc.etaSec > 0 {
                arrivalsSeenInbound.insert(a.id)
            } else if arrivalsSeenInbound.contains(a.id) {
                fulfilled.append(a.id)
            }
        }
        for id in fulfilled {
            arrivalsSeenInbound.remove(id)
            removeAlert(id: id)
        }
    }

    // ─── Tick: smooth countdown + keep visible stops fresh ─
    private func onTick() {
        tick &+= 1
        var codes = Set(pins.map(\.code))
        if let c = openCard?.stopCode { codes.insert(c) }
        for c in codes { ds.ensureArrivals(stop: c) }

        // Keep every alert's stop fresh (not just pinned ones) so the
        // scheduler reads current arrivalDates for un-pinned alert stops.
        for a in alerts where a.kind == .arrival { ds.ensureArrivals(stop: a.stopCode) }

        // One-shot arrival alerts: once the tracked bus actually reaches the
        // stop, the alert has done its job — clear it (and its paired Live
        // Activity, via removeAlert) so it doesn't linger in Manage alerts or
        // silently re-arm for the next bus. Matches the Live Activity, which
        // already auto-ends on arrival, and the "Notify me before IT arrives"
        // copy.
        clearFulfilledArrivalAlerts()

        // Reschedule arrival-alert notifications every ~10 s — LTA's
        // arrivalDate values drift, and a coarse cadence is enough since
        // notification fire times are absolute (set via UNTimeIntervalTrigger).
        if notificationsEnabled, tick % 10 == 0 {
            rearmAlertNotifications()
        }

        // Pull MRT/LRT disruption alerts on a slow cadence. The DataStore
        // itself enforces the 60 s gate; tick just gives it a heartbeat.
        ds.refreshTrainAlertsIfStale()
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
                rearmAlertNotifications()
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
            busNo: busNo, alightStopCode: stopCode,
            alightStopName: stopName, fireAt: fireAt)
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

    /// True iff this bus is shown on the stop's Home card (pinned ⟺ ≥1 bus;
    /// nil `tracked` = all shown). This is card *visibility*, independent of
    /// notification alerts — those live in the `alerts` list.
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

    /// Toggle a service on the stop's Home card. Checking on an unpinned stop
    /// pins it; unchecking the last tracked bus unpins it (pinned ⟺ ≥1 bus).
    /// Card visibility only — notification alerts are managed separately via
    /// `upsertAlert`/`removeAlert`.
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
        let state = liveState(etaSec: s.etaSec, stopsAway: -1, monitored: s.monitored)
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

    private func liveState(etaSec: Int, stopsAway: Int, monitored: Bool = true)
        -> LeyneActivityAttributes.ContentState {
        let arrived = etaSec <= 0
        // Floor to whole minutes so the Dynamic Island / Lock Screen numeral
        // matches the app's `fmtETA` (sec / 60). Using ceil here made the Live
        // Activity read one minute higher than SoftBusView for the same ETA.
        let mins = max(0, etaSec / 60)
        // Whisper-quiet: the status reads confidently regardless of `monitored`
        // (no "Scheduled ·" banner). The estimate tell is the "~" in the widget
        // / Live Activity numeral; `monitored` still flows through for that.
        let status: String
        if arrived { status = "Bus is here" }
        else if etaSec <= 30 { status = "Now" }
        else if etaSec <= 90 { status = "Arrives in 1 min" }
        else { status = "Arrives in \(mins) min" }
        return .init(etaMinutes: arrived ? 0 : mins, status: status,
                     stopsAway: stopsAway, arrived: arrived, monitored: monitored)
    }

    // ─── Live Activity polling cadence + safety bounds ────
    private static let kLivePollInterval: UInt64 = 15_000_000_000  // 15 s
    /// Hard backstop on a single activity's lifetime (~60 min). A bus we never
    /// see arrive (wrong match, feed quirk) must not pin a Live Activity to the
    /// lock screen indefinitely.
    private static let kLiveMaxPolls = 240
    /// ETA (seconds) at/under which the tracked bus counts as "close". Once
    /// seen close, a sudden disappearance or ETA jump means it has arrived.
    private static let kLiveCloseSec = 120
    /// Consecutive empty snapshots tolerated before treating the service as
    /// ended (covers brief feed gaps between buses).
    private static let kLiveMaxMisses = 4

    /// Polls real LTA every ~15 s and pushes updates into the Live Activity,
    /// then ends it once the tracked bus arrives.
    ///
    /// Arrival is detected three ways, because LTA almost never reports the
    /// tracked bus at exactly 0 s — it drops it and the feed rolls to the
    /// *following* bus:
    ///   1. ETA reaches 0 (rare, but handled).
    ///   2. After the bus has been close (≤ `kLiveCloseSec`), the ETA jumps far
    ///      UP — the feed rolled to the next bus, i.e. ours just left.
    ///   3. After it's been close, the service vanishes from the feed.
    /// Previously only (1) was checked, so the activity silently re-tracked the
    /// next bus and never cleared — the bug this fixes. The poll cap is the
    /// final backstop.
    private func startLivePolling(busNo: String, stopCode: String) {
        liveActivityTask?.cancel()
        liveActivityTask = Task { [weak self] in
            guard let self else { return }
            var routeYou: Int?
            if let r = await self.ds.route(service: busNo, stopCode: stopCode) {
                routeYou = r.youIndex
            }
            var lastEta = Int.max / 2  // previous poll's ETA (seconds); halved
                                       // so `lastEta + …` can't overflow
            var sawClose = false    // bus has been inside the close window
            var misses = 0          // consecutive empty snapshots
            var polls = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.kLivePollInterval)
                if Task.isCancelled { return }
                polls += 1

                guard let snap = await self.ds.liveServiceSnapshot(
                    serviceNo: busNo, stopCode: stopCode) else {
                    misses += 1
                    // (3) Vanished after being close → it arrived. Vanished
                    // while still far for several polls → service likely ended.
                    if sawClose || misses >= Self.kLiveMaxMisses {
                        await self.finishLiveActivityAsArrived(monitored: true)
                        return
                    }
                    continue
                }
                misses = 0
                let eta = snap.etaSec

                // (2) ETA rolled far up after being close, or (1) hit zero.
                let rolledToNextBus =
                    sawClose && eta > lastEta + Self.kLiveCloseSec && eta > 150
                if eta <= 0 || rolledToNextBus {
                    await self.finishLiveActivityAsArrived(monitored: snap.monitored)
                    return
                }

                if eta <= Self.kLiveCloseSec { sawClose = true }
                lastEta = eta

                // Stops-away MUST match what SoftBusView shows, or the Live
                // Activity (Dynamic Island / Lock Screen) and the app disagree.
                // SoftBusView derives the bus index from the ETA (~90 s/stop),
                // so stopsRemaining ≈ round(etaSec / 90); we replicate that here.
                var stopsAway = -1
                if let you = routeYou {
                    let fromEta = Int((Double(max(0, eta)) / 90.0).rounded())
                    stopsAway = max(0, min(you, fromEta))
                }
                let state = self.liveState(etaSec: eta, stopsAway: stopsAway,
                                           monitored: snap.monitored)
                await self.liveActivity?.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)))

                if polls >= Self.kLiveMaxPolls {
                    await self.finishLiveActivityAsArrived(monitored: snap.monitored)
                    return
                }
            }
        }
    }

    /// Pushes a final "Bus is here" state, holds it briefly on both the Lock
    /// Screen and Dynamic Island, then dismisses IMMEDIATELY so nothing
    /// lingers. `.immediate` clears both surfaces together — `.default` left an
    /// ended activity stuck on the Lock Screen for hours. The activity is
    /// captured up front so a Live Activity started for a different bus during
    /// the 6 s hold isn't ended or cleared by mistake.
    private func finishLiveActivityAsArrived(monitored: Bool) async {
        guard let act = liveActivity else { return }
        let arrived = liveState(etaSec: 0, stopsAway: 0, monitored: monitored)
        await act.update(ActivityContent(state: arrived, staleDate: nil))
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        await act.end(ActivityContent(state: arrived, staleDate: nil),
                      dismissalPolicy: .immediate)
        guard liveActivity?.id == act.id else { return }  // superseded meanwhile
        liveActivityEndObserver?.cancel()
        liveActivityEndObserver = nil
        liveActivityTask = nil
        liveActivity = nil
        liveActivityKey = nil
        liveActivityOn = false
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

    /// Two arrival tiers, mirroring the design: an early heads-up while the
    /// bus is still a few minutes out, then the imminent "arriving soon" nudge
    /// for the final approach. The displayed minutes are derived from these
    /// leads (lead/60), so the copy and the fire time can never drift apart.
    private let imminentLeadSec: TimeInterval = 60     // "arriving soon"
    private let headsUpLeadSec: TimeInterval = 300     // "5 min away"
    /// Don't bother with a heads-up if it would land within this gap of the
    /// imminent nudge — two pings seconds apart is noise, not signal.
    private let minTierGapSec: TimeInterval = 120

    /// Notifications whose identifier carries one of these prefixes belong to
    /// us; the orphan-sweep / clearAll only touch our own requests.
    private let imminentPrefix = "arrival."
    private let headsUpPrefix  = "headsup."
    private var arrivalPrefixes: [String] { [imminentPrefix, headsUpPrefix] }

    /// Destination ("reach my stop") one-shots. Keyed off the BusAlert id.
    private let destinationPrefix = "destination."

    private func imminentId(stopCode: String, busNo: String) -> String {
        "\(imminentPrefix)\(stopCode).\(busNo)"
    }
    private func headsUpId(stopCode: String, busNo: String) -> String {
        "\(headsUpPrefix)\(stopCode).\(busNo)"
    }
    /// Stable per-alert request id. Slashes/@ in the id are fine for UN.
    private func destinationId(_ alert: BusAlert) -> String {
        "\(destinationPrefix)\(alert.busNo).\(alert.stopCode)"
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

    /// Cancels every pending arrival alert we own (both tiers).
    func clearAll() {
        let prefixes = arrivalPrefixes
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { id in
                prefixes.contains { id.hasPrefix($0) }
            }
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
    /// any prior alight alert (only one active ride at a time). The
    /// identifier uses the stop CODE (stable, no spaces or punctuation),
    /// not the user-facing name — names like "Opp Blk 211" contain
    /// characters that make the id awkward to parse downstream.
    func scheduleAlightAlert(busNo: String, alightStopCode: String,
                             alightStopName: String, fireAt: Date) {
        cancelAlightAlerts()
        let identifier = "\(alightIdPrefix)\(busNo).\(alightStopCode)"
        let interval = fireAt.timeIntervalSinceNow
        // Must be at least 1 s in the future — UNTimeIntervalNotificationTrigger
        // rejects zero/negative intervals.
        guard interval > 1 else {
            // Fire immediately as a heads-up (the user picked a stop the
            // bus is already at or past the 2-stop threshold).
            let content = alightContent(busNo: busNo, stopName: alightStopName)
            let req = UNNotificationRequest(
                identifier: identifier,
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
            identifier: identifier,
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
        // For alight, we deep-link to the bus's current detail view —
        // RootView reads `stopCode` from AppModel.activeAlight when this
        // kind fires so the user lands on the right page.
        content.userInfo = [
            "kind": "alight",
            "busNo": busNo,
        ]
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

    /// Recomputes the desired ARRIVAL schedule from the user's alerts and the
    /// live cards. Each arrival alert fires `lead` minutes before its bus's
    /// live ETA at its stop. Idempotent: replaces requests with the same id
    /// and cancels any pending arrival alerts whose alert no longer exists.
    /// Destination one-shots are left alone (scheduled separately, at an
    /// absolute moment, by `scheduleDestinationAlert`).
    func scheduleArrivalAlerts(alerts: [BusAlert], cards: [CardModel]) {
        var desired: [(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger)] = []
        let now = Date()

        let cardByCode = Dictionary(uniqueKeysWithValues:
            cards.map { ($0.stopCode, $0) })

        for alert in alerts where alert.kind == .arrival {
            guard let card = cardByCode[alert.stopCode],
                  let s = card.services.first(where: { $0.no == alert.busNo }),
                  let arrives = s.arrivalDate else { continue }
            let stopLabel = alert.stopName.isEmpty
                ? (card.stopName.isEmpty ? card.label : card.stopName)
                : alert.stopName

            // Fire `lead` minutes before the live ETA. Already inside the
            // window (or arrived) → nothing to schedule this round.
            let fireAt = AlertTiming.arrivalFireAt(arrives, leadMinutes: alert.leadMinutes)
            let interval = fireAt.timeIntervalSince(now)
            guard interval > 1 else { continue }
            desired.append((
                id: imminentId(stopCode: alert.stopCode, busNo: alert.busNo),
                content: arrivalContent(
                    busNo: alert.busNo, stopCode: alert.stopCode, stopName: stopLabel,
                    title: AlertTiming.arrivalTitle(alert.busNo),
                    body: AlertTiming.arrivalBody(stopName: stopLabel,
                                                  leadMinutes: alert.leadMinutes)),
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: interval, repeats: false)))
        }

        // Cancel orphans first so the system's pending list stays clean,
        // then (re)add the desired set. UN replaces requests with the same
        // identifier, so add-after-add is safe. Only arrival prefixes are
        // swept here; destination one-shots are owned by their own path.
        let desiredIds = Set(desired.map(\.id))
        let prefixes = arrivalPrefixes
        center.getPendingNotificationRequests { reqs in
            let toCancel = reqs.map(\.identifier).filter { id in
                prefixes.contains { id.hasPrefix($0) } && !desiredIds.contains(id)
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

    /// Schedules a destination alert as a one-shot at the absolute `fireAt`
    /// the caller computed (boarding ETA + per-segment estimate − lead). The
    /// id is stable per alert, so re-setting replaces in place. Past/near-now
    /// fire times are dropped (UNTimeIntervalNotificationTrigger rejects
    /// intervals ≤ 0); we never fire a "you've already arrived" ping.
    func scheduleDestinationAlert(_ alert: BusAlert, fireAt: Date) {
        let id = destinationId(alert)
        let interval = fireAt.timeIntervalSinceNow
        // Replace any prior instance regardless of whether we reschedule.
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard interval > 1 else { return }
        let content = destinationContent(alert)
        let req = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval, repeats: false))
        center.add(req) { err in
            if let err {
                notifLog.error("destination schedule failed: \(err.localizedDescription)")
            }
        }
    }

    private func destinationContent(_ alert: BusAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = AlertTiming.destinationTitle()
        content.body = AlertTiming.destinationBody(destName: alert.stopName,
                                                   leadMinutes: alert.leadMinutes)
        content.threadIdentifier = "destination"
        content.sound = .default
        content.userInfo = [
            "kind": "destination",
            "stopCode": alert.boardStopCode,
            "busNo": alert.busNo,
        ]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    /// Cancels the pending notification(s) for one alert (used on delete).
    func cancelAlert(_ alert: BusAlert) {
        let id = alert.kind == .arrival
            ? imminentId(stopCode: alert.stopCode, busNo: alert.busNo)
            : destinationId(alert)
        // Arrival also had a legacy heads-up companion in older builds —
        // sweep it too so a deleted arrival alert leaves nothing behind.
        let headsUp = headsUpId(stopCode: alert.stopCode, busNo: alert.busNo)
        center.removePendingNotificationRequests(withIdentifiers: [id, headsUp])
    }

    /// Shared arrival-alert content. Title + body come from `AlertTiming` so
    /// the copy stays identical to the Flutter side and the displayed minutes
    /// can never drift from the scheduling lead. No stops-away parenthetical —
    /// at schedule time we can't guarantee it'll still be true at fire time,
    /// and a wrong "(1 stop away)" reads worse than none
    /// (see feedback_timely_over_honest).
    private func arrivalContent(busNo: String, stopCode: String, stopName: String,
                                title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = stopCode
        content.sound = .default
        // userInfo drives the tap-to-open deep link: LeyneAppDelegate
        // .didReceive reads these and posts a NotificationCenter event that
        // RootView consumes to open the stop's DetailView.
        content.userInfo = [
            "kind": "arrival",
            "stopCode": stopCode,
            "busNo": busNo,
        ]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
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
