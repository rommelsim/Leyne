// CoreLocation wrapper — When-In-Use, for the Nearby tab.

import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func requestPermission() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorized {
            manager.startUpdatingLocation()
        }
    }

    func start() {
        if authorized { manager.startUpdatingLocation() }
    }

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
