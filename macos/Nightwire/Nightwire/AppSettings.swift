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

    var githubToken: String {
        didSet { defaults.set(githubToken, forKey: Keys.githubToken) }
    }

    var skippedUpdateVersion: String {
        didSet { defaults.set(skippedUpdateVersion, forKey: Keys.skippedUpdate) }
    }

    var hasGitHubToken: Bool {
        !githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoTrackGateway = "nightwire.autoTrackGateway"
        static let notifications = "nightwire.notificationsEnabled"
        static let githubToken = "nightwire.githubToken"
        static let skippedUpdate = "nightwire.skippedUpdateVersion"
    }

    private init() {
        autoTrackGateway = defaults.object(forKey: Keys.autoTrackGateway) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        githubToken = defaults.string(forKey: Keys.githubToken) ?? ""
        skippedUpdateVersion = defaults.string(forKey: Keys.skippedUpdate) ?? ""
        loginAtStartup = SMAppService.mainApp.status == .enabled
    }

    func skip(version: String) {
        skippedUpdateVersion = version
    }

    func hasSkipped(version: String) -> Bool {
        !version.isEmpty && skippedUpdateVersion == version
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
