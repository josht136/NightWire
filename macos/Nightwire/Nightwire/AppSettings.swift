import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var autoTrackGateway: Bool {
        didSet { defaults.set(autoTrackGateway, forKey: Keys.autoTrackGateway) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    var loginAtStartup: Bool
    var loginError: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoTrackGateway = "nightwire.autoTrackGateway"
        static let notifications = "nightwire.notificationsEnabled"
    }

    private init() {
        autoTrackGateway = defaults.object(forKey: Keys.autoTrackGateway) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        loginAtStartup = SMAppService.mainApp.status == .enabled
    }

    func refreshLoginStatus() {
        loginAtStartup = SMAppService.mainApp.status == .enabled
    }

    func setLoginAtStartup(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }
}
