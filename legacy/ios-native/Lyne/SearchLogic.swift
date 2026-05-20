// Pure query-kind detection (no data). Buses + Stops are resolved live by
// DataStore.searchServices / DataStore.searchStops.

import Foundation

func detectQueryKind(_ raw: String) -> DetectedKind {
    let q = raw.trimmingCharacters(in: .whitespaces)
    if q.isEmpty { return DetectedKind(kind: "empty", label: "") }
    if q.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
        return DetectedKind(kind: "postal", label: "Postal code")
    }
    if q.range(of: #"^\d{5}$"#, options: .regularExpression) != nil {
        return DetectedKind(kind: "stopcode", label: "Stop code")
    }
    // Up to 2 leading letters covers real SG services: 88, 410W, NR1, CT8.
    if q.range(of: #"^[A-Za-z]{0,2}\d{1,3}[A-Za-z]?$"#, options: .regularExpression) != nil {
        return DetectedKind(kind: "bus", label: "Bus service")
    }
    if q.range(of: #"^blk\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return DetectedKind(kind: "block", label: "Block + street")
    }
    return DetectedKind(kind: "text", label: "Name or place")
}
