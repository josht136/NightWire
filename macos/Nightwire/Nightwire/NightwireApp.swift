import AppKit
import SwiftUI

enum NightwireWindowID {
    static let details = "details"
}

@main
struct NightwireApp: App {
    @State private var monitor = PingMonitor()
    @State private var network = NetworkStatusStore.shared
    @State private var settings = AppSettings.shared
    @State private var updater = AppUpdater.shared

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
                .task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    await updater.checkOnLaunch()
                }
                .sheet(isPresented: promptBinding) {
                    UpdatePromptView(updater: updater)
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.checkNow() }
                }
            }
        }

        Window("Details", id: NightwireWindowID.details) {
            NetworkDetailsWindow(store: network)
                .frame(minWidth: 620, minHeight: 440)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarStatusView(network: network)
        } label: {
            MenuBarLabel(network: network)
        }
        .menuBarExtraStyle(.window)
    }

    private var promptBinding: Binding<Bool> {
        Binding(
            get: { updater.showPrompt },
            set: { updater.setPromptPresented($0) }
        )
    }
}
