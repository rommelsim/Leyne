// CoreLocation wrapper — When-In-Use, for the Nearby tab.
// API mirrors lib/services/location_service.dart (Flutter v2.0):
//   refreshStatus()     — read auth status without prompting (safe in init)
//   startIfAuthorized() — start the stream only if already granted
//   requestAndStart()   — prompt (if .notDetermined) then start
//   openAppSettings()   — recovery for .denied / .restricted (Settings deep link)

import Foundation
import CoreLocation
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus
    /// Compass bearing in degrees (true north preferred). Only published while
    /// a screen has asked for it via `startHeading()` — the magnetometer is not
    /// free, and only the map cares which way you are facing.
    @Published var headingDegrees: Double?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50  // metres — matches Flutter LocationSettings
    }

    var authorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// True only when the user has previously denied + the system treats
    /// further requestWhenInUseAuthorization calls as no-ops. Drives the
    /// "Open Settings" CTA in the Nearby permission prompt.
    var deniedForever: Bool {
        status == .denied || status == .restricted
    }

    /// Read current permission status without prompting.
    func refreshStatus() {
        status = manager.authorizationStatus
    }

    /// Start the position stream if (and only if) permission is already
    /// granted. Never prompts — safe to call from view initialisation.
    func startIfAuthorized() {
        refreshStatus()
        if authorized { manager.startUpdatingLocation() }
    }

    /// Prompt the user (if `.notDetermined`) and start the stream if granted.
    /// On `.denied` the UI should offer `openAppSettings()` as recovery.
    func requestAndStart() {
        refreshStatus()
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()  // delegate fires when answered
        } else if authorized {
            manager.startUpdatingLocation()
        }
    }

    /// Open the OS Settings deep-link for this app.
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Heading (map only)

    /// Start the compass and tighten the position stream. The map draws the
    /// user as a facing arrow, which is a lie at 50 m / 100 m accuracy — while
    /// the map is on screen we ask for the good fix and hand it back on exit.
    func startHeading() {
        guard authorized else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 2          // degrees
            manager.startUpdatingHeading()
        }
    }

    func stopHeading() {
        manager.stopUpdatingHeading()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        headingDegrees = nil
    }

    nonisolated func locationManager(_ m: CLLocationManager,
                                     didUpdateHeading newHeading: CLHeading) {
        // Negative trueHeading means no valid compass calibration yet.
        let deg = newHeading.trueHeading >= 0 ? newHeading.trueHeading
                                              : newHeading.magneticHeading
        guard deg >= 0 else { return }
        Task { @MainActor in self.headingDegrees = deg }
    }

    // Retained for backwards compatibility with existing call sites.
    func requestPermission() { requestAndStart() }
    func start() { startIfAuthorized() }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            status = m.authorizationStatus
            if authorized { m.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager,
                                     didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { @MainActor in
            self.location = loc
            DataStore.shared.updateNearby(loc)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager,
                                     didFailWithError error: Error) { /* keep last */ }
}
