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
        try await cachedOrFetch("BusRoutes", "BusRoutes", LTABusRouteDTO.self)
    }
}
