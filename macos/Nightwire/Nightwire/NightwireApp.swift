import AppKit
import SwiftUI

@main
struct NightwireApp: App {
    @State private var monitor = PingMonitor()
    @State private var network = NetworkStatusStore()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup("Nightwire") {
            ContentView(monitor: monitor, network: network, settings: settings)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                    monitor.start()
                    network.start()
                    monitor.syncGateway(network.snapshot.primary?.gateway)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Nightwire") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Nightwire"
                    ])
                }
            }
        }

        MenuBarExtra {
            MenuBarStatusView(network: network)
        } label: {
            MenuBarLabel(network: network)
        }
        .menuBarExtraStyle(.window)
    }
}
