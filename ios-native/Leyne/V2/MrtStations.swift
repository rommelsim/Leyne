// MRT/LRT station lookup — turns a bus-stop description that sits at a rail
// station ("Clementi Stn", "Farrer Rd Stn Exit A", "Bt Batok Stn") into the
// station's display name + line code(s) with official line colours, so the
// route timeline can show a colour-coded pill ("[EW23] Clementi") instead of a
// generic "MRT" tag.
//
// Matches on the stop DESCRIPTION: SG descriptions tag rail stops with "Stn"
// and use the station's name (often abbreviated — "Rd"→Road, "Bt"→Bukit,
// "Upp"→Upper). `resolveMrtStation` strips the directional prefix + "Stn" token,
// expands those abbreviations, then looks the name up. Conservative: returns nil
// unless the name resolves to a known station, so we never invent a code.
// Stations data current as of 2026 (NSL, EWL/CG, NEL, CCL/CE, DTL, TEL).
//
// Kept identical to the Flutter side (lib/data/mrt_stations.dart).

import SwiftUI

/// A single station code + its line colour, e.g. EW23 (green).
struct MrtCode: Equatable {
    let code: String
    let color: Color
}

/// A resolved rail station: display name + one or more line codes (>1 for
/// interchanges, e.g. Jurong East → EW24, NS1).
struct MrtStation: Equatable {
    let name: String
    let codes: [MrtCode]
}

private func mrtColor(_ hex: UInt32) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255,
          opacity: 1)
}

/// Official LTA line brand colours, keyed by the 2-letter code prefix.
private let mrtLineColors: [String: Color] = [
    "NS": mrtColor(0xD42E12), // North South — red
    "EW": mrtColor(0x009645), // East West — green
    "CG": mrtColor(0x009645), // Changi Airport branch — green
    "NE": mrtColor(0x9900AA), // North East — purple
    "CC": mrtColor(0xFA9E0D), // Circle — orange
    "CE": mrtColor(0xFA9E0D), // Circle extension — orange
    "DT": mrtColor(0x005EC4), // Downtown — blue
    "TE": mrtColor(0x9D5B25), // Thomson–East Coast — brown
]

/// Fallback colour for any LRT/other code we don't brand individually.
private let mrtLrtColor = mrtColor(0x748477) // LRT — grey-green

/// Brand colour for a station code like "EW23" / "CC1".
func mrtLineColorFor(_ code: String) -> Color {
    let prefix = String(code.prefix(2)).uppercased()
    return mrtLineColors[prefix] ?? mrtLrtColor
}

/// Station display name → all of its line codes. Interchanges list every code.
private let mrtStationCodes: [String: [String]] = [
    // North South Line
    "Jurong East": ["EW24", "NS1"],
    "Bukit Batok": ["NS2"],
    "Bukit Gombak": ["NS3"],
    "Choa Chu Kang": ["NS4"],
    "Yew Tee": ["NS5"],
    "Kranji": ["NS7"],
    "Marsiling": ["NS8"],
    "Woodlands": ["NS9", "TE2"],
    "Admiralty": ["NS10"],
    "Sembawang": ["NS11"],
    "Canberra": ["NS12"],
    "Yishun": ["NS13"],
    "Khatib": ["NS14"],
    "Yio Chu Kang": ["NS15"],
    "Ang Mo Kio": ["NS16"],
    "Bishan": ["NS17", "CC15"],
    "Braddell": ["NS18"],
    "Toa Payoh": ["NS19"],
    "Novena": ["NS20"],
    "Newton": ["NS21", "DT11"],
    "Orchard": ["NS22", "TE14"],
    "Somerset": ["NS23"],
    "Dhoby Ghaut": ["NS24", "NE6", "CC1"],
    "City Hall": ["NS25", "EW13"],
    "Raffles Place": ["NS26", "EW14"],
    "Marina Bay": ["NS27", "CE2", "TE20"],
    "Marina South Pier": ["NS28"],
    // East West Line + Changi branch
    "Pasir Ris": ["EW1"],
    "Tampines": ["EW2", "DT32"],
    "Simei": ["EW3"],
    "Tanah Merah": ["EW4"],
    "Bedok": ["EW5"],
    "Kembangan": ["EW6"],
    "Eunos": ["EW7"],
    "Paya Lebar": ["EW8", "CC9"],
    "Aljunied": ["EW9"],
    "Kallang": ["EW10"],
    "Lavender": ["EW11"],
    "Bugis": ["EW12", "DT14"],
    "Tanjong Pagar": ["EW15"],
    "Outram Park": ["EW16", "NE3", "TE17"],
    "Tiong Bahru": ["EW17"],
    "Redhill": ["EW18"],
    "Queenstown": ["EW19"],
    "Commonwealth": ["EW20"],
    "Buona Vista": ["EW21", "CC22"],
    "Dover": ["EW22"],
    "Clementi": ["EW23"],
    "Chinese Garden": ["EW25"],
    "Lakeside": ["EW26"],
    "Boon Lay": ["EW27"],
    "Pioneer": ["EW28"],
    "Joo Koon": ["EW29"],
    "Gul Circle": ["EW30"],
    "Tuas Crescent": ["EW31"],
    "Tuas West Road": ["EW32"],
    "Tuas Link": ["EW33"],
    "Expo": ["CG1", "DT35"],
    "Changi Airport": ["CG2"],
    // North East Line
    "HarbourFront": ["NE1", "CC29"],
    "Chinatown": ["NE4", "DT19"],
    "Clarke Quay": ["NE5"],
    "Little India": ["NE7", "DT12"],
    "Farrer Park": ["NE8"],
    "Boon Keng": ["NE9"],
    "Potong Pasir": ["NE10"],
    "Woodleigh": ["NE11"],
    "Serangoon": ["NE12", "CC13"],
    "Kovan": ["NE13"],
    "Hougang": ["NE14"],
    "Buangkok": ["NE15"],
    "Sengkang": ["NE16"],
    "Punggol": ["NE17"],
    "Punggol Coast": ["NE18"],
    // Circle Line + extension
    "Bras Basah": ["CC2"],
    "Esplanade": ["CC3"],
    "Promenade": ["CC4", "DT15"],
    "Nicoll Highway": ["CC5"],
    "Stadium": ["CC6"],
    "Mountbatten": ["CC7"],
    "Dakota": ["CC8"],
    "MacPherson": ["CC10", "DT26"],
    "Tai Seng": ["CC11"],
    "Bartley": ["CC12"],
    "Lorong Chuan": ["CC14"],
    "Marymount": ["CC16"],
    "Caldecott": ["CC17", "TE9"],
    "Botanic Gardens": ["CC19", "DT9"],
    "Farrer Road": ["CC20"],
    "Holland Village": ["CC21"],
    "one-north": ["CC23"],
    "Kent Ridge": ["CC24"],
    "Haw Par Villa": ["CC25"],
    "Pasir Panjang": ["CC26"],
    "Labrador Park": ["CC27"],
    "Telok Blangah": ["CC28"],
    "Bayfront": ["CE1", "DT16"],
    // Downtown Line
    "Bukit Panjang": ["DT1"],
    "Cashew": ["DT2"],
    "Hillview": ["DT3"],
    "Hume": ["DT4"],
    "Beauty World": ["DT5"],
    "King Albert Park": ["DT6"],
    "Sixth Avenue": ["DT7"],
    "Tan Kah Kee": ["DT8"],
    "Stevens": ["DT10", "TE11"],
    "Rochor": ["DT13"],
    "Downtown": ["DT17"],
    "Telok Ayer": ["DT18"],
    "Fort Canning": ["DT20"],
    "Bencoolen": ["DT21"],
    "Jalan Besar": ["DT22"],
    "Bendemeer": ["DT23"],
    "Geylang Bahru": ["DT24"],
    "Mattar": ["DT25"],
    "Ubi": ["DT27"],
    "Kaki Bukit": ["DT28"],
    "Bedok North": ["DT29"],
    "Bedok Reservoir": ["DT30"],
    "Tampines West": ["DT31"],
    "Tampines East": ["DT33"],
    "Upper Changi": ["DT34"],
    // Thomson–East Coast Line
    "Woodlands North": ["TE1"],
    "Woodlands South": ["TE3"],
    "Springleaf": ["TE4"],
    "Lentor": ["TE5"],
    "Mayflower": ["TE6"],
    "Bright Hill": ["TE7"],
    "Upper Thomson": ["TE8"],
    "Napier": ["TE12"],
    "Orchard Boulevard": ["TE13"],
    "Great World": ["TE15"],
    "Havelock": ["TE16"],
    "Maxwell": ["TE18"],
    "Shenton Way": ["TE19"],
    "Gardens by the Bay": ["TE22"],
    "Tanjong Rhu": ["TE23"],
    "Katong Park": ["TE24"],
    "Tanjong Katong": ["TE25"],
    "Marine Parade": ["TE26"],
    "Marine Terrace": ["TE27"],
    "Siglap": ["TE28"],
    "Bayshore": ["TE29"],
]

/// Common LTA bus-stop abbreviations → full words, so a stop description
/// normalises to the dataset's station names.
private let mrtAbbrev: [String: String] = [
    "rd": "road", "bt": "bukit", "upp": "upper", "pk": "park",
    "gdns": "gardens", "ctrl": "central", "ctr": "central",
]

/// Canonical form: lowercased, abbreviations expanded, spaces collapsed. Used to
/// build the lookup index AND to normalise queries, so both sides meet ("Farrer
/// Road" and "Farrer Rd Stn" both → "farrer road").
private func mrtCanon(_ s: String) -> String {
    let tokens = s.lowercased()
        .split(whereSeparator: { $0 == " " || $0 == "\t" })
        .map { mrtAbbrev[String($0)] ?? String($0) }
    return tokens.joined(separator: " ").replacingOccurrences(of: "cck", with: "choa chu kang")
}

/// Canonical station name → display name.
private let mrtIndex: [String: String] = {
    var idx: [String: String] = [:]
    for name in mrtStationCodes.keys { idx[mrtCanon(name)] = name }
    return idx
}()

/// Reverse index: station code (e.g. "EW13") → display name. Built once from
/// `mrtStationCodes`. Covers the trunk MRT lines (NS/EW/NE/CC/DT/TE); LRT and
/// any uncatalogued code simply isn't present.
private let mrtNameByCode: [String: String] = {
    var idx: [String: String] = [:]
    for (name, codes) in mrtStationCodes {
        for c in codes { idx[c.uppercased()] = name }
    }
    return idx
}()

/// Display name for a station code like "EW13" / "NS1", or nil if unknown.
/// Used to label PCD (crowd density) rows, which carry only station codes.
func mrtStationName(forCode code: String) -> String? {
    mrtNameByCode[code.uppercased()]
}

/// Resolve a bus-stop description to its rail station, or nil when it isn't a
/// (recognised) station stop. e.g. "Farrer Rd Stn Exit A" → Farrer Road [CC20].
func resolveMrtStation(_ stopName: String) -> MrtStation? {
    var s = stopName.lowercased().trimmingCharacters(in: .whitespaces)
    guard s.range(of: #"\b(stn|station|mrt|lrt)\b"#, options: .regularExpression) != nil
    else { return nil }
    // Drop a leading directional prefix ("Opp Clementi Stn" → "clementi stn").
    s = s.replacingOccurrences(
        of: #"^(opp|opposite|bef|before|aft|after)\s+"#,
        with: "", options: .regularExpression)
    // Keep only the part before the station token (drops "Stn", "Exit A", …).
    if let r = s.range(of: #"\b(stn|station|mrt|lrt)\b"#, options: .regularExpression) {
        s = String(s[s.startIndex..<r.lowerBound])
    }
    guard let display = mrtIndex[mrtCanon(s)] else { return nil }
    let codes = (mrtStationCodes[display] ?? []).map { MrtCode(code: $0, color: mrtLineColorFor($0)) }
    return MrtStation(name: display, codes: codes)
}
