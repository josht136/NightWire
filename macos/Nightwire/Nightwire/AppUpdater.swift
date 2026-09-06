import AppKit
import Foundation
import Observation

struct GitHubRelease: Equatable {
    let tagName: String
    let title: String
    let notes: String
    let htmlURL: URL?
    let assetAPIURL: URL
    let assetBrowserURL: URL

    var marketingVersion: String {
        var tag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.first == "v" || tag.first == "V" {
            tag.removeFirst()
        }
        return tag
    }

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nightwire \(marketingVersion)" : trimmed
    }
}

enum UpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease)
    case downloading(Double)
    case readyToInstall(GitHubRelease)
    case installing
    case installed(String)
    case failed(String)
}

@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    var phase: UpdatePhase = .idle
    var showPrompt = false

    var currentMarketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var currentVersionLabel: String {
        "\(currentMarketingVersion) (\(currentBuild))"
    }

    var canCancel: Bool {
        switch phase {
        case .installing:
            return false
        default:
            return true
        }
    }

    private let settings = AppSettings.shared
    private var downloadedAppURL: URL?
    private var workDirectory: URL?
    private var download: FileDownload?
    private var launchCheckStarted = false

    private init() {}

    func checkOnLaunch() async {
        guard !launchCheckStarted else { return }
        launchCheckStarted = true
        guard !showPrompt else { return }
        do {
            let release = try await fetchLatestRelease()
            guard isNewer(release), !settings.hasSkipped(version: release.marketingVersion) else {
                return
            }
            present(.available(release))
        } catch {
            // Launch checks stay silent. Manual check surfaces the error.
        }
    }

    func checkNow() async {
        download?.cancel()
        download = nil
        cleanupWorkDirectory()
        present(.checking)
        do {
            let release = try await fetchLatestRelease()
            if isNewer(release) {
                present(.available(release))
            } else {
                present(.upToDate)
            }
        } catch {
            present(.failed(error.localizedDescription))
        }
    }

    func skipAvailableVersion() {
        if case .available(let release) = phase {
            settings.skip(version: release.marketingVersion)
        }
        dismissPrompt()
    }

    func startDownload() async {
        guard case .available(let release) = phase else { return }
        present(.downloading(0))
        do {
            let zipURL = try await downloadAsset(for: release)
            let appURL = try unpackAndValidate(zip: zipURL, expected: release)
            downloadedAppURL = appURL
            present(.readyToInstall(release))
        } catch {
            if Self.isCancellation(error) {
                if showPrompt { dismissPrompt() }
                return
            }
            present(.failed(error.localizedDescription))
        }
    }

    func installDownloadedUpdate() async {
        guard case .readyToInstall(let release) = phase, let appURL = downloadedAppURL else { return }
        present(.installing)
        do {
            try replaceRunningApp(with: appURL)
            present(.installed(release.marketingVersion))
        } catch {
            present(.failed(error.localizedDescription))
        }
    }

    func relaunch() {
        relaunchReplacedApp()
        NSApp.terminate(nil)
    }

    func dismissPrompt() {
        if !canCancel { return }
        download?.cancel()
        download = nil
        cleanupWorkDirectory()
        downloadedAppURL = nil
        phase = .idle
        showPrompt = false
    }

    func setPromptPresented(_ presented: Bool) {
        if presented {
            showPrompt = true
        } else {
            dismissPrompt()
        }
    }

    private func present(_ phase: UpdatePhase) {
        self.phase = phase
        showPrompt = true
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: UpdateConfig.latestReleaseURL)
        request.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        applyToken(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw UpdateError.invalidToken
        case 403:
            throw UpdateError.rateLimited
        case 404:
            throw UpdateError.releaseNotVisible
        default:
            throw UpdateError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(GitHubReleaseDTO.self, from: data)
        guard let asset = decoded.assets.first(where: { $0.name == UpdateConfig.assetName }) else {
            throw UpdateError.missingAsset
        }
        guard let apiURL = URL(string: asset.url), let browserURL = URL(string: asset.browserDownloadUrl) else {
            throw UpdateError.missingAsset
        }
        return GitHubRelease(
            tagName: decoded.tagName,
            title: decoded.name ?? "",
            notes: decoded.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            htmlURL: decoded.htmlUrl.flatMap(URL.init(string:)),
            assetAPIURL: apiURL,
            assetBrowserURL: browserURL
        )
    }

    private func downloadAsset(for release: GitHubRelease) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NightwireUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workDirectory = directory

        var request = URLRequest(url: settings.hasGitHubToken ? release.assetAPIURL : release.assetBrowserURL)
        request.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if settings.hasGitHubToken {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            applyToken(to: &request)
        }
        let destination = directory.appendingPathComponent(UpdateConfig.assetName)
        let session = FileDownload()
        download = session
        let url = try await session.download(request, to: destination) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }
        download = nil
        return url
    }

    private func unpackAndValidate(zip: URL, expected: GitHubRelease) throws -> URL {
        guard let directory = workDirectory else { throw UpdateError.unpackFailed }
        let unpackDir = directory.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", zip.path, unpackDir.path])
        guard let appURL = findAppBundle(in: unpackDir) else {
            throw UpdateError.unpackFailed
        }
        try clearQuarantine(at: appURL)
        try validateBundle(at: appURL, expected: expected)
        return appURL
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let direct = directory.appendingPathComponent("Nightwire.app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "Nightwire.app" {
                return item
            }
        }
        return nil
    }

    private func validateBundle(at appURL: URL, expected: GitHubRelease) throws {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) else {
            throw UpdateError.invalidBundle
        }
        let identifier = plist["CFBundleIdentifier"] as? String
        guard identifier == UpdateConfig.bundleIdentifier else {
            throw UpdateError.invalidBundle
        }
        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        let build = plist["CFBundleVersion"] as? String ?? "0"
        guard Self.versionParts(version) == Self.versionParts(expected.marketingVersion) else {
            throw UpdateError.invalidBundle
        }
        guard Self.compare(current: (currentMarketingVersion, currentBuild), incoming: (version, build)) else {
            throw UpdateError.notNewerThanRunning
        }
    }

    private func replaceRunningApp(with newApp: URL) throws {
        let destination = Bundle.main.bundleURL
        guard destination.pathExtension == "app" else {
            throw UpdateError.replaceFailed("Nightwire is not running from an .app bundle.")
        }
        if !FileManager.default.isWritableFile(atPath: destination.path)
            && !FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) {
            throw UpdateError.replaceFailed("Cannot write to \(destination.path). Move Nightwire to Desktop or Applications and try again.")
        }
        try run("/usr/bin/ditto", arguments: [newApp.path, destination.path])
        try clearQuarantine(at: destination)
    }

    private func relaunchReplacedApp() {
        let destination = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.15; done
        open \(Self.shellEscape(destination.path))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()
    }

    private func applyToken(to request: inout URLRequest) {
        let token = settings.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func isNewer(_ release: GitHubRelease) -> Bool {
        Self.compare(
            current: (currentMarketingVersion, currentBuild),
            incoming: (release.marketingVersion, "0")
        )
    }

    /// True when incoming marketing version (then build) is greater than the running app.
    static func compare(current: (String, String), incoming: (String, String)) -> Bool {
        let currentParts = versionParts(current.0)
        let incomingParts = versionParts(incoming.0)
        let count = max(currentParts.count, incomingParts.count)
        for index in 0..<count {
            let left = index < currentParts.count ? currentParts[index] : 0
            let right = index < incomingParts.count ? incomingParts[index] : 0
            if left != right { return left < right }
        }
        let currentBuild = Int(current.1.filter(\.isNumber)) ?? 0
        let incomingBuild = Int(incoming.1.filter(\.isNumber)) ?? 0
        return currentBuild < incomingBuild
    }

    private static func versionParts(_ raw: String) -> [Int] {
        raw.split(separator: ".").map { segment in
            Int(segment.filter(\.isNumber)) ?? 0
        }
    }

    private func clearQuarantine(at url: URL) throws {
        try? run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", url.path])
    }

    private func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed(launchPath, detail ?? "exit \(process.terminationStatus)")
        }
    }

    private func cleanupWorkDirectory() {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        downloadedAppURL = nil
    }

    private static func shellEscape(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String?
    let assets: [GitHubAssetDTO]
}

private struct GitHubAssetDTO: Decodable {
    let name: String
    let url: String
    let browserDownloadUrl: String
}

private enum UpdateError: LocalizedError {
    case badResponse
    case httpStatus(Int)
    case invalidToken
    case rateLimited
    case releaseNotVisible
    case missingAsset
    case unpackFailed
    case invalidBundle
    case notNewerThanRunning
    case replaceFailed(String)
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "GitHub returned an unreadable response."
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code)."
        case .invalidToken:
            return "GitHub rejected the token. Check Options → GitHub token."
        case .rateLimited:
            return "GitHub rate-limited the version check. Try again later, or add a token in Options."
        case .releaseNotVisible:
            return "No visible GitHub Release. The repo is private or has no published release. Add a GitHub token in Options, or publish a public repo/release."
        case .missingAsset:
            return "The latest GitHub Release has no “\(UpdateConfig.assetName)” asset."
        case .unpackFailed:
            return "Downloaded update was not a Nightwire.app zip."
        case .invalidBundle:
            return "The downloaded app is not a Nightwire bundle."
        case .notNewerThanRunning:
            return "The downloaded app is not newer than this copy of Nightwire."
        case .replaceFailed(let message):
            return message
        case .commandFailed(_, let detail):
            return detail.isEmpty ? "Failed to unpack or replace the app." : detail
        }
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var onProgress: (@Sendable (Double) -> Void)?

    func download(
        _ request: URLRequest,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        self.destination = destination
        self.onProgress = onProgress
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: request)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let finish: (Result<URL, Error>) -> Void = { [weak self] result in
            guard let self, let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
            session.finishTasksAndInvalidate()
        }

        guard let http = downloadTask.response as? HTTPURLResponse else {
            finish(.failure(UpdateError.badResponse))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                finish(.failure(UpdateError.invalidToken))
            } else if http.statusCode == 404 {
                finish(.failure(UpdateError.releaseNotVisible))
            } else {
                finish(.failure(UpdateError.httpStatus(http.statusCode)))
            }
            return
        }
        guard let destination else {
            finish(.failure(UpdateError.badResponse))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }
}
