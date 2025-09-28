//
//  LocationLogger.swift
//  PitTemp
// 位置情報キャプチャ（低コスト常時“最後の位置”）

import CoreLocation
import Combine

final class LocationLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationLogger()

    @Published private(set) var last: CLLocation?
    @Published private(set) var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 30 // 30m 単位で十分
    }

    func request() {
        authStatus = manager.authorizationStatus
        if authStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // Delegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last { last = loc }
    }
}

