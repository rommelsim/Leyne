// MrtGeo — bundled MRT/LRT station geo dataset loader and proximity helpers.
// No UI. Used by SoftMrtView (Phase 2), SoftSearchView, and the nearest-
// stations widget path.

import CoreLocation
import Foundation

// MARK: - Model

struct MrtGeoStation: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let codes: [String]
    let lat: Double
    let lon: Double

    /// Stable identity — all line codes concatenated plus the station name.
    /// Interchange stations carry multiple codes (e.g. "EW13-NS25City Hall"),
    /// so this stays unique even across future dataset updates.
    var id: String { codes.joined(separator: "-") + name }
}

// MARK: - Dataset loader

/// Lazily loads and caches the bundled `MrtStationsGeo.json` once per process
/// lifetime. All lookups and proximity queries go through `MrtGeo.all`.
enum MrtGeo {
    /// All 181 SG MRT/LRT stations, decoded once and kept in memory.
    /// Returns `[]` if the bundle resource is absent or malformed — callers
    /// should treat an empty array as a degraded-but-not-crashed state.
    static let all: [MrtGeoStation] = {
        guard let url = Bundle.main.url(forResource: "MrtStationsGeo",
                                        withExtension: "json") else {
            assertionFailure("MrtStationsGeo.json missing from app bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([MrtGeoStation].self, from: data)
        } catch {
            assertionFailure("MrtStationsGeo.json decode failed: \(error)")
            return []
        }
    }()

    // MARK: - Proximity

    /// Returns the `limit` nearest stations to `coord`, sorted by ascending
    /// distance. Each result includes the haversine distance in metres and a
    /// walking-time estimate at ~5 km/h (same formula as `DataStore.updateNearby`).
    ///
    /// - Parameters:
    ///   - coord: The reference coordinate (typically the user's location).
    ///   - limit: Maximum results to return (default 6).
    ///   - withinMeters: When non-nil, only stations at or closer than this
    ///     distance are included. Stations beyond the radius are excluded entirely
    ///     (callers handle the empty-list case themselves).
    static func nearestStations(
        to coord: CLLocationCoordinate2D,
        limit: Int = 6,
        withinMeters radius: Int? = nil
    ) -> [(station: MrtGeoStation, distanceM: Int, walkMin: Int)] {
        all
            .map { station -> (MrtGeoStation, Int, Int) in
                let d = haversine(coord.latitude, coord.longitude,
                                  station.lat, station.lon)
                let distM = Int(d.rounded())
                let walk = max(1, Int((d / 80).rounded()))
                return (station, distM, walk)
            }
            .sorted { $0.1 < $1.1 }
            .filter { radius == nil || $0.1 <= radius! }
            .prefix(limit)
            .map { ($0.0, $0.1, $0.2) }
    }

    /// Returns the single nearest station to `coord` regardless of distance.
    /// Used to provide the "nearest outside radius" hint in empty states.
    static func nearestStation(
        to coord: CLLocationCoordinate2D
    ) -> (station: MrtGeoStation, distanceM: Int, walkMin: Int)? {
        all
            .map { station -> (MrtGeoStation, Int, Int) in
                let d = haversine(coord.latitude, coord.longitude,
                                  station.lat, station.lon)
                let distM = Int(d.rounded())
                let walk = max(1, Int((d / 80).rounded()))
                return (station, distM, walk)
            }
            .min { $0.1 < $1.1 }
            .map { ($0.0, $0.1, $0.2) }
    }

    // MARK: - Lookup helpers

    /// Returns the station whose `codes` array contains `code` (exact,
    /// case-sensitive — MRT codes are always uppercase in the dataset).
    static func station(forCode code: String) -> MrtGeoStation? {
        all.first { $0.codes.contains(code) }
    }

    /// Case-insensitive substring match on station name OR any line code.
    /// Trims leading/trailing whitespace from `query` before matching.
    /// Returns `[]` for an empty query after trimming.
    static func stations(matching query: String) -> [MrtGeoStation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return all.filter { station in
            station.name.lowercased().contains(q)
                || station.codes.contains { $0.lowercased().contains(q) }
        }
    }
}
