import SwiftUI

struct SettingsPopover: View {
    @Bindable var settings: AppSettings
    var onApplyConfig: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPTIONS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(Theme.cyan)

            toggle("Start at login", isOn: loginBinding)
            toggle("Change notifications", isOn: $settings.notificationsEnabled)
            toggle("Auto-track gateway", isOn: $settings.autoTrackGateway)

            if let error = settings.loginError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.hotPink)
            }

            Button("Apply network config…") {
                onApplyConfig()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.magenta)

            updatesSection
        }
        .padding(14)
        .frame(width: 248)
        .background(Theme.ink.opacity(0.45))
        .onAppear { settings.refreshLoginStatus() }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { settings.loginAtStartup },
            set: { settings.setLoginAtStartup($0) }
        )
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPDATES")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(Theme.cyan)
                .padding(.top, 4)

            Text("Nightwire \(AppUpdater.shared.currentVersionLabel)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textDim)

            Button("Check for updates…") {
                Task { await AppUpdater.shared.checkNow() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.magenta)
            .disabled(isChecking)

            SecureField("GitHub token (private repo)", text: $settings.githubToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .help("Optional. Needed to see releases while \(UpdateConfig.repositoryDisplayName) is private. Stored on this Mac.")

            Text("Token stays on this Mac. Public releases do not need one.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isChecking: Bool {
        if case .checking = AppUpdater.shared.phase { return true }
        return false
    }
}
