// Codable DTOs for the LTA DataMall responses + mappers to domain models.

import Foundation

// ─── Bus Arrival v3 ───────────────────────────────────────
struct LTAArrivalResponse: Decodable {
    let BusStopCode: String
    let Services: [LTAArrivalService]
}

struct LTAArrivalService: Decodable {
    let ServiceNo: String
    let Operator: String?
    let NextBus: LTANextBus
    let NextBus2: LTANextBus
    let NextBus3: LTANextBus
}

struct LTANextBus: Decodable {
    let OriginCode: String?
    let DestinationCode: String?
    let EstimatedArrival: String?
    let Latitude: String?
    let Longitude: String?
    let Load: String?
    let Feature: String?
    let vehicleType: String?
    /// LTA flag: 1 = position is from a live GPS feed; 0 = a scheduled
    /// estimate (no vehicle telemetry). Drives the live/scheduled badge.
    let Monitored: Int?

    enum CodingKeys: String, CodingKey {
        case OriginCode, DestinationCode, EstimatedArrival
        case Latitude, Longitude, Load, Feature, Monitored
        case vehicleType = "Type"
    }

    var arrivalDate: Date? {
        guard let s = EstimatedArrival, !s.isEmpty else { return nil }
        return LTADate.parse(s)
    }
    var lat: Double? { Double(Latitude ?? "") }
    var lon: Double? { Double(Longitude ?? "") }
    var hasData: Bool { arrivalDate != nil }
}

// ─── Bulk reference datasets ──────────────────────────────
struct LTAList<T: Codable>: Codable { let value: [T] }

struct LTABusStop: Codable, Equatable {
    let BusStopCode: String
    let RoadName: String
    let Description: String
    let Latitude: Double
    let Longitude: Double
}

struct LTABusServiceDTO: Codable, Equatable {
    let ServiceNo: String
    let `Operator`: String?
    let Direction: Int
    let Category: String?
    let OriginCode: String?
    let DestinationCode: String?
    let LoopDesc: String?
}

struct LTABusRouteDTO: Codable, Equatable {
    let ServiceNo: String
    let `Operator`: String?
    let Direction: Int
    let StopSequence: Int
    let BusStopCode: String
    let Distance: Double?
    // First/last bus clock times ("HHmm", e.g. "0530"; "-"/"" when not running)
    // per service day. LTA returns these on every BusRoutes row; the Bus view
    // surfaces the boarding stop's window so a late-night commuter can tell
    // whether the last bus has already gone. Optional → an older on-disk cache
    // (encoded before these fields existed) decodes them as nil, not an error.
    let WD_FirstBus: String?
    let WD_LastBus: String?
    let SAT_FirstBus: String?
    let SAT_LastBus: String?
    let SUN_FirstBus: String?
    let SUN_LastBus: String?
}

// ─── Train service alerts (MRT/LRT) ───────────────────────
// `value` is an object (not an array) so this endpoint uses its own
// envelope rather than `LTAList`. Status: 1 = normal, 2 = disrupted.

struct LTATrainAlertResponse: Codable {
    let value: LTATrainAlerts
}

struct LTATrainAlerts: Codable {
    let Status: Int
    let AffectedSegments: [LTAAffectedSegment]
    let Message: [LTATrainMessage]
}

struct LTAAffectedSegment: Codable, Equatable {
    let Line: String              // e.g. "NEL", "EWL", "NSL", "CCL", "DTL", "TEL"
    let Direction: String?        // "Both" | direction name
    let Stations: String?         // comma-separated station codes, e.g. "NE6,NE7,..."
    let FreePublicBus: String?
    let FreeMRTShuttle: String?
    let MRTShuttleDirection: String?
}

struct LTATrainMessage: Codable, Equatable {
    let Content: String
    let CreatedDate: String?
}

// ─── Station crowd density (PCDRealTime) ──────────────────
// Real-time MRT/LRT station crowdedness for one train line.
// CrowdLevel: "l" low · "m" moderate · "h" high · "NA" unknown.
struct LTAStationCrowd: Codable, Equatable {
    let Station: String          // station code, e.g. "EW13"
    let StartTime: String?
    let EndTime: String?
    let CrowdLevel: String
}

// ─── Station crowd forecast (PCDForecast) ─────────────────
// The PCDForecast endpoint returns one of two JSON shapes depending on the
// date context. We handle both defensively; any parse failure yields [].
//
// Nested shape (typical):
//   { "value": [ { "Date": "...", "Stations": [ { "Station": "EW1",
//       "Interval": [ { "Start": "2025-01-01T06:00:00+08:00",
//                       "CrowdLevel": "l" } ] } ] } ] }
//
// Flat shape (historical / some endpoints):
//   { "value": [ { "Station": "EW1", "Start": "...", "CrowdLevel": "l" } ] }

/// A single (station, interval-start, crowd-level) tuple from PCDForecast.
struct LTAForecastInterval: Equatable {
    let station: String     // e.g. "EW13"
    let start: Date
    let crowdLevel: String  // "l" | "m" | "h" | "NA"
}

/// Decoder that tolerates both the nested and flat PCDForecast shapes.
/// On any failure it returns an empty array instead of throwing.
enum LTAForecastParser {
    /// Attempt the nested shape first, then the flat shape.
    /// Never throws — always returns (possibly empty) results.
    static func parse(data: Data) -> [LTAForecastInterval] {
        if let nested = tryNested(data: data), !nested.isEmpty { return nested }
        if let flat   = tryFlat(data: data),   !flat.isEmpty   { return flat }
        return []
    }

    // Nested shape intermediates
    private struct NestedRoot: Decodable {
        let value: [NestedDay]
        struct NestedDay: Decodable {
            let Date: String?
            let Stations: [NestedStation]
        }
        struct NestedStation: Decodable {
            let Station: String
            let Interval: [NestedInterval]
        }
        struct NestedInterval: Decodable {
            let Start: String
            let CrowdLevel: String
        }
    }

    private static func tryNested(data: Data) -> [LTAForecastInterval]? {
        guard let root = try? JSONDecoder().decode(NestedRoot.self, from: data) else { return nil }
        var out: [LTAForecastInterval] = []
        for day in root.value {
            for station in day.Stations {
                for interval in station.Interval {
                    guard let date = LTADate.parse(interval.Start) else { continue }
                    out.append(LTAForecastInterval(station: station.Station,
                                                  start: date,
                                                  crowdLevel: interval.CrowdLevel))
                }
            }
        }
        return out.isEmpty ? nil : out
    }

    // Flat shape intermediates
    private struct FlatRoot: Decodable {
        let value: [FlatRow]
        struct FlatRow: Decodable {
            let Station: String
            let Start: String
            let CrowdLevel: String
        }
    }

    private static func tryFlat(data: Data) -> [LTAForecastInterval]? {
        guard let root = try? JSONDecoder().decode(FlatRoot.self, from: data) else { return nil }
        let out = root.value.compactMap { row -> LTAForecastInterval? in
            guard let date = LTADate.parse(row.Start) else { return nil }
            return LTAForecastInterval(station: row.Station,
                                      start: date,
                                      crowdLevel: row.CrowdLevel)
        }
        return out.isEmpty ? nil : out
    }
}

// ─── Facilities maintenance v2 (adhoc lift maintenance) ───
struct LTAFacilityMaintenance: Codable, Equatable {
    let Line: String             // e.g. "NEL"
    let StationCode: String      // e.g. "NE12"
    let StationName: String      // e.g. "Serangoon"
    let LiftID: String?
    let LiftDesc: String?        // e.g. "Exit B Street level - Concourse"
}

// ─── ISO-8601 (+08:00) date parsing ───────────────────────
enum LTADate {
    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fmtFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func parse(_ s: String) -> Date? {
        fmt.date(from: s) ?? fmtFractional.date(from: s)
    }
}

// ─── Mapping LTA → domain ─────────────────────────────────
extension Load {
    init(lta raw: String?) {
        switch (raw ?? "").uppercased() {
        case "SDA": self = .sda
        case "LSD": self = .lsd
        default:    self = .sea   // SEA or unknown
        }
    }

    /// Strict variant: nil when LTA gives no occupancy code (rather than
    /// defaulting to `.sea`). Used for the 2nd/3rd buses, where an absent
    /// Load should read as "crowd unknown", not a falsely confident "seats".
    init?(ltaStrict raw: String?) {
        switch (raw ?? "").uppercased() {
        case "SEA": self = .sea
        case "SDA": self = .sda
        case "LSD": self = .lsd
        default:    return nil
        }
    }
}

extension Deck {
    init(lta raw: String?) {
        switch (raw ?? "").uppercased() {
        case "DD": self = .DD
        case "BD": self = .BD
        default:   self = .SD
        }
    }
}

extension LTAArrivalService {
    /// Build a domain Service. `destName` resolves DestinationCode → stop name.
    func toService(destName: String) -> Service {
        let now = Date()
        let eta = NextBus.arrivalDate.map { max(0, Int($0.timeIntervalSince(now))) } ?? 0
        let foll = NextBus2.arrivalDate.map { max(0, Int($0.timeIntervalSince(now))) }
            ?? (eta + 600)
        return Service(
            no: ServiceNo,
            dest: destName,
            etaSec: eta,
            followingSec: foll,
            load: Load(lta: NextBus.Load),
            wab: (NextBus.Feature ?? "").uppercased() == "WAB",
            deck: Deck(lta: NextBus.vehicleType),
            // Absent Monitored ⟶ treat as live; LTA only emits 0 when it
            // knows the estimate is schedule-derived.
            monitored: (NextBus.Monitored ?? 1) == 1,
            op: BusOperator(lta: Operator),
            arrivalDate: NextBus.arrivalDate,
            followingDate: NextBus2.arrivalDate,
            thirdDate: NextBus3.arrivalDate,
            // Live bus GPS (monitored only) → honest Distance sort on Stop.
            busLat: (NextBus.lat ?? 0) != 0 ? NextBus.lat : nil,
            busLon: (NextBus.lon ?? 0) != 0 ? NextBus.lon : nil,
            followingLoad: Load(ltaStrict: NextBus2.Load),
            thirdLoad: Load(ltaStrict: NextBus3.Load)
        )
    }
}
