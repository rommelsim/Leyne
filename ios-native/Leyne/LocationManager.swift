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

    /// Resumed by the authorization delegate so callers can `await` the user's
    /// answer to the location prompt (used by the first-run permission runner).
    private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

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

    // Retained for backwards compatibility with existing call sites.
    func requestPermission() { requestAndStart() }
    func start() { startIfAuthorized() }

    /// Prompt for permission and await the user's answer. Returns immediately
    /// with the current status if it's already determined.
    func requestPermissionAwaiting() async -> CLAuthorizationStatus {
        refreshStatus()
        guard status == .notDetermined else {
            if authorized { manager.startUpdatingLocation() }
            return status
        }
        return await withCheckedContinuation { cont in
            permissionContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            status = m.authorizationStatus
            if authorized { m.startUpdatingLocation() }
            // Only resume once the user has actually answered — the delegate
            // also fires with `.notDetermined` at registration, before the
            // prompt is shown.
            if status != .notDetermined, let cont = permissionContinuation {
                permissionContinuation = nil
                cont.resume(returning: status)
            }
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
