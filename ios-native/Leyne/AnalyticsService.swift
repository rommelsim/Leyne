//  AnalyticsService.swift
//
//  Thin, typed wrapper over Firebase Analytics — the app's high-signal product
//  events. Centralising the Firebase import here means the rest of the app logs
//  via a typed API (`AnalyticsService.log(.stopViewed(...))`) and never imports
//  FirebaseAnalytics directly, so event names + parameters have one source of
//  truth that the Android side mirrors. `app_open` is logged automatically by the
//  SDK, so it is deliberately not represented here.
//
//  NOTE: ad revenue (`ad_impression`) is NOT logged here — the Google Mobile Ads
//  SDK auto-logs it once the AdMob↔Firebase link is active. Don't re-add a manual
//  paidEventHandler logger, or impressions double-count in GA4.
//
//  Firebase is configured at launch in `LeyneApp` (LeyneAppDelegate). When the
//  GoogleService-Info.plist is absent (e.g. a fork / CI without the config),
//  configure() is skipped and these calls degrade to no-ops — never a crash.

import Foundation
import FirebaseAnalytics

enum AnalyticsService {

    // MARK: - Product events

    /// The seven high-signal events from the Phase 0 plan (minus auto `app_open`).
    enum Event {
        case stopViewed(code: String, kind: StopKind)
        case alertSet(kind: String, busNo: String)
        case favouriteAdded(kind: FavKind)
        case searchPerformed
        case onboardingCompleted
        case notificationTapped(kind: String)

        enum StopKind: String { case bus, mrt }
        enum FavKind: String { case stop, service }

        var name: String {
            switch self {
            case .stopViewed:          return "stop_viewed"
            case .alertSet:            return "alert_set"
            case .favouriteAdded:      return "favourite_added"
            case .searchPerformed:     return "search_performed"
            case .onboardingCompleted: return "onboarding_completed"
            case .notificationTapped:  return "notification_tapped"
            }
        }

        var parameters: [String: Any]? {
            switch self {
            case let .stopViewed(code, kind):
                return ["stop_code": code, "kind": kind.rawValue]
            case let .alertSet(kind, busNo):
                return ["kind": kind, "bus_no": busNo]
            case let .favouriteAdded(kind):
                return ["kind": kind.rawValue]
            case .searchPerformed, .onboardingCompleted:
                return nil
            case let .notificationTapped(kind):
                return ["kind": kind.isEmpty ? "unknown" : kind]
            }
        }
    }

    /// Log a product event. Safe to call before Firebase is configured (no-op).
    static func log(_ event: Event) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
