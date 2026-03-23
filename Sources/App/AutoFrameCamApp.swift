import SwiftUI

@main
struct AutoFrameCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 650)
    }
}

