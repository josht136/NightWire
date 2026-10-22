import SwiftUI

@main
struct NightwireApp: App {
    @State private var store = NetworkStatusStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
