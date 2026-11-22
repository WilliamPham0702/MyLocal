import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?

    /// Gọi mỗi khi có tọa độ mới (vị trí thật, hoặc vị trí giả khi đang giả lập).
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    /// Gọi khi la bàn đổi hướng (độ, 0 = Bắc).
    var onHeading: ((Double) -> Void)?
    /// Gọi khi người dùng chỉ cho phép vị trí gần đúng (lệch vài km).
    var onReducedAccuracy: ((Bool) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
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
        // Bỏ các điểm cũ hoặc sai số quá lớn để mũi tên không nhảy lung tung.
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 200 || lastKnownCoordinate == nil,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        let coordinate = location.coordinate
        lastKnownCoordinate = coordinate
        onLocation?(coordinate)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        onReducedAccuracy?(reduced)
        if reduced {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "MyLocalPrecise")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        onHeading?(value)
    }
}
