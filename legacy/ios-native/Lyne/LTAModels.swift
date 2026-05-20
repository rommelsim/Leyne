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

    enum CodingKeys: String, CodingKey {
        case OriginCode, DestinationCode, EstimatedArrival
        case Latitude, Longitude, Load, Feature
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
            arrivalDate: NextBus.arrivalDate,
            followingDate: NextBus2.arrivalDate,
            thirdDate: NextBus3.arrivalDate
        )
    }
}
