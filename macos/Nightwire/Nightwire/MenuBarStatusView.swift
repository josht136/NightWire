import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @Bindable var network: NetworkStatusStore

    var body: some View {
        let iface = network.snapshot.primary
        let mode = iface?.configuration.rawValue ?? "—"
        let ip = iface?.ipv4 ?? "No IP"
        Text("\(mode)  \(ip)")
            .monospacedDigit()
    }
}

struct MenuBarStatusView: View {
    @Bindable var network: NetworkStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let iface = network.snapshot.primary {
                Text("NIGHTWIRE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Theme.magenta)
                Text("\(iface.configuration.rawValue)  ·  \(iface.ipv4)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(iface.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
                Text("↓ \(RateFormat.bits(network.downBps))   ↑ \(RateFormat.bits(network.upBps))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.cyan)
            } else {
                Text("No active IPv4 interface")
                    .foregroundStyle(Theme.textMute)
            }

            Divider()

            Button("Open Nightwire") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Nightwire" || $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Button("Refresh") {
                network.refreshNow()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
