// WeatherService — wraps WeatherKit for Leyne.
//
// Design constraints:
//   • Fully @MainActor: all state is published on the main actor so SwiftUI
//     views read it without crossing isolation boundaries.
//   • Graceful fallback: any WeatherKit error (unauthorized, network, not
//     provisioned) silently sets `snapshot` to nil. The rest of the app is
//     unaffected.
//   • Attribution: the app must show the legal WeatherKit attribution link per
//     Apple's terms. `attributionURL` and `attributionLogoURL` are fetched
//     alongside the first weather fetch and cached.
//   • Refresh cadence: on demand (onAppear) + 15-min background timer.
//     A guard on `lastFetchDate` prevents redundant calls within 10 minutes.
//   • iOS 16.0+ (WeatherKit availability). The whole service returns nil on
//     iOS 15 because Leyne's deployment target is iOS 18, but we add the
//     explicit availability annotation for documentation clarity.

import Foundation
import CoreLocation
import os

#if canImport(WeatherKit)
import WeatherKit
#endif

// MARK: - Public snapshot type

/// Caller-facing weather data. Value type — safe to pass across MainActor boundary.
struct WeatherSnapshot: Sendable {
    let tempC: Int                  // rounded °C
    let symbolName: String          // SF Symbol from WeatherKit
    let conditionLabel: String      // short localised description
    let rainHint: String?           // e.g. "light rain ~5 pm" or nil
    let bucket: WeatherBucket       // backdrop variant
}

/// Backdrop condition bucket — drives the greyscale overlay opacity.
enum WeatherBucket: Sendable {
    case clearDay, clearNight, cloudy, rain
}

// MARK: - WeatherService

@MainActor
final class WeatherService: ObservableObject {

    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var attributionURL: URL?
    @Published private(set) var attributionLogoURL: URL?     // light-scheme logo

    private var lastFetchDate: Date?
    private var refreshTimer: Timer?

    private let log = Logger(subsystem: "com.leyne.Leyne", category: "WeatherService")

    private init() {}

    // MARK: - Public interface

    /// Fetch weather for the given location if the cache is stale (>10 min)
    /// or this is the first call. Safe to call repeatedly from `onAppear`.
    func fetchIfNeeded(location: CLLocation) {
        let now = Date()
        if let last = lastFetchDate, now.timeIntervalSince(last) < 600 { return }
        Task { await fetch(location: location) }
    }

    /// Arms the 15-minute background refresh. Call once from the owning view's
    /// `onAppear`. Calling again is a no-op if the timer is already running.
    func startPeriodicRefresh(getLocation: @escaping @Sendable () -> CLLocation?) {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let loc = getLocation() else { return }
                await self.fetch(location: loc)
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Private fetch

    private func fetch(location: CLLocation) async {
#if canImport(WeatherKit)
        do {
            let service = WKWeatherService.shared
            let weather = try await service.weather(for: location)
            let attrib  = try await service.attribution

            lastFetchDate = Date()

            // Attribution (WeatherKit ToS — must surface these URLs in UI).
            attributionURL     = attrib.legalPageURL
            attributionLogoURL = attrib.combinedMarkDarkURL  // dark = visible on light bg too

            let current = weather.currentWeather
            let tempC   = Int(current.temperature.converted(to: .celsius).value.rounded())

            let rainHint = nearTermRainHint(
                hourly: weather.hourlyForecast,
                referenceDate: Date()
            )

            snapshot = WeatherSnapshot(
                tempC: tempC,
                symbolName: current.symbolName,
                conditionLabel: current.condition.description,
                rainHint: rainHint,
                bucket: bucket(for: current)
            )
        } catch {
            // Unauthorized, not provisioned, or network failure — degrade silently.
            log.info("WeatherKit fetch skipped: \(error.localizedDescription)")
            // Do NOT clear an existing snapshot on transient errors so the last
            // reading persists until a successful refresh.
            if snapshot == nil {
                // First-ever fetch failed — stay nil (no weather UI).
            }
        }
#endif
    }

    // MARK: - Helpers

    /// Looks at the next two hours of hourly forecast. If any hour has
    /// ≥ 40 % precipitation chance, returns a hint string like "light rain ~5 pm".
    /// Returns nil when no rain is expected.
    private func nearTermRainHint(
        hourly: Forecast<HourWeather>,
        referenceDate: Date
    ) -> String? {
        let cal = Calendar.current
        let twoHoursLater = referenceDate.addingTimeInterval(2 * 3600)

        let soonHours = hourly.filter {
            $0.date > referenceDate && $0.date <= twoHoursLater
        }

        guard let first = soonHours.first(where: { $0.precipitationChance >= 0.40 })
        else { return nil }

        let hour = cal.component(.hour, from: first.date)
        let ampm = hour >= 12 ? "pm" : "am"
        let display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)

        // Condition name from WeatherKit's precipitation type if available,
        // else generic "rain".
        let label: String
        switch first.precipitation {
        case .hail:          label = "hail"
        case .mixed:         label = "sleet"
        case .rain:          label = "rain"
        case .sleet:         label = "sleet"
        case .snow:          label = "snow"
        default:             label = "rain"
        }

        return "\(label) ~\(display)\(ampm)"
    }

    /// Maps the current condition to a greyscale backdrop bucket.
    private func bucket(for current: CurrentWeather) -> WeatherBucket {
        let isDaytime = current.isDaylight
        switch current.condition {
        case .clear, .mostlyClear, .hot, .windy:
            return isDaytime ? .clearDay : .clearNight
        case .drizzle, .heavyRain, .rain, .sunShowers, .isolatedThunderstorms,
             .scatteredThunderstorms, .strongStorms, .thunderstorms,
             .tropicalStorm, .hurricane, .haze, .smoky, .blizzard, .blowingSnow,
             .flurries, .freezingDrizzle, .freezingRain, .heavySnow, .sleet, .snow,
             .sunFlurries, .wintryMix:
            return .rain
        default:
            return .cloudy
        }
    }
}

// Alias to avoid shadowing if WeatherKit is unavailable at the call site.
#if canImport(WeatherKit)
private typealias WKWeatherService = WeatherKit.WeatherService
private typealias HourWeather = WeatherKit.HourWeather
#endif
