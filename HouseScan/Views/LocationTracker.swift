import CoreLocation
import Observation

/// Keeps the latest position and heading while a site note is being taken.
@MainActor @Observable
final class LocationTracker: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var heading: SiteHeading?
    private(set) var isDenied = false
    private(set) var isPrecise = true

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = kCLHeadingFilterNone
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    var position: SitePosition? {
        location.flatMap { SitePosition($0, at: Date(), isPrecise: isPrecise) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        isDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = SiteHeading(magnetic: newHeading.magneticHeading, true: newHeading.trueHeading, accuracy: newHeading.headingAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
