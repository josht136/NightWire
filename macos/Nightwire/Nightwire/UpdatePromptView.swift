import SwiftUI

struct UpdatePromptView: View {
    @Bindable var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NeonText(text: "UPDATE", color: Theme.magenta, size: 16, tracking: 3)
            content
            actions
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.ink)
        .interactiveDismissDisabled(!updater.canCancel)
    }

    @ViewBuilder
    private var content: some View {
        switch updater.phase {
        case .idle:
            Text("No update in progress.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

        case .checking:
            statusRow(title: "Checking GitHub…", detail: UpdateConfig.repositoryDisplayName, progress: nil)

        case .upToDate:
            Text("You’re on Nightwire \(updater.currentVersionLabel). That’s the latest release.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

        case .available(let release):
            availableCopy(release)

        case .downloading(let fraction):
            statusRow(
                title: "Downloading \(UpdateConfig.assetName)…",
                detail: "Nightwire will not install until you confirm.",
                progress: fraction
            )

        case .readyToInstall(let release):
            Text("Download finished. Install Nightwire \(release.marketingVersion)? This replaces the running app at:")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(Bundle.main.bundleURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.cyan)
                .textSelection(.enabled)

        case .installing:
            statusRow(title: "Installing…", detail: "Replacing Nightwire.app", progress: nil)

        case .installed(let version):
            Text("Nightwire \(version) is installed. Relaunch to use the new version.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

        case .failed(let message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.hotPink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            switch updater.phase {
            case .available:
                Button("Not now") { updater.dismissPrompt() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                Button("Skip this version") { updater.skipAvailableVersion() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textMute)
                Spacer()
                primaryButton("Download & install") {
                    Task { await updater.startDownload() }
                }

            case .downloading:
                Button("Cancel") { updater.dismissPrompt() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                Spacer()

            case .readyToInstall:
                Button("Cancel") { updater.dismissPrompt() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                primaryButton("Install") {
                    Task { await updater.installDownloadedUpdate() }
                }

            case .installed:
                Button("Later") { updater.dismissPrompt() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                primaryButton("Relaunch") {
                    updater.relaunch()
                }

            case .checking, .installing:
                Spacer()

            case .idle, .upToDate, .failed:
                Spacer()
                Button("OK") {
                    updater.dismissPrompt()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.cyan)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private func availableCopy(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nightwire \(release.marketingVersion) is available. You’re on \(updater.currentVersionLabel).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }

            Text("Nothing is downloaded until you choose Download & install.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMute)
        }
    }

    private func statusRow(title: String, detail: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(Theme.cyan)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textMute)
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.void)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.magenta)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
