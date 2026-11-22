import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?

    /// Gọi mỗi khi có tọa độ mới (vị trí thật, hoặc vị trí giả khi đang giả lập).
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    /// Gọi khi la bàn đổi hướng (độ, 0 = Bắc).
    var onHeading: ((Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.headingFilter = 5
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        lastKnownCoordinate = coordinate
        onLocation?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        onHeading?(value)
    }
}
