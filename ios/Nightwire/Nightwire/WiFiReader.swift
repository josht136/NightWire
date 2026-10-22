import CoreLocation
import Foundation
import NetworkExtension

struct WiFiSnapshot: Equatable, Sendable {
    var ssid: String?
    var bssid: String?
    var signal: String?

    static let empty = WiFiSnapshot()
}

/// Reads the associated Wi-Fi network. iOS only returns it after Location permission
/// and the Wi-Fi Information capability are both present.
@MainActor
final class WiFiReader: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiReader()

    var onChange: (() -> Void)?
    private(set) var snapshot = WiFiSnapshot.empty

    private let manager: CLLocationManager
    private var lastFetch = Date.distantPast
    private var askedForAccuracy = false
    private var fetchInFlight = false

    private override init() {
        let manager = CLLocationManager()
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func prepare() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            fetchIfStale(force: false)
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        else { return }
        fetchIfStale(force: true)
    }

    private func fetchIfStale(force: Bool) {
        guard !fetchInFlight else { return }
        if !force, Date().timeIntervalSince(lastFetch) < 8 { return }
        lastFetch = Date()
        fetchInFlight = true

        if !askedForAccuracy {
            askedForAccuracy = true
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WiFiDetails") { [weak self] _ in
                Task { @MainActor in
                    self?.fetchCurrent()
                }
            }
            return
        }
        fetchCurrent()
    }

    private func fetchCurrent() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let next = Self.snapshot(from: network)
            Task { @MainActor in
                guard let self else { return }
                self.fetchInFlight = false
                guard next != self.snapshot else { return }
                self.snapshot = next
                self.onChange?()
            }
        }
    }

    nonisolated private static func snapshot(from network: NEHotspotNetwork?) -> WiFiSnapshot {
        guard let network else { return .empty }
        let ssid = network.ssid.isEmpty ? nil : network.ssid
        let percent = Int((min(max(network.signalStrength, 0), 1) * 100).rounded())
        return WiFiSnapshot(ssid: ssid, bssid: cleanedBSSID(network.bssid), signal: "\(percent)%")
    }

    nonisolated private static func cleanedBSSID(_ value: String) -> String? {
        value.isEmpty ? nil : (MACAddress.normalize(value) ?? value.uppercased())
    }

    nonisolated private static func cleanedBSSID(_ value: String?) -> String? {
        guard let value else { return nil }
        return cleanedBSSID(value)
    }
}
