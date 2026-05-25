// Live data repository — replaces the old Mock. Pulls everything from LTA.

import Foundation
import CoreLocation
import Combine

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

    /// Warm arrivals for the visible nearby stops so expanding is instant.
    // Warm only the closest few (nearby is distance-sorted) so a user-tapped
    // expand isn't queued behind a 12-request prefetch wave.
    func prefetchNearbyArrivals() {
        for s in nearby.prefix(5) { ensureArrivals(stop: s.stopCode, silent: true) }
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
        return Array(stopByCode.values.filter {
            $0.Description.lowercased().contains(s)
                || $0.RoadName.lowercased().contains(s)
                || $0.BusStopCode.contains(s)
        }
        .sorted { $0.Description < $1.Description }
        .prefix(40))
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
        async -> (etaSec: Int, coord: CLLocationCoordinate2D?)? {
        guard let resp = try? await api.busArrival(stopCode: stopCode, serviceNo: serviceNo),
              let svc = resp.Services.first(where: { $0.ServiceNo == serviceNo }),
              let arr = svc.NextBus.arrivalDate
        else { return nil }
        let eta = max(0, Int(arr.timeIntervalSince(Date())))
        var coord: CLLocationCoordinate2D? = nil
        if let lat = svc.NextBus.lat, let lon = svc.NextBus.lon, lat != 0, lon != 0 {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return (eta, coord)
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
