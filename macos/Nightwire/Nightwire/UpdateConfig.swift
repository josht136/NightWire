import Foundation

enum UpdateConfig {
    static let owner = "josht136"
    static let repo = "pingslut"
    static let assetName = "Nightwire.app.zip"
    static let bundleIdentifier = "com.nightwire.app"

    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    static var repositoryDisplayName: String {
        "\(owner)/\(repo)"
    }

    static let userAgent = "Nightwire-Updater"
}
