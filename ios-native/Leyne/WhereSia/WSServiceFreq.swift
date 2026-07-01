// WhereSia — bus service frequency loader.
//
// The shared LTAService caches BusServices without the frequency columns, so
// the Service Info screen loads them here on demand: page the BusServices
// endpoint (with the freq fields), cache to disk for a week, and index by
// service number. Self-contained — reuses only LTAConfig, never invents data.

import Foundation

/// One service's operating category + frequency bands (raw LTA "8-12" strings).
struct WSServiceFreq: Codable, Equatable {
    let serviceNo: String
    let category: String?
    let amPeak: String?
    let amOffpeak: String?
    let pmPeak: String?
    let pmOffpeak: String?

    /// "8-12" → "8–12 min"; blank / "-" → "—".
    static func band(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s != "-" else { return "—" }
        return s.replacingOccurrences(of: "-", with: "–") + " min"
    }
}

actor WSServiceFreqStore {
    static let shared = WSServiceFreqStore()

    private var index: [String: WSServiceFreq]?

    private struct DTO: Codable {
        let ServiceNo: String
        let Category: String?
        let AM_Peak_Freq: String?
        let AM_Offpeak_Freq: String?
        let PM_Peak_Freq: String?
        let PM_Offpeak_Freq: String?
    }
    private struct Page: Codable { let value: [DTO] }
    private struct Cached: Codable { let savedAt: Date; let items: [WSServiceFreq] }

    private var cacheURL: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LTA", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("WSBusServicesFreq.json")
    }

    /// Frequency for a service (first direction encountered), or nil.
    func freq(for serviceNo: String) async -> WSServiceFreq? {
        if index == nil { await loadIndex() }
        return index?[serviceNo]
    }

    private func loadIndex() async {
        if let items = loadCache() {
            index = Dictionary(items.map { ($0.serviceNo, $0) }) { a, _ in a }
            return
        }
        let items = (try? await fetchAll()) ?? []
        // One row per service (both directions carry the same freq bands).
        index = Dictionary(items.map { ($0.serviceNo, $0) }) { a, _ in a }
        if !items.isEmpty { saveCache(items) }
    }

    private func fetchAll() async throws -> [WSServiceFreq] {
        var out: [WSServiceFreq] = []
        var skip = 0
        while true {
            var c = URLComponents(url: LTAConfig.baseURL.appendingPathComponent("BusServices"),
                                  resolvingAgainstBaseURL: false)!
            if skip > 0 { c.queryItems = [URLQueryItem(name: "$skip", value: String(skip))] }
            var r = URLRequest(url: c.url!)
            r.setValue(LTAConfig.accountKey, forHTTPHeaderField: "AccountKey")
            r.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, _) = try await URLSession.shared.data(for: r)
            let page = try JSONDecoder().decode(Page.self, from: data)
            out += page.value.map {
                WSServiceFreq(serviceNo: $0.ServiceNo, category: $0.Category,
                              amPeak: $0.AM_Peak_Freq, amOffpeak: $0.AM_Offpeak_Freq,
                              pmPeak: $0.PM_Peak_Freq, pmOffpeak: $0.PM_Offpeak_Freq)
            }
            if page.value.count < LTAConfig.pageSize { break }
            skip += LTAConfig.pageSize
            if skip > 20_000 { break }
        }
        return out
    }

    private func loadCache() -> [WSServiceFreq]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              Date().timeIntervalSince(cached.savedAt) < LTAConfig.referenceCacheMaxAge
        else { return nil }
        return cached.items
    }

    private func saveCache(_ items: [WSServiceFreq]) {
        if let data = try? JSONEncoder().encode(Cached(savedAt: Date(), items: items)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
