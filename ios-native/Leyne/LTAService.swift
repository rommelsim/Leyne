// Async LTA DataMall client + on-disk cache for the bulk reference datasets.

import Foundation

enum LTAError: LocalizedError {
    case badResponse(Int)
    case decoding(String)
    var errorDescription: String? {
        switch self {
        case .badResponse(let c): return "LTA returned HTTP \(c)"
        case .decoding(let m): return "Couldn’t read LTA data (\(m))"
        }
    }
}

private struct Cached<T: Codable>: Codable {
    let savedAt: Date
    let items: [T]
}

final class LTAService: @unchecked Sendable {
    static let shared = LTAService()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = true
        // Default is 6 → a prefetch wave + a user-tapped fetch would queue.
        c.httpMaximumConnectionsPerHost = 8
        // Arrivals are live; don't serve them from the URL cache (we keep our
        // own disk cache for the bulk reference datasets).
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Pages fetched concurrently per wave (matches the connection pool).
    private let pageWindow = 6

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(LTAConfig.accountKey, forHTTPHeaderField: "AccountKey")
        r.setValue("application/json", forHTTPHeaderField: "accept")
        return r
    }

    private func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: request(url))
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LTAError.badResponse(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LTAError.decoding(String(describing: error)) }
    }

    // ─── Live: Bus Arrival v3 ─────────────────────────────
    func busArrival(stopCode: String, serviceNo: String? = nil) async throws -> LTAArrivalResponse {
        var c = URLComponents(url: LTAConfig.baseURL.appendingPathComponent("v3/BusArrival"),
                              resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "BusStopCode", value: stopCode)]
        if let s = serviceNo { q.append(URLQueryItem(name: "ServiceNo", value: s)) }
        c.queryItems = q
        return try await get(c.url!, as: LTAArrivalResponse.self)
    }

    // ─── Bulk paginated fetch ($skip by 500), concurrent ──
    // Pages are disjoint slices, so fetch a window of them in parallel
    // instead of strictly sequentially (BusRoutes is ~53 pages — this turns
    // ~53 round-trips into ~9 waves).
    private func pageURL(_ path: String, skip: Int) -> URL {
        var c = URLComponents(url: LTAConfig.baseURL.appendingPathComponent(path),
                              resolvingAgainstBaseURL: false)!
        if skip > 0 { c.queryItems = [URLQueryItem(name: "$skip", value: String(skip))] }
        return c.url!
    }

    private func fetchAllPaged<T: Codable>(_ path: String, _ type: T.Type) async throws -> [T] {
        var out: [T] = []
        var base = 0
        while true {
            let skips = (0..<pageWindow).map { base + $0 * LTAConfig.pageSize }
            let pages = try await withThrowingTaskGroup(of: (Int, [T]).self) { group -> [[T]] in
                for (i, skip) in skips.enumerated() {
                    let url = self.pageURL(path, skip: skip)
                    group.addTask { (i, try await self.get(url, as: LTAList<T>.self).value) }
                }
                var collected = Array(repeating: [T](), count: skips.count)
                for try await (i, page) in group { collected[i] = page }
                return collected
            }
            var reachedEnd = false
            for p in pages {
                out += p
                if p.count < LTAConfig.pageSize { reachedEnd = true }
            }
            if reachedEnd { break }
            base += pageWindow * LTAConfig.pageSize
            if base > 80_000 { break }   // safety bound
        }
        return out
    }

    // ─── Disk cache ───────────────────────────────────────
    private var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LTA", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func loadCache<T: Codable>(_ name: String, _ type: T.Type,
                                       maxAge: TimeInterval) -> [T]? {
        let url = cacheDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(Cached<T>.self, from: data),
              Date().timeIntervalSince(cached.savedAt) < maxAge
        else { return nil }
        return cached.items
    }

    private func saveCache<T: Codable>(_ name: String, _ items: [T]) {
        let url = cacheDir.appendingPathComponent("\(name).json")
        if let data = try? JSONEncoder().encode(Cached(savedAt: Date(), items: items)) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func cachedOrFetch<T: Codable>(_ name: String, _ path: String, _ type: T.Type)
        async throws -> [T]
    {
        if let hit = loadCache(name, type, maxAge: LTAConfig.referenceCacheMaxAge) {
            return hit
        }
        let fresh = try await fetchAllPaged(path, type)
        saveCache(name, fresh)
        return fresh
    }

    func busStops() async throws -> [LTABusStop] {
        try await cachedOrFetch("BusStops", "BusStops", LTABusStop.self)
    }
    func busServices() async throws -> [LTABusServiceDTO] {
        try await cachedOrFetch("BusServices", "BusServices", LTABusServiceDTO.self)
    }
    func busRoutes() async throws -> [LTABusRouteDTO] {
        // Cache key bumped to "BusRoutes2" so existing installs re-fetch once
        // and pick up the first/last-bus columns added to LTABusRouteDTO; the
        // old "BusRoutes.json" cache lacked them and would decode them as nil.
        try await cachedOrFetch("BusRoutes2", "BusRoutes", LTABusRouteDTO.self)
    }

    // ─── Live: Train Service Alerts (MRT/LRT) ─────────────
    /// Always-on endpoint reporting current MRT/LRT line disruptions.
    /// The body's `Status` is 1 (normal) or 2 (disrupted); when normal
    /// `AffectedSegments` and `Message` are empty.
    func trainServiceAlerts() async throws -> LTATrainAlerts {
        let url = LTAConfig.baseURL.appendingPathComponent("TrainServiceAlerts")
        return try await get(url, as: LTATrainAlertResponse.self).value
    }

    // ─── Live: Station Crowd Density (real-time) ──────────
    /// Real-time station crowdedness for one train line. `trainLine` is the
    /// PCD line code (EWL, NSL, NEL, CCL, DTL, TEL, …).
    func stationCrowd(trainLine: String) async throws -> [LTAStationCrowd] {
        var c = URLComponents(url: LTAConfig.baseURL.appendingPathComponent("PCDRealTime"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "TrainLine", value: trainLine)]
        return try await get(c.url!, as: LTAList<LTAStationCrowd>.self).value
    }

    // ─── Live: Facilities Maintenance v2 (lift maintenance)
    /// Network-wide list of MRT-station lifts currently under maintenance.
    func facilitiesMaintenance() async throws -> [LTAFacilityMaintenance] {
        let url = LTAConfig.baseURL.appendingPathComponent("v2/FacilitiesMaintenance")
        return try await get(url, as: LTAList<LTAFacilityMaintenance>.self).value
    }
}

// MARK: - GeocodeService (OneMap postal-code lookup)

/// A geocoded address — the centre point for a postal-code radius search.
struct GeoPlace: Equatable {
    let lat: Double
    let lon: Double
    /// Short human label — building name, or block + road.
    let label: String
    let postalCode: String
}

/// OneMap postal-code geocoding — turns a Singapore 6-digit postal code
/// into a lat/lon + short label. Mirrors lib/services/geocode_service.dart.
/// Uses OneMap's public elastic-search endpoint, which still answers
/// without an API token. Never throws — collapses any network or parse
/// failure to nil so callers handle one case.
final class GeocodeService: @unchecked Sendable {
    static let shared = GeocodeService()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Resolve a 6-digit Singapore postal code to a GeoPlace, or nil.
    func postalCode(_ code: String) async -> GeoPlace? {
        let q = code.trimmingCharacters(in: .whitespaces)
        guard q.count == 6, q.allSatisfy(\.isNumber) else { return nil }
        var c = URLComponents(string: "https://www.onemap.gov.sg/api/common/elastic/search")!
        c.queryItems = [
            URLQueryItem(name: "searchVal", value: q),
            URLQueryItem(name: "returnGeom", value: "Y"),
            URLQueryItem(name: "getAddrDetails", value: "Y"),
            URLQueryItem(name: "pageNum", value: "1"),
        ]
        guard let url = c.url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  !results.isEmpty
            else { return nil }
            // Prefer an entry whose POSTAL matches exactly; fall back to first.
            let row = results.first(where: { ($0["POSTAL"] as? String) == q })
                ?? results[0]
            guard let latStr = row["LATITUDE"] as? String,
                  let lonStr = row["LONGITUDE"] as? String,
                  let lat = Double(latStr),
                  let lon = Double(lonStr)
            else { return nil }
            return GeoPlace(lat: lat, lon: lon, label: Self.labelFrom(row), postalCode: q)
        } catch {
            return nil
        }
    }

    /// Building name when it's real, else block + road. OneMap uses "NIL"
    /// for "no building name".
    private static func labelFrom(_ row: [String: Any]) -> String {
        func field(_ k: String) -> String {
            ((row[k] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        }
        let building = field("BUILDING")
        if !building.isEmpty, building.uppercased() != "NIL" {
            return titleCase(building)
        }
        let parts = [field("BLK_NO"), field("ROAD_NAME")].filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? "Singapore" : titleCase(joined)
    }

    /// OneMap returns ALL-CAPS strings; soften to Title Case for display.
    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            guard let first = word.first else { return "" }
            return first.uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
