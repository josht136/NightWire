import Foundation
import UserNotifications

@MainActor
final class ChangeNotifier {
    private var lastIP: String?
    private var lastConfig: IpConfigurationType?
    private var lastSSID: String?
    private var lastGateway: String?
    private var primed = false

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func observe(_ snapshot: NetworkSnapshot) {
        guard AppSettings.shared.notificationsEnabled else {
            remember(snapshot)
            return
        }

        let ip = snapshot.primary?.ipv4
        let config = snapshot.primary?.configuration
        let ssid = snapshot.primary?.wifiSSID
        let gateway = snapshot.primary?.gateway

        if primed {
            if let ip, ip != lastIP, let previous = lastIP {
                notify(title: "IP changed", body: "\(previous) → \(ip)")
            }
            if let config, config != lastConfig, let previous = lastConfig, previous != .unknown {
                notify(title: "Addressing changed", body: "\(previous.rawValue) → \(config.rawValue)")
            }
            if ssid != lastSSID, lastSSID != nil || ssid != nil {
                let from = lastSSID ?? "off"
                let to = ssid ?? "off"
                notify(title: "Wi-Fi changed", body: "\(from) → \(to)")
            }
            if let gateway, !gateway.isEmpty, gateway != lastGateway, let previous = lastGateway, !previous.isEmpty {
                notify(title: "Gateway changed", body: "\(previous) → \(gateway)")
            }
        }

        remember(snapshot)
        primed = true
    }

    private func remember(_ snapshot: NetworkSnapshot) {
        lastIP = snapshot.primary?.ipv4
        lastConfig = snapshot.primary?.configuration
        lastSSID = snapshot.primary?.wifiSSID
        lastGateway = snapshot.primary?.gateway
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
