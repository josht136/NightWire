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
        }
        .padding(14)
        .frame(width: 230)
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
}
