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
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

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

    // ─── Bulk paginated fetch ($skip by 500) ──────────────
    private func fetchAllPaged<T: Codable>(_ path: String, _ type: T.Type) async throws -> [T] {
        var out: [T] = []
        var skip = 0
        while true {
            var c = URLComponents(url: LTAConfig.baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
            if skip > 0 { c.queryItems = [URLQueryItem(name: "$skip", value: String(skip))] }
            let page = try await get(c.url!, as: LTAList<T>.self).value
            out += page
            if page.count < LTAConfig.pageSize { break }
            skip += LTAConfig.pageSize
            if skip > 60_000 { break }   // safety bound
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
