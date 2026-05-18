// Central app state. Pins are user data (persisted, stop-code keyed);
// all arrivals/stops/routes are live from LTA via DataStore. No mock data.

import SwiftUI
import Combine
import CoreLocation

enum AppTab: String { case home, nearby, settings }

/// A user-pinned stop. `tracked` = service numbers to show (empty = all).
struct Pin: Codable, Equatable {
    var code: String
    var nickname: String
    var tracked: [String] = []
}

@MainActor
final class AppModel: ObservableObject {
    // Tweaks (persisted)
    @AppStorage("lyne.theme")       var themeRaw = "light"
    @AppStorage("lyne.sound")       var sound = true
    @AppStorage("lyne.haptic")      var haptic = true
    @AppStorage("lyne.motion")      var motion = false
    @AppStorage("lyne.searchStyle") var searchStyle = "conservative"
    @AppStorage("lyne.onboarded")   var onboarded = false

    var isDark: Bool { themeRaw == "dark" }
    var t: Theme { isDark ? .dark : .light }

    // Navigation / overlays
    @Published var tab: AppTab = .home
    @Published var launching = true
    @Published var showOnboarding = false
    @Published var showAdd = false
    @Published var searchOpen = false
    @Published var openCard: CardModel? = nil
    @Published var liveActivity: ActivityModel? = nil
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
        if let s = UserDefaults.standard.string(forKey: "lyne.startTab"),
           let initial = AppTab(rawValue: s) { tab = initial }
        syncFeedback()
    }

    // ─── Persistence ──────────────────────────────────────
    private func loadPins() {
        if let d = UserDefaults.standard.data(forKey: "lyne.pins"),
           let p = try? JSONDecoder().decode([Pin].self, from: d) { pins = p }
    }
    private func persistPins() {
        if let d = try? JSONEncoder().encode(pins) {
            UserDefaults.standard.set(d, forKey: "lyne.pins")
        }
    }
    private func loadRecents() {
        recents = UserDefaults.standard.stringArray(forKey: "lyne.recents") ?? []
    }
    func addRecent(_ q: String) {
        let v = q.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        recents.removeAll { $0.caseInsensitiveCompare(v) == .orderedSame }
        recents.insert(v, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: "lyne.recents")
    }

    func finishOnboarding() { onboarded = true; showOnboarding = false }
    func syncFeedback() { Feedback.shared.config(sound: sound, haptic: haptic, motion: motion) }

    // ─── Tick: smooth countdown + keep visible stops fresh ─
    private func onTick() {
        tick &+= 1
        var codes = Set(pins.map(\.code))
        if let c = openCard?.stopCode { codes.insert(c) }
        for c in codes { ds.ensureArrivals(stop: c) }
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
            pins.remove(at: i)
        } else {
            Feedback.shared.success()
            pins.append(Pin(code: code, nickname: ds.stopName(code)))
            markNew(code)
        }
    }
    func togglePinForCard(_ card: CardModel) { togglePin(code: card.stopCode) }

    func addPin(code: String, tracked: [String]) {
        let all = ds.servicesFor(code).map(\.no)
        let norm = (Set(tracked) == Set(all)) ? [] : tracked
        if let i = pins.firstIndex(where: { $0.code == code }) {
            pins[i].tracked = norm
        } else {
            pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: norm))
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

    func trackedSet(forCode code: String) -> [String] { pin(forCode: code)?.tracked ?? [] }

    /// True if `busNo` is shown on Home for this stop.
    func isTracked(code: String, busNo: String) -> Bool {
        guard let p = pin(forCode: code) else { return true }
        return p.tracked.isEmpty || p.tracked.contains(busNo)
    }

    /// Service numbers hidden from the Home card for this stop.
    func hiddenSet(code: String, allNos: [String]) -> Set<String> {
        guard let p = pin(forCode: code), !p.tracked.isEmpty else { return [] }
        return Set(allNos).subtracting(p.tracked)
    }

    /// Toggle a service for Home. Auto-pins the stop if not yet pinned.
    func toggleTracked(code: String, busNo: String, allNos: [String]) {
        if let i = pins.firstIndex(where: { $0.code == code }) {
            var shown = pins[i].tracked.isEmpty ? Set(allNos) : Set(pins[i].tracked)
            if shown.contains(busNo) { shown.remove(busNo) } else { shown.insert(busNo) }
            pins[i].tracked = (shown == Set(allNos)) ? [] : Array(shown)
        } else {
            // not pinned yet → pin with only this service tracked
            pins.append(Pin(code: code, nickname: ds.stopName(code), tracked: [busNo]))
            Feedback.shared.success()
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

    func startLiveActivity(_ s: Service, stopName: String, stopCode: String) {
        liveActivity = ActivityModel(
            busNo: s.no, dest: s.dest, stopName: stopName, stopCode: stopCode,
            etaAtStart: Double(max(20, s.etaSec)), startedAt: Date())
        openCard = nil
    }
}

struct ActivityModel: Equatable {
    var busNo: String
    var dest: String
    var stopName: String
    var stopCode: String
    var etaAtStart: Double
    var startedAt: Date
}
