// Live data repository — replaces the old Mock. Pulls everything from LTA.

import Foundation
import CoreLocation
import Combine
import WidgetKit

enum LoadState: Equatable {
    case loading, ready, error(String)
}

enum ArrivalState: Equatable {
    case loading
    case loaded([Service])
    case empty            // no estimates / not in operation
    case error(String)
}

struct RouteStopLive: Identifiable, Equatable {
    let code: String
    let name: String
    let lat: Double
    let lon: Double
    let seq: Int
    var id: String { code }
}

struct RouteInfo: Equatable {
    var stops: [RouteStopLive]
    var youIndex: Int
    var busIndex: Int?           // nearest route stop to the live bus
    var busCoord: CLLocationCoordinate2D?

    static func == (a: RouteInfo, b: RouteInfo) -> Bool {
        a.stops == b.stops && a.youIndex == b.youIndex && a.busIndex == b.busIndex
            && a.busCoord?.latitude == b.busCoord?.latitude
            && a.busCoord?.longitude == b.busCoord?.longitude
    }
}

/// One direction of a service (LTA Direction 1 or 2): the full ordered stop
/// list, where the anchor stop sits in it, and whether the anchor is in this
/// direction at all. A bus service almost always runs two directions
/// (origin→terminus and back), so the Bus view offers a toggle between them.
/// First/last bus clock times at a stop, per service day. Strings are raw LTA
/// "HHmm" (e.g. "0530"; LTA encodes past-midnight as "24xx"/"25xx"). The view
/// picks today's pair and formats it for the user's 12/24-h preference.
struct OperatingWindow: Equatable {
    let firstWD: String?,  lastWD: String?
    let firstSat: String?, lastSat: String?
    let firstSun: String?, lastSun: String?
}

struct RouteDirection: Equatable {
    /// LTA `Direction` value (1 or 2).
    let direction: Int
    let stops: [RouteStopLive]

    /// Index of the anchor stop in `stops` (0 when the anchor isn't in this
    /// direction — see `anchorPresent`).
    let youIndex: Int

    /// Whether the anchor stopCode actually appears in this direction. False for
    /// the "other" direction when the view was opened from a specific stop.
    let anchorPresent: Bool

    /// First/last bus at the anchor (boarding) stop in this direction, when the
    /// BusRoutes feed carried it. nil for the non-anchor direction.
    var firstLast: OperatingWindow? = nil

    var originName: String { stops.first?.name ?? "" }
    var destinationName: String { stops.last?.name ?? "" }
}

/// A service's complete route across all directions. `initialIndex` is the
/// direction whose stop list contains the anchor stop (so opening from a stop
/// preselects the right way round); falls back to 0.
struct ServiceRoute: Equatable {
    let serviceNo: String
    let directions: [RouteDirection]
    let initialIndex: Int
}

/// MRT/LRT line disruption surfaced on the Home screen. Built from LTA's
/// TrainServiceAlerts response — one entry per affected segment so a
/// multi-line incident renders as multiple cards.
struct TrainAlert: Identifiable, Equatable {
    /// Stable per-line id so SwiftUI ForEach + Set-based dismissals key
    /// off "the NEL alert" rather than the message text.
    let id: String
    /// LTA's line code as returned (e.g. "NEL", "EWL").
    let lineCode: String
    /// Mapped palette entry; nil for lines we haven't catalogued yet.
    let line: MRTLine?
    /// Header shown on the card — "NE Line · disrupted".
    let title: String
    /// Body text — a trimmed single-sentence summary of the LTA message.
    let detail: String
}

/// The relevant slice of the route to draw on the map: from the bus's current
/// position (or an approach window if it's passed/unknown) to just past your
/// stop. Drawing the *whole* route connects 40–60 stops incl. loops with
/// straight lines (LTA has no road geometry) → the tangled "weird waypoint".
func journeySegment(_ r: RouteInfo) -> [RouteStopLive] {
    guard !r.stops.isEmpty else { return [] }
    let you = min(max(r.youIndex, 0), r.stops.count - 1)
    let start: Int
    if let b = r.busIndex, b >= 0, b <= you { start = b }
    else { start = max(0, you - 6) }
    let end = min(r.stops.count - 1, you + 1)
    guard start <= end else { return [r.stops[you]] }
    return Array(r.stops[start...end])
}

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var referenceState: LoadState = .loading
    @Published var nearby: [NearbyStop] = []
    @Published var arrivals: [String: ArrivalState] = [:]
    @Published var routesLoaded = false
    /// MRT/LRT line disruptions, refreshed periodically by AppModel's tick.
    /// Empty means no disruptions; the Home page renders one card per item.
    @Published var trainAlerts: [TrainAlert] = []
    private var lastTrainAlertFetch: Date?

    private(set) var stopByCode: [String: LTABusStop] = [:]
    private var services: [LTABusServiceDTO] = []
    private var routesAll: [LTABusRouteDTO]?
    /// Last successful arrival fetch per stop. Exposed via `lastRefresh(_:)`
    /// so UI surfaces (the Home freshness dot, per-stop staleness chips)
    /// can render a confidence signal without re-implementing the cache.
    @Published private(set) var lastFetched: [String: Date] = [:]
    private var inflight: Set<String> = []
    private var lastLoc: CLLocation?

    /// Returns the timestamp of the most recent successful arrival fetch
    /// for `code`, or nil if we've never fetched it.
    func lastRefresh(_ code: String) -> Date? { lastFetched[code] }

    /// The newest fetch across any of `codes` — used to drive the global
    /// freshness indicator on the Home screen, which reflects the *most
    /// recently confirmed* data the user might be looking at.
    func newestRefresh(amongst codes: [String]) -> Date? {
        codes.compactMap { lastFetched[$0] }.max()
    }

    private let api = LTAService.shared

    // ─── Bootstrap reference data ─────────────────────────
    func bootstrap() async {
        if case .ready = referenceState { return }
        referenceState = .loading
        do {
            async let stops = api.busStops()
            async let svcs = api.busServices()
            let (s, v) = try await (stops, svcs)
            stopByCode = Dictionary(s.map { ($0.BusStopCode, $0) }) { a, _ in a }
            services = v
            referenceState = .ready
            if let loc = lastLoc { updateNearby(loc) }
        } catch {
            referenceState = .error((error as? LTAError)?.errorDescription
                                    ?? error.localizedDescription)
        }
    }

    func stopName(_ code: String) -> String {
        stopByCode[code].map { $0.Description } ?? code
    }
    func roadName(_ code: String) -> String {
        stopByCode[code]?.RoadName ?? ""
    }

    // ─── Train service alerts ─────────────────────────────
    /// Refresh MRT/LRT alerts from LTA. AppModel's per-second tick calls
    /// this; the inner gate keeps us at one network hit per 60 s.
    func refreshTrainAlertsIfStale(force: Bool = false) {
        if !force,
           let last = lastTrainAlertFetch,
           Date().timeIntervalSince(last) < 60 { return }
        lastTrainAlertFetch = Date()
        Task { await self.fetchTrainAlerts() }
    }

    private func fetchTrainAlerts() async {
        do {
            let r = try await api.trainServiceAlerts()
            let alerts: [TrainAlert] = (r.Status == 2)
                ? r.AffectedSegments.map { seg in
                    TrainAlert(
                        id: seg.Line,
                        lineCode: seg.Line,
                        line: MRTLine.from(ltaCode: seg.Line),
                        title: "\(MRTLine.shortLabel(forLta: seg.Line)) · disrupted",
                        detail: trainAlertSummary(
                            seg: seg, messages: r.Message))
                }
                : []
            // Don't bounce equal arrays through @Published — keeps the
            // Home re-render quiet when nothing changed.
            if alerts != trainAlerts { trainAlerts = alerts }
        } catch {
            // Network failures here are routine; we keep the previous
            // snapshot rather than blanking the cards out.
        }
    }

    /// Pluck the first matching `Message.Content` for the segment, trim
    /// to a single sentence, and fall back to a generic note if LTA
    /// returned segments without paired messages.
    private func trainAlertSummary(
        seg: LTAAffectedSegment, messages: [LTATrainMessage]
    ) -> String {
        let raw = messages.first { $0.Content.contains(seg.Line) }?.Content
            ?? messages.first?.Content
            ?? "Service disruption — tap to dismiss"
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        // Cut at the first full stop so the card stays one line tall.
        if let dot = trimmed.firstIndex(of: ".") {
            return String(trimmed[..<dot]) + " · tap to dismiss"
        }
        return trimmed + " · tap to dismiss"
    }

    // ─── Nearby ───────────────────────────────────────────
    func updateNearby(_ loc: CLLocation) {
        lastLoc = loc
        guard !stopByCode.isEmpty else { return }
        let here = loc.coordinate
        let ranked = stopByCode.values.map { s -> (LTABusStop, Double) in
            (s, haversine(here.latitude, here.longitude, s.Latitude, s.Longitude))
        }
        .sorted { $0.1 < $1.1 }
        .prefix(12)

        nearby = ranked.map { s, d in
            NearbyStop(
                id: s.BusStopCode,
                stopName: s.Description,
                stopCode: s.BusStopCode,
                distanceM: Int(d.rounded()),
                walkMin: max(1, Int((d / 80).rounded())),   // ~5 km/h
                services: servicesFor(s.BusStopCode)
            )
        }
        mirrorNearbyToWidget()
    }

    /// Publishes the closest few stops to the App Group for the Nearby widget.
    /// Guarded by the stop set: location ticks every few metres, but the
    /// widget only cares when the *stops* change — re-publishing (and waking
    /// WidgetKit) on every GPS jitter would be wasteful and throttled anyway.
    private var lastPublishedNearby: [String] = []
    private func mirrorNearbyToWidget() {
        let top = nearby.prefix(6)
        let codes = top.map(\.stopCode)
        guard codes != lastPublishedNearby else { return }
        lastPublishedNearby = codes
        let shared = top.map {
            SharedNearbyStop(id: $0.stopCode, name: $0.stopName, walkMin: $0.walkMin)
        }
        if let d = try? JSONEncoder().encode(Array(shared)) {
            AppGroup.defaults?.set(d, forKey: AppGroup.nearbyKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // ─── Live arrivals ────────────────────────────────────
    func servicesFor(_ code: String) -> [Service] {
        if case .loaded(let s) = arrivals[code] { return s }
        return []
    }

    /// `silent` warms data without publishing a `.loading` state (used by
    /// prefetch so entering Nearby doesn't burst-republish the whole list).
    func ensureArrivals(stop code: String, force: Bool = false, silent: Bool = false) {
        let fresh = lastFetched[code].map {
            Date().timeIntervalSince($0) < LTAConfig.arrivalRefreshSeconds
        } ?? false
        if !force, fresh, case .loaded = arrivals[code] { return }
        if inflight.contains(code) { return }
        inflight.insert(code)
        if !silent, arrivals[code] == nil { arrivals[code] = .loading }

        Task { [weak self] in
            guard let self else { return }
            do {
                let resp = try await self.api.busArrival(stopCode: code)
                let mapped: [Service] = resp.Services.compactMap { svc in
                    guard svc.NextBus.hasData else { return nil }
                    let destCode = svc.NextBus.DestinationCode ?? ""
                    return svc.toService(destName: self.stopName(destCode))
                }
                .sorted { $0.etaSec < $1.etaSec }
                self.arrivals[code] = mapped.isEmpty ? .empty : .loaded(mapped)
                self.lastFetched[code] = Date()
            } catch {
                if self.arrivals[code] == nil || self.arrivals[code] == .loading {
                    self.arrivals[code] = .error(
                        (error as? LTAError)?.errorDescription ?? "Couldn’t reach LTA")
                }
            }
            self.inflight.remove(code)
        }
    }

    /// Async force-refresh for pull-to-refresh. Unlike `ensureArrivals`,
    /// this awaits the LTA round-trip so SwiftUI's `.refreshable` keeps the
    /// spinner up until fresh data actually lands. Bypasses the freshness
    /// window and the in-flight guard — a deliberate user pull always hits
    /// the network.
    func refreshArrivals(stop code: String) async {
        inflight.remove(code)
        do {
            let resp = try await api.busArrival(stopCode: code)
            let mapped: [Service] = resp.Services.compactMap { svc in
                guard svc.NextBus.hasData else { return nil }
                let destCode = svc.NextBus.DestinationCode ?? ""
                return svc.toService(destName: self.stopName(destCode))
            }
            .sorted { $0.etaSec < $1.etaSec }
            arrivals[code] = mapped.isEmpty ? .empty : .loaded(mapped)
            lastFetched[code] = Date()
        } catch {
            if arrivals[code] == nil || arrivals[code] == .loading {
                arrivals[code] = .error(
                    (error as? LTAError)?.errorDescription ?? "Couldn’t reach LTA")
            }
        }
    }

    /// Warm arrivals for ALL visible nearby stops so every card shows its live
    /// buses up front, without the user having to open each stop first.
    ///
    /// This used to warm only the closest 5 to avoid a request burst, but that
    /// left every card past the 5th showing "No live arrivals right now" until
    /// it was opened (opening a stop calls `ensureArrivals` for it, which is
    /// why a visited stop filled in on return). The `inflight` + `lastFetched`
    /// freshness guards in `ensureArrivals` dedupe repeat calls, and each fetch
    /// is its own concurrent `Task`, so a user-tapped stop is never queued
    /// behind the wave. `nearby` is already capped at 12.
    func prefetchNearbyArrivals() {
        for s in nearby { ensureArrivals(stop: s.stopCode, silent: true) }
    }

    // ─── Search (Buses + Stops, both live) ────────────────
    func searchServices(_ q: String) -> [LTABusServiceDTO] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return [] }
        var seen = Set<String>()
        return services.filter {
            $0.ServiceNo.lowercased().contains(s) && seen.insert($0.ServiceNo).inserted
        }
    }
    func searchStops(_ q: String) -> [LTABusStop] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return [] }
        // Token match: every query word must appear in the stop's text (any
        // order), after normalising synonyms — so "yio chu kang mrt" finds
        // "Yio Chu Kang Stn", and "clementi interchange" finds "Clementi Int".
        let queryTokens = Self.searchTokens(s)
        return Array(stopByCode.values.filter { stop in
            if stop.BusStopCode.contains(s) { return true }
            let hay = Self.searchTokens("\(stop.Description) \(stop.RoadName)")
            return queryTokens.allSatisfy { qt in hay.contains { $0.contains(qt) } }
        }
        .sorted { $0.Description < $1.Description }
        .prefix(40))
    }

    /// Synonym-normalised search tokens. Maps the words LTA never uses in stop
    /// names (mrt / station / interchange / lrt) onto the ones it does (stn /
    /// int), and splits on any non-alphanumeric separator.
    static func searchTokens(_ s: String) -> [String] {
        let synonyms: [String: String] = [
            "mrt": "stn", "station": "stn", "stn": "stn", "lrt": "stn",
            "interchange": "int", "int": "int", "intg": "int",
        ]
        return s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { synonyms[$0] ?? $0 }
    }
    /// First stop served by a service (its route origin), for bus-result taps.
    func originStop(ofService no: String) async -> LTABusStop? {
        guard let routes = await loadRoutes() else { return nil }
        let first = routes
            .filter { $0.ServiceNo == no }
            .sorted { $0.StopSequence < $1.StopSequence }
            .first
        return first.flatMap { stopByCode[$0.BusStopCode] }
    }

    // ─── Routes (lazy, big dataset, disk-cached) ──────────
    func loadRoutes() async -> [LTABusRouteDTO]? {
        if let r = routesAll { return r }
        do {
            let r = try await api.busRoutes()
            routesAll = r
            routesLoaded = true
            return r
        } catch { return nil }
    }

    /// Fire-and-forget version of loadRoutes — kicks off the load if not yet
    /// cached, returns immediately. Used by Nearby so service chips on each
    /// row can populate without awaiting in SwiftUI body.
    func ensureRoutes() {
        guard routesAll == nil else { return }
        Task { _ = await loadRoutes() }
    }

    /// Service numbers that stop here, derived from the static routes
    /// dataset (independent of whether live arrivals have come in yet).
    /// Returns sorted, de-duplicated. Empty until routes finish loading.
    func servicesAtStop(_ code: String) -> [String] {
        guard let routes = routesAll else { return [] }
        var set = Set<String>()
        for r in routes where r.BusStopCode == code {
            set.insert(r.ServiceNo)
        }
        return set.sorted { a, b in
            let na = Int(a.filter(\.isNumber)) ?? Int.max
            let nb = Int(b.filter(\.isNumber)) ?? Int.max
            if na != nb { return na < nb }
            return a < b
        }
    }

    func route(service no: String, stopCode: String) async -> RouteInfo? {
        guard let all = await loadRoutes() else { return nil }
        // Pick the direction whose stop list contains this stop.
        let forSvc = all.filter { $0.ServiceNo == no }
        let dirs = Set(forSvc.map { $0.Direction })
        var chosen: [LTABusRouteDTO] = []
        for d in dirs.sorted() {
            let seq = forSvc.filter { $0.Direction == d }
                .sorted { $0.StopSequence < $1.StopSequence }
            if seq.contains(where: { $0.BusStopCode == stopCode }) { chosen = seq; break }
            if chosen.isEmpty { chosen = seq }
        }
        guard !chosen.isEmpty else { return nil }
        let stops: [RouteStopLive] = chosen.compactMap { r in
            guard let s = stopByCode[r.BusStopCode] else { return nil }
            return RouteStopLive(code: s.BusStopCode, name: s.Description,
                                 lat: s.Latitude, lon: s.Longitude, seq: r.StopSequence)
        }
        let youIdx = stops.firstIndex { $0.code == stopCode } ?? 0
        return RouteInfo(stops: stops, youIndex: youIdx, busIndex: nil, busCoord: nil)
    }

    /// All directions of `service` (typically two — there and back), each with
    /// its ordered stops. When `stopCode` is given, the matching direction is
    /// flagged `anchorPresent` and chosen as `initialIndex`. Drives the Bus
    /// view's direction toggle. Nil when routes can't load or the service is
    /// unknown.
    func serviceRoute(service no: String, stopCode: String?) async -> ServiceRoute? {
        guard let all = await loadRoutes() else { return nil }
        let forSvc = all.filter { $0.ServiceNo == no }
        guard !forSvc.isEmpty else { return nil }
        let dirs = Set(forSvc.map { $0.Direction }).sorted()
        var directions: [RouteDirection] = []
        for d in dirs {
            let seq = forSvc.filter { $0.Direction == d }
                .sorted { $0.StopSequence < $1.StopSequence }
            let stops: [RouteStopLive] = seq.compactMap { r in
                guard let s = stopByCode[r.BusStopCode] else { return nil }
                return RouteStopLive(code: s.BusStopCode, name: s.Description,
                                     lat: s.Latitude, lon: s.Longitude, seq: r.StopSequence)
            }
            guard !stops.isEmpty else { continue }
            let youIdx: Int
            if let code = stopCode {
                youIdx = stops.firstIndex(where: { $0.code == code }) ?? -1
            } else {
                youIdx = -1
            }
            // First/last bus at the boarding stop (this direction only).
            var window: OperatingWindow? = nil
            if let code = stopCode, youIdx >= 0,
               let row = seq.first(where: { $0.BusStopCode == code }) {
                window = OperatingWindow(
                    firstWD: row.WD_FirstBus,   lastWD: row.WD_LastBus,
                    firstSat: row.SAT_FirstBus, lastSat: row.SAT_LastBus,
                    firstSun: row.SUN_FirstBus, lastSun: row.SUN_LastBus)
            }
            directions.append(RouteDirection(
                direction: d,
                stops: stops,
                youIndex: youIdx < 0 ? 0 : youIdx,
                anchorPresent: youIdx >= 0,
                firstLast: window
            ))
        }
        guard !directions.isEmpty else { return nil }
        let initial = directions.firstIndex(where: { $0.anchorPresent }) ?? 0
        return ServiceRoute(serviceNo: no, directions: directions, initialIndex: initial)
    }

    /// Live position of the next bus of `service` approaching `stopCode`.
    func liveBus(service no: String, stopCode: String) async -> CLLocationCoordinate2D? {
        guard let resp = try? await api.busArrival(stopCode: stopCode, serviceNo: no),
              let svc = resp.Services.first(where: { $0.ServiceNo == no }),
              let lat = svc.NextBus.lat, let lon = svc.NextBus.lon,
              lat != 0, lon != 0
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Live snapshot for one service at a stop — used by the Live Activity to
    /// poll the real ETA + bus position (no mock/elapsed-time simulation).
    func liveServiceSnapshot(serviceNo: String, stopCode: String)
        async -> (etaSec: Int, coord: CLLocationCoordinate2D?, monitored: Bool)? {
        guard let resp = try? await api.busArrival(stopCode: stopCode, serviceNo: serviceNo),
              let svc = resp.Services.first(where: { $0.ServiceNo == serviceNo }),
              let arr = svc.NextBus.arrivalDate
        else { return nil }
        let eta = max(0, Int(arr.timeIntervalSince(Date())))
        var coord: CLLocationCoordinate2D? = nil
        if let lat = svc.NextBus.lat, let lon = svc.NextBus.lon, lat != 0, lon != 0 {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        // Absent Monitored ⟶ live (LTA only emits 0 when it genuinely has no
        // GPS), matching the convention used in LTAModels.
        let monitored = (svc.NextBus.Monitored ?? 1) == 1
        return (eta, coord, monitored)
    }
}

func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let R = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat/2) * sin(dLat/2)
        + cos(lat1 * .pi/180) * cos(lat2 * .pi/180) * sin(dLon/2) * sin(dLon/2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}
