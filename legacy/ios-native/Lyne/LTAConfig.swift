// LTA DataMall configuration.
//
// NOTE: this is a client-embedded LTA DataMall AccountKey. DataMall keys are
// low-sensitivity (public open-data, rate-limited) so embedding is acceptable
// for this app; keep it in this one file and do not log it. For a shipping
// product, prefer injecting via xcconfig / a fetch-on-launch endpoint.

import Foundation

enum LTAConfig {
    static let accountKey = "+6zJ3XstTqOcDkvczHttWA=="
    static let baseURL = URL(string: "https://datamall2.mytransport.sg/ltaodataservice")!

    /// Records returned per page for the bulk datasets ($skip pagination).
    static let pageSize = 500

    /// How often to re-poll a stop's live arrivals (guide: 20s update freq).
    static let arrivalRefreshSeconds: TimeInterval = 25

    /// Bulk reference datasets are "ad hoc" — cache on disk and refresh weekly.
    static let referenceCacheMaxAge: TimeInterval = 7 * 24 * 3600
}
