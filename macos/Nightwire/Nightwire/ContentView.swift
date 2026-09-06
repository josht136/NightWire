import SwiftUI

struct ContentView: View {
    @Bindable var monitor: PingMonitor
    @Bindable var network: NetworkStatusStore
    @Bindable var settings: AppSettings
    @State private var showSettings = false
    @State private var showApplyConfig = false

    var body: some View {
        ZStack {
            SynthwaveBackdrop()

            VStack(spacing: 0) {
                TitleBar(monitor: monitor, showSettings: $showSettings)
                .padding(.top, 10)
                .padding(.horizontal, 18)

                NetworkStatusView(store: network)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                ThroughputStrip(store: network)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                HStack(alignment: .top, spacing: 16) {
                    SidebarView(monitor: monitor)
                        .frame(width: 312)
                    ChartWorkspaceView(monitor: monitor)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 10)
            }
        }
        .ignoresSafeArea()
        .onChange(of: network.snapshot.primary?.gateway) { _, gateway in
            monitor.syncGateway(gateway)
        }
        .onChange(of: settings.autoTrackGateway) { _, enabled in
            if enabled {
                monitor.syncGateway(network.snapshot.primary?.gateway)
            }
        }
        .popover(isPresented: $showSettings, arrowEdge: .top) {
            SettingsPopover(settings: settings) {
                showSettings = false
                showApplyConfig = true
            }
        }
        .sheet(isPresented: $showApplyConfig) {
            ApplyConfigView(store: network)
        }
    }
}

struct TitleBar: View {
    @Bindable var monitor: PingMonitor
    @Binding var showSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            NeonText(text: "NIGHTWIRE", color: Theme.magenta, size: 24, tracking: 5)

            Text("Network Tool")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(Theme.cyan.opacity(0.8))
                .shadow(color: Theme.cyan.opacity(0.45), radius: 8)

            Spacer()

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
            .help("Options")

            HStack(spacing: 8) {
                Circle()
                    .fill(monitor.isRunning ? Theme.cyan : Theme.magenta)
                    .frame(width: 8, height: 8)
                    .shadow(color: (monitor.isRunning ? Theme.cyan : Theme.magenta).opacity(0.9), radius: 8)
                Text(monitor.isRunning ? "LIVE" : "IDLE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .padding(.leading, 62)
        .padding(.trailing, 8)
    }
}
